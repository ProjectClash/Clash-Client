import Foundation
import ClashClientUI

 
 
 
 
struct ProxiesOverviewModel: Equatable, Sendable {
    static let empty = ProxiesOverviewModel(
        proxies: [], groups: [], providers: [], ungrouped: []
    )

     
     
     
     
    var catalogRefusal: String? = nil
     
     
     
     
    var catalogUnavailable = false

    struct Proxy: Identifiable, Hashable, Sendable {
        var id: String { name }
        let name: String
        let type: String
    }

    struct Member: Hashable, Sendable {
        let name: String
        let type: String
        let isGroup: Bool
         
         
         
         
         
         
         
        let chainedThrough: String?
         
         
        let placeholderType: String?

        init(
            name: String,
            type: String,
            isGroup: Bool,
            chainedThrough: String? = nil,
            placeholderType: String? = nil
        ) {
            self.name = name
            self.type = type
            self.isGroup = isGroup
            self.chainedThrough = chainedThrough
            self.placeholderType = placeholderType
        }

         
         
         
         
        func withProtocol(_ kernelType: String?) -> Member {
            guard !isGroup, type.isEmpty || type == name, let kernelType, !kernelType.isEmpty else { return self }
            return Member(name: name, type: kernelType, isGroup: false,
                          chainedThrough: chainedThrough, placeholderType: placeholderType)
        }
    }

    struct Group: Identifiable, Hashable, Sendable {
        var id: String { name }
        let name: String
        let type: String
        let members: [Member]
        let configuredSelection: String?
         
         
         
         
         
         
        var defaultSelection: String? = nil
         
         
         
         
        var emptyFallback: String? = nil
         
         
         
         
         
         
        var hidden: Bool = false
         
         
         
         
         
         
        var isSynthesized: Bool = false
         
         
         
        var icon: String? = nil
         
         
         
         
        var drawsFromProviders: [String] = []
         
         
        var memberTotal: Int? = nil
         
         
        var carriedSelection: String? = nil

        private var normalizedType: String {
            type.lowercased()
        }

        private var isManual: Bool {
            ["select", "selector"].contains(normalizedType)
        }

         
         
         
         
        var allowsMemberChoice: Bool { isManual || canBeUnpinned }

         
         
         
         
         
         
         
         
        var canBeUnpinned: Bool {
            ["url-test", "urltest", "fallback"].contains(normalizedType)
        }

         
         
         
        var allowsOfflineConfiguredRoute: Bool { isManual || configuredSelection != nil }
    }

    struct Provider: Identifiable, Hashable, Sendable {
        var id: String { name }
        let name: String
        let type: String
        var nodeCount: Int? = nil
         
         
         
         
         
         
         
         
        var note: ProviderNote? = nil
         
        var url: String? = nil
    }

    let proxies: [Proxy]
    let groups: [Group]
    let providers: [Provider]
    let ungrouped: [Proxy]

     
     
     
     
     
     
    var visibleGroups: [Group] {
        groups.filter { !$0.hidden }
    }

     
     
     
    static func emptyGroupNote(drawsFrom providerNames: [String], providers: [Provider]) -> ProviderNote? {
        for name in providerNames {
            if let provider = providers.first(where: { $0.name == name }),
               (provider.nodeCount ?? 0) == 0, let note = provider.note, note.isShown {
                return note
            }
        }
        return nil
    }

     
     
     
     
     
     
     
    func annotatingEmptyProviders(unusable: [String: String] = [:], downloading: Set<String> = [],
                                  failures: [String: ProviderNote] = [:]) -> ProxiesOverviewModel {
        var annotated = ProxiesOverviewModel(
            proxies: proxies,
            groups: groups,
            providers: providers.map { provider in
                guard (provider.nodeCount ?? 0) == 0 else { return provider }
                var provider = provider
                if let notice = unusable[provider.name] {
                     
                    provider.note = .failed(.verbatim(notice))
                } else if let url = provider.url, downloading.contains(url) {
                    provider.note = .downloading
                } else if let url = provider.url, let failure = failures[url] {
                    provider.note = failure
                } else if provider.note == nil, provider.type == "http" {
                    provider.note = .notDownloadedYet
                }
                return provider
            },
            ungrouped: ungrouped
        )
        annotated.catalogRefusal = catalogRefusal
        annotated.catalogUnavailable = catalogUnavailable
        return annotated
    }

     
     
     
    func explainingEmptyProviders(sourceYAML: String?, catalog: ProviderCatalog?) -> ProxiesOverviewModel {
        var unusable = catalog?.unusableProxyProviders ?? [:]
        let unexplained = providers.contains {
            ($0.nodeCount ?? 0) == 0 && $0.type == "http" && unusable[$0.name] == nil
        }
        if unexplained, let sourceYAML, let plan = try? ConfigTransforms.planResources(mergedYAML: sourceYAML) {
            unusable.merge(ProviderCatalog.unusableProxyProviders(in: plan)) { recorded, _ in recorded }
        }
        return annotatingEmptyProviders(unusable: unusable, downloading: ProviderDownloadActivity.downloading,
                                        failures: ProviderDownloadActivity.recentFailures)
    }

    func group(named name: String) -> Group? {
        groups.first { $0.name == name }
    }

    func resolvedConfiguredRoute(
        forGroupNamed name: String
    ) -> String? {
         
         
         
        let selections = Dictionary(
            groups.compactMap { group in
                group.configuredSelection.map {
                    (group.name, $0)
                }
            },
            uniquingKeysWith: { first, _ in first }
        )
        return resolvedRoute(
            from: selections[name],
            selectionsByGroup: selections
        )
    }

    func resolvedRoute(
        from initial: String?,
        selectionsByGroup: [String: String]
    ) -> String? {
        guard var current = initial?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
            !current.isEmpty
        else {
            return nil
        }
        var visited = Set<String>()
        while group(named: current) != nil {
            guard visited.insert(current).inserted,
                  let next = selectionsByGroup[current]?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                  !next.isEmpty else {
                return nil
            }
            current = next
        }
        return current
    }

     
     
     
     
     
     
     
     
     
     
     
    static func cached(sourceYAML: String?) -> ProxiesOverviewModel {
        guard let sourceYAML else { return .empty }
        cacheLock.lock()
        if let entry = cacheEntry, entry.source == sourceYAML {
            cacheLock.unlock()
            return entry.model
        }
        cacheLock.unlock()

         
         
        let started = DispatchTime.now()
        let model = make(sourceYAML: sourceYAML)
        ClashPageProbe.stamp(
            "projection-miss",
            milliseconds: Double(
                DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds
            ) / 1_000_000
        )

        cacheLock.lock()
        cacheEntry = (sourceYAML, model)
        cacheLock.unlock()
        return model
    }

    nonisolated(unsafe) private static var cacheEntry: (
        source: String,
        model: ProxiesOverviewModel
    )?
    private static let cacheLock = NSLock()

    static func make(
        sourceYAML: String?,
        selectedMap: [String: String] = [:],
        providerNodes: [String: [Proxy]] = [:],
        notes: [String: ProviderNote] = [:]
    ) -> ProxiesOverviewModel {
        guard let yaml = sourceYAML else { return .empty }
         
         
         
         
         
        let reduced = yaml.utf8.count > NodesInventoryProjection.wholeReadBytes
            ? ConfigurationSections.droppingLong(["proxies", "rules"], from: yaml) : nil
        guard let parsed = ConfigTransforms.parsedRoot(forYAML: reduced ?? yaml) else {
            return .empty
        }
        let root = parsed.root
        let json = parsed.json
        let nodesReadHere = reduced == nil && root["x-clash-node-library"] == nil

        let proxies: [Proxy] =
            ((root["proxies"] as? [Any]) ?? []).compactMap {
                guard let dictionary = $0 as? [String: Any],
                      let name = dictionary["name"] as? String else {
                    return nil
                }
                return Proxy(
                    name: name,
                    type: (dictionary["type"] as? String) ?? ""
                )
            }
         
         
         
         
         
        let nodeTypes = Dictionary(
            proxies.map { ($0.name, $0.type) },
            uniquingKeysWith: { first, _ in first }
        )
         
         
        var nodeDialers: [String: String] = [:]
        for entry in (root["proxies"] as? [Any]) ?? [] {
            guard let dictionary = entry as? [String: Any],
                  let name = dictionary["name"] as? String,
                  let dialer = (dictionary["dialer-proxy"] as? String)?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !dialer.isEmpty else { continue }
            nodeDialers[name] = dialer
        }
        let rawGroups =
            ((root["proxy-groups"] as? [Any]) ?? []).compactMap {
                $0 as? [String: Any]
            }
        var groupTypes: [String: String] = [:]
        for dictionary in rawGroups {
            if let name = dictionary["name"] as? String {
                groupTypes[name] =
                    (dictionary["type"] as? String) ?? ""
            }
        }

        let groups: [Group] = rawGroups.compactMap { dictionary in
            guard let name = dictionary["name"] as? String else {
                return nil
            }
            let explicitNames =
                ((dictionary["proxies"] as? [Any]) ?? [])
                    .compactMap { $0 as? String }

            let flag = { (key: String) in
                (dictionary[key] as? Bool) ?? false
            }
            let includeAll = flag("include-all")
            let includeAllProxies = includeAll || flag("include-all-proxies")
            let includeAllProviders = includeAll || flag("include-all-providers")

             
             
             
             
             
             
             
             
             
             
             
             
             
            let filterExpressions = compiledExpressions(
                dictionary["filter"] as? String
            )
            let excludeExpressions = compiledExpressions(
                dictionary["exclude-filter"] as? String
            )
             
             
            let declaredProviders =
                (root["proxy-providers"] as? [String: Any]) ?? [:]
            let useReferences =
                ((dictionary["use"] as? [Any]) ?? []).compactMap { $0 as? String }
            let unknownExplicit = explicitNames.contains { name in
                nodeTypes[name] == nil
                    && groupTypes[name] == nil
                    && !builtinProxyNames.contains(name)
            }
             
             
             
             
            let unknownProvider = !includeAllProviders
                && useReferences.contains { reference in
                    declaredProviders[reference] == nil
                        && providerNodes[reference] == nil
                }
            let filtersRefusedByKernel =
                filterExpressions == nil || excludeExpressions == nil
                    || (nodesReadHere && unknownExplicit) || unknownProvider
            let excludedTypes = Set(
                ((dictionary["exclude-type"] as? String) ?? "")
                    .split(separator: "|")
                    .map { $0.lowercased() }
                    .filter { !$0.isEmpty }
            )
            func excludedByType(name: String, rawType: String) -> Bool {
                 
                 
                 
                 
                 
                let canonical: String
                if nodeTypes[name] == nil, groupTypes[name] == nil,
                   let builtin = canonicalTypesByBuiltinName[name] {
                    canonical = builtin
                } else {
                    canonical = canonicalAdapterType(rawType)
                }
                return excludedTypes.contains(canonical)
            }
            func firstMatchingExpression(_ name: String) -> Int? {
                guard let filterExpressions, !filterExpressions.isEmpty else {
                    return nil
                }
                return filterExpressions.firstIndex {
                    matchesExpression($0, name)
                }
            }
            func admits(_ node: Proxy) -> Bool {
                if let filterExpressions, !filterExpressions.isEmpty,
                   firstMatchingExpression(node.name) == nil {
                    return false
                }
                if let excludeExpressions,
                   excludeExpressions.contains(where: {
                       matchesExpression($0, node.name)
                   }) {
                    return false
                }
                return !excludedByType(name: node.name, rawType: node.type)
            }

             
             
             
             
             
             
            var members = explicitNames
                .map { member -> Member in
                    if let groupType = groupTypes[member] {
                        return Member(
                            name: member,
                            type: groupType,
                            isGroup: true
                        )
                    }
                    return Member(
                        name: member,
                        type: nodeTypes[member] ?? member,
                        isGroup: false,
                        chainedThrough: nodeDialers[member]
                    )
                }
                .filter { member in
                    if let excludeExpressions,
                       excludeExpressions.contains(where: {
                           matchesExpression($0, member.name)
                       }) {
                        return false
                    }
                    return !excludedByType(
                        name: member.name,
                        rawType: member.type
                    )
                }

             
             
             
             
             
             
             
            if includeAllProxies {
                var seen = Set(members.map(\.name))
                for node in proxies.filter({ admits($0) })
                    .sorted(by: { $0.name < $1.name })
                where seen.insert(node.name).inserted {
                    members.append(
                        Member(
                            name: node.name,
                            type: node.type,
                            isGroup: false,
                            chainedThrough: nodeDialers[node.name]
                        )
                    )
                }
            }

             
             
             
             
             
             
             
             
             
             
             
             
             
            let providerReferences = includeAllProviders
                ? Set(declaredProviders.keys)
                    .union(providerNodes.keys)
                    .sorted()
                : useReferences
            var seenMembers = Set(members.map(\.name))
            for reference in providerReferences {
                let resolved = providerNodes[reference]
                    ?? inlinePayloadNodes(root, name: reference)
                 
                 
                 
                 
                let admitted: [Proxy]
                if let filterExpressions, filterExpressions.count > 1 {
                    admitted = resolved
                        .filter { admits($0) }
                        .enumerated()
                        .sorted { lhs, rhs in
                            let l = firstMatchingExpression(lhs.element.name)
                                ?? filterExpressions.count
                            let r = firstMatchingExpression(rhs.element.name)
                                ?? filterExpressions.count
                            return l == r
                                ? lhs.offset < rhs.offset
                                : l < r
                        }
                        .map(\.element)
                } else {
                    admitted = resolved.filter { admits($0) }
                }
                 
                 
                 
                 
                for node in admitted
                where seenMembers.insert(node.name).inserted {
                    members.append(
                        Member(
                            name: node.name,
                            type: node.type,
                            isGroup: false
                        )
                    )
                }
            }

             
             
             
             
             
             
             
            let contributingSources =
                (explicitNames.isEmpty && !includeAllProxies ? 0 : 1)
                    + providerReferences.count
            if let filterExpressions, filterExpressions.count > 1,
               contributingSources > 1 {
                members = members.enumerated().sorted { lhs, rhs in
                    let l = firstMatchingExpression(lhs.element.name)
                        ?? filterExpressions.count
                    let r = firstMatchingExpression(rhs.element.name)
                        ?? filterExpressions.count
                    return l == r ? lhs.offset < rhs.offset : l < r
                }.map(\.element)
            }

             
             
             
             
             
             
            if filtersRefusedByKernel {
                members = []
            }
            if members.isEmpty, !filtersRefusedByKernel {
                let fallbackName =
                    (dictionary["empty-fallback"] as? String) ?? "COMPATIBLE"
                 
                 
                 
                 
                 
                 
                let isNode = nodeTypes[fallbackName] != nil
                let isGroup = groupTypes[fallbackName] != nil
                if (isNode || builtinProxyNames.contains(fallbackName)), !isGroup {
                    members = [
                        Member(
                            name: fallbackName,
                            type: nodeTypes[fallbackName] ?? fallbackName,
                            isGroup: false
                        )
                    ]
                }
            }

            let type = (dictionary["type"] as? String) ?? ""
            let storedSelection = selectedMap[name].flatMap { selected in
                members.contains(where: { $0.name == selected })
                    ? selected
                    : nil
            }
             
             
             
             
             
             
             
             
             
             
             
            let configuredDefault = (dictionary["default-selected"] as? String)
                .flatMap { named in
                    members.contains(where: { $0.name == named }) ? named : nil
                }
            let defaultSelection =
                ProxyGroupControlKind(rawType: type) == .manual
                    ? (configuredDefault ?? members.first?.name)
                    : nil
            let emptyFallback = (dictionary["empty-fallback"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "COMPATIBLE"
            return Group(
                name: name,
                type: type,
                members: members,
                configuredSelection:
                    storedSelection ?? defaultSelection,
                defaultSelection: defaultSelection,
                emptyFallback: emptyFallback,
                hidden: Self.isHiddenFlag(dictionary["hidden"]),
                icon: (dictionary["icon"] as? String)
                    .flatMap { $0.isEmpty ? nil : $0 },
                drawsFromProviders: providerReferences.filter { declaredProviders[$0] != nil }
            )
        }

        let providerSpecifications =
            (root["proxy-providers"] as? [String: Any]) ?? [:]
         
         
         
         
        let providers = ConfiguredProxyOrder
            .sortedProviderNames(Array(providerSpecifications.keys), inJSON: json)
            .map { name in
            let specification =
                providerSpecifications[name] as? [String: Any]
            let inlineCount = inlinePayloadNodes(root, name: name).count
            return Provider(
                name: name,
                type: (specification?["type"] as? String) ?? "",
                nodeCount: providerNodes[name]?.count
                    ?? (inlineCount > 0 ? inlineCount : nil),
                note: notes[name],
                url: specification?["url"] as? String
            )
        }

        var seenNames = Set(proxies.map(\.name))
        var searchableProxies = proxies
        for providerName in providerNodes.keys.sorted() {
            for node in providerNodes[providerName] ?? []
            where seenNames.insert(node.name).inserted {
                searchableProxies.append(node)
            }
        }
        let referenced = Set(
            groups.flatMap { $0.members.map(\.name) }
        )
         
         
         
        let ungrouped = proxies.filter {
            !referenced.contains($0.name)
        }
        return ProxiesOverviewModel(
            proxies: searchableProxies,
            groups: groups + synthesizedGlobal(
                declared: groups,
                proxies: proxies
            ),
            providers: providers,
            ungrouped: ungrouped
        )
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func applying(selectedMap: [String: String]) -> ProxiesOverviewModel {
        var applied = ProxiesOverviewModel(
            proxies: proxies,
            groups: groups.map { group in
                guard !group.isSynthesized else { return group }
                let stored = selectedMap[group.name].flatMap { selected in
                    group.members.contains(where: { $0.name == selected })
                        ? selected
                        : nil
                }
                let selection = stored ?? group.defaultSelection
                guard selection != group.configuredSelection else {
                    return group
                }
                return Group(
                    name: group.name,
                    type: group.type,
                    members: group.members,
                    configuredSelection: selection,
                    defaultSelection: group.defaultSelection,
                     
                     
                    emptyFallback: group.emptyFallback,
                    hidden: group.hidden,
                    isSynthesized: group.isSynthesized,
                    icon: group.icon,
                    drawsFromProviders: group.drawsFromProviders
                )
            },
            providers: providers,
            ungrouped: ungrouped
        )
         
        applied.catalogRefusal = catalogRefusal
        applied.catalogUnavailable = catalogUnavailable
        return applied
    }

    private static func synthesizedGlobal(
        declared: [Group],
        proxies: [Proxy]
    ) -> [Group] {
        guard !declared.contains(where: { $0.name == "GLOBAL" }) else {
            return []
        }
        let builtIn = ["DIRECT", "REJECT"].map {
            Member(name: $0, type: $0.capitalized, isGroup: false)
        }
        let nodes = proxies.map {
            Member(name: $0.name, type: $0.type, isGroup: false)
        }
        let groups = declared.map {
            Member(name: $0.name, type: $0.type, isGroup: true)
        }
        return [
            Group(
                name: "GLOBAL",
                type: "Selector",
                members: builtIn + nodes + groups,
                configuredSelection: nil,
                isSynthesized: true
            )
        ]
    }

     
     
     
     
     
    private static func compiledExpressions(
        _ raw: String?
    ) -> [NSRegularExpression]? {
        guard let raw, !raw.isEmpty else { return [] }
        var expressions: [NSRegularExpression] = []
        for piece in raw.split(separator: "`", omittingEmptySubsequences: false) {
            guard let regex = try? NSRegularExpression(
                pattern: String(piece)
            ) else {
                return nil
            }
            expressions.append(regex)
        }
        return expressions
    }

    private static func matchesExpression(
        _ regex: NSRegularExpression,
        _ name: String
    ) -> Bool {
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return regex.firstMatch(in: name, range: range) != nil
    }

    private static func matches(_ pattern: String, _ name: String) -> Bool {
         
         
         
         
        pattern.split(separator: "`", omittingEmptySubsequences: false)
            .contains { expression in
                guard let regex = try? NSRegularExpression(
                    pattern: String(expression)
                ) else {
                    return false
                }
                let range = NSRange(name.startIndex..<name.endIndex, in: name)
                return regex.firstMatch(in: name, range: range) != nil
            }
    }

     
     
    static let builtinProxyNames: Set<String> = [
        "COMPATIBLE", "DIRECT", "REJECT", "REJECT-DROP", "PASS", "PASS-RULE",
    ]

     
     
     
     
    private static let canonicalTypesByBuiltinName: [String: String] = [
        "DIRECT": "direct",
        "REJECT": "reject",
        "REJECT-DROP": "rejectdrop",
        "PASS": "pass",
        "PASS-RULE": "passrule",
        "COMPATIBLE": "compatible",
    ]

     
     
     
     
     
    private static let canonicalAdapterTypesByRawType: [String: String] = [
        "ss": "shadowsocks",
        "ssr": "shadowsocksr",
        "socks5": "socks5",
        "http": "http",
        "vmess": "vmess",
        "vless": "vless",
        "snell": "snell",
        "trojan": "trojan",
        "hysteria": "hysteria",
        "hysteria2": "hysteria2",
        "wireguard": "wireguard",
        "tuic": "tuic",
        "shadowquic": "shadowquic",
        "direct": "direct",
        "dns": "dns",
        "ssh": "ssh",
        "mieru": "mieru",
        "anytls": "anytls",
        "reject": "reject",
        "rematch": "rematch",
        "sudoku": "sudoku",
        "masque": "masque",
        "trusttunnel": "trusttunnel",
        "openvpn": "openvpn",
        "tailscale": "tailscale",
         
         
         
        "gost-relay": "gostrelay",
         
        "select": "selector",
        "url-test": "urltest",
        "fallback": "fallback",
        "load-balance": "loadbalance",
        "relay": "relay",
    ]

    static func canonicalAdapterType(_ rawType: String) -> String {
        let raw = rawType.lowercased()
        return canonicalAdapterTypesByRawType[raw] ?? raw
    }

    private static func inlinePayloadNodes(
        _ root: [String: Any],
        name: String
    ) -> [Proxy] {
        guard let specification =
                (root["proxy-providers"] as? [String: Any])?[name]
                    as? [String: Any],
              (specification["type"] as? String)?.lowercased()
                == "inline",
              let payload = specification["payload"] as? [Any] else {
            return []
        }
        return payload.compactMap {
            guard let dictionary = $0 as? [String: Any],
                  let nodeName = dictionary["name"] as? String else {
                return nil
            }
            return Proxy(
                name: nodeName,
                type: (dictionary["type"] as? String) ?? ""
            )
        }
    }
}

extension ProxiesOverviewModel {
     
     
     
    static func isHiddenFlag(_ value: Any?) -> Bool {
        switch value {
        case let flag as Bool: return flag
        case let text as String: return text.lowercased() == "true"
        default: return false
        }
    }

     
    var withoutCatalogRefusal: ProxiesOverviewModel {
        var model = self
        model.catalogRefusal = nil
        model.catalogUnavailable = false
        return model
    }

     
     
     
     
     
     
     
     
    func applyingKernelCatalog(_ data: Data) -> ProxiesOverviewModel? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let decoded = root["proxies"] as? [String: Any] else { return nil }
         
        let kernelProxies = ModuleRouteHiding.stripping(decoded, hiding: ModuleRouteHiding.hiddenNames())
        let kernelProviders = root["providers"] as? [String: Any] ?? [:]
        let providerErrors = root["providerErrors"] as? [String: String] ?? [:]

         
         
         
         
        var nodeTypes: [String: String] = [:]
        for (name, value) in kernelProxies {
            guard let type = (value as? [String: Any])?["type"] as? String else { continue }
            nodeTypes[name] = Self.configSpelling(ofKernelType: type)
        }
        var providerNodes: [String: [Proxy]] = [:]
        for (name, value) in kernelProviders {
            guard let provider = value as? [String: Any],
                  (provider["vehicleType"] as? String) != "Compatible" else { continue }
            let nodes = (provider["proxies"] as? [[String: Any]] ?? []).compactMap { node -> Proxy? in
                guard let nodeName = node["name"] as? String else { return nil }
                return Proxy(name: nodeName, type: nodeTypes[nodeName]
                    ?? Self.configSpelling(ofKernelType: node["type"] as? String ?? ""))
            }
            providerNodes[name] = nodes
            for node in nodes where nodeTypes[node.name] == nil { nodeTypes[node.name] = node.type }
        }
        for proxy in proxies { nodeTypes[proxy.name] = proxy.type }
        let groupNames = Set(groups.map(\.name))

        let rebuilt = groups.map { group -> Group in
            guard let kernel = kernelProxies[group.name] as? [String: Any],
                  let all = kernel["all"] as? [String] else { return group }
            let known = Dictionary(group.members.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
            let members = all.map { name -> Member in
                let kernelType = ((kernelProxies[name] as? [String: Any])?["type"] as? String)
                    .map(Self.configSpelling(ofKernelType:))
                if let member = known[name] { return member.withProtocol(kernelType) }
                return Member(
                    name: name,
                    type: groupNames.contains(name)
                        ? (self.group(named: name)?.type ?? "")
                        : (nodeTypes[name] ?? kernelType ?? ""),
                    isGroup: groupNames.contains(name)
                )
            }
             
             
             
             
             
             
             
            let isAutomatic = group.canBeUnpinned
            let isManual = ["select", "selector"].contains(group.type.lowercased())
            let kernelNow = (kernel["now"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let projected = group.configuredSelection.flatMap { all.contains($0) ? $0 : nil }
            let selection: String? = group.isSynthesized
                ? nil
                : isManual ? (kernelNow ?? projected)
                : isAutomatic ? projected
                : nil
            let icon = (kernel["icon"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? group.icon
            let fallback = (kernel["emptyFallback"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? group.emptyFallback
             
             
             
             
             
            let defaultSelection: String? = isManual
                ? (kernelNow ?? group.defaultSelection.flatMap { all.contains($0) ? $0 : nil } ?? all.first)
                : nil
            return Group(
                name: group.name,
                type: group.type,
                members: members,
                configuredSelection: selection,
                defaultSelection: defaultSelection,
                emptyFallback: fallback,
                hidden: (kernel["hidden"] as? Bool) ?? group.hidden,
                isSynthesized: group.isSynthesized,
                icon: icon,
                drawsFromProviders: group.drawsFromProviders,
                 
                 
                 
                 
                memberTotal: (kernel["total"] as? Int)
                    .map { $0 - ((kernel[ModuleRouteHiding.hiddenMembersKey] as? [String])?.count ?? 0) }
                    .flatMap { $0 > all.count ? $0 : nil }
            )
        }

         
         
         
         
         
         
         
         
         
         
        let builtIns: Set<String> = ["direct", "reject", "reject-drop", "pass", "passrule", "compatible", "dns"]
        let groupish = Set(kernelProxies.compactMap { name, value in
            ((value as? [String: Any])?["all"] != nil) ? name : nil
        })
        let kernelInline = Set(kernelProxies.keys.filter { name in
            !groupish.contains(name)
                && !Self.builtinProxyNames.contains(name)
                && !builtIns.contains(nodeTypes[name] ?? "")
        })
        var seen = Set<String>()
        var inline: [Proxy] = []
        for proxy in proxies where kernelInline.contains(proxy.name) && seen.insert(proxy.name).inserted {
            inline.append(proxy)
        }
        for name in kernelInline.sorted() where seen.insert(name).inserted {
            inline.append(Proxy(name: name, type: nodeTypes[name] ?? ""))
        }
        var searchable = inline
        for provider in providers {
            for node in providerNodes[provider.name] ?? [] where seen.insert(node.name).inserted {
                searchable.append(node)
            }
        }
         
         
         
         
        let referenced = Set(rebuilt.filter { !$0.isSynthesized && $0.name != "GLOBAL" }.flatMap { $0.members.map(\.name) })
        return ProxiesOverviewModel(
            proxies: searchable,
            groups: rebuilt,
            providers: providers.map { provider in
                var provider = provider
                if let nodes = providerNodes[provider.name] {
                    provider.nodeCount = nodes.count
                     
                     
                     
                     
                     
                    if !nodes.isEmpty, provider.note?.isTunnelWord != true { provider.note = nil }
                }
                if let failure = providerErrors[provider.name] { provider.note = .failed(.verbatim(failure)) }
                return provider
            },
            ungrouped: inline.filter { !referenced.contains($0.name) }
        )
    }

     
     
     
    static func configSpelling(ofKernelType type: String) -> String {
        kernelTypeSpellings[type] ?? type.lowercased()
    }

    private static let kernelTypeSpellings: [String: String] = [
            "Shadowsocks": "ss", "ShadowsocksR": "ssr", "Socks5": "socks5", "Http": "http",
            "Vmess": "vmess", "Vless": "vless", "Trojan": "trojan", "Snell": "snell",
            "Hysteria": "hysteria", "Hysteria2": "hysteria2", "Tuic": "tuic", "WireGuard": "wireguard",
            "Ssh": "ssh", "AnyTLS": "anytls", "Mieru": "mieru", "Direct": "direct", "Reject": "reject",
            "RejectDrop": "reject-drop", "Dns": "dns", "Pass": "pass", "Compatible": "compatible",
            "Selector": "select", "URLTest": "url-test", "Fallback": "fallback",
            "LoadBalance": "load-balance", "Relay": "relay",
    ]
}

extension ProxiesOverviewModel {
     
     
     
     
     
     
     
    func resolvedWithKernelCatalog(profileID: String?) -> ProxiesOverviewModel {
        resolvedWithKernelCatalog(input: OfflineProxyCatalogLoader.input(preferredProfileID: profileID))
    }

     
     
    func resolvedWithKernelCatalog(input: OfflineProxyCatalogInput?) -> ProxiesOverviewModel {
        guard let input else { return self }
        do {
             
             
            return applyingKernelCatalog(try OfflineProxyCatalogLoader.catalog(input, holder: nil)) ?? self
        } catch OfflineProxyCatalogError.refused(let reason) {
            var model = self
            model.catalogRefusal = reason
            return model
        } catch {
            var model = self
            model.catalogUnavailable = true
            return model
        }
    }
}
