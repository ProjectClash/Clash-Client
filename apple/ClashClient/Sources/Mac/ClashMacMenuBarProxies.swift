import Foundation
import ClashClientUI

 
 
 
 
 
 
 
struct ClashMacMenuProxyCatalog: Equatable {
    struct Group: Equatable, Identifiable {
        let name: String
        let members: [String]
         
        let now: String
         
         
         
         
         
         
         
         
         
        var checked: String?
         
         
        var type: String = ""
         
         
        var icon: String? = nil
         
         
        var latency: [String: ClashProxyLatencyState] = [:]
         
         
         
         
         
         
         
         
         
         
        var pinsOnRepick = false
         
         
         
        var isEmpty = false
         
        var emptyMembers: Set<String> = []
         
         
         
         
        var memberTotal: Int?
         
         
        var sort: ClashProxiesDisplayPreferences.Sort = .standard
         
         
         
         
        var lastReadings: [String: ClashProxyLatencyState] = [:]
        var id: String { name }

         
         
         
         
         
         
         
        var sortsItsRows: Bool {
            sort != .standard && memberTotal == nil && members.count <= ClashMacMenuProxyCatalog.sortLimit
        }

         
         
         
         
         
        var listed: [String] {
            sortsItsRows ? sort.ordered(members, name: { $0 }, latency: orderReading(of:)) : members
        }

         
         
        func orderReading(of member: String) -> ClashProxyLatencyState {
            let shown = latency[member] ?? .untested
            return shown == .testing ? lastReadings[member] ?? shown : shown
        }
    }

     
     
     
     
     
    static let sortLimit = 10_000

    let groups: [Group]

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func make(
        groups: [ProxyGroup],
        mode: ProxyBrowsingVisibility.Mode,
        delays: [String: Int] = [:],
        testing: Set<String> = [],
        isConnected: Bool = true,
        configuredSelections: [String: String] = [:],
        sort: ClashProxiesDisplayPreferences.Sort = .standard
    ) -> ClashMacMenuProxyCatalog {
        let visible = ProxyBrowsingVisibility.groups(
            groups,
            mode: mode,
            name: \.name,
            isHidden: \.hidden
        )
         
         
         
         
         
         
        let emptyGroups = Set(groups.filter(\.isEmpty).map(\.name))
        let knownGroups = Set(groups.map(\.name))
        let byName = Dictionary(groups.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        return ClashMacMenuProxyCatalog(
            groups: visible.compactMap { group in
                 
                 
                 
                 
                 
                 
                let members = ProxyBrowsingVisibility.members(
                    group.members, of: group.name, mode: mode, name: { $0 }
                )
                guard group.acceptsMemberChoice, !group.members.isEmpty else {
                    return nil
                }
                 
                 
                 
                if group.isEmpty || members.isEmpty {
                    return Group(
                        name: group.name, members: [], now: group.now,
                        checked: nil, type: group.type, icon: group.iconURL, isEmpty: true
                    )
                }
                var latency: [String: ClashProxyLatencyState] = [:]
                var lastReadings: [String: ClashProxyLatencyState] = [:]
                for member in members {
                    if emptyGroups.contains(member) {
                        latency[member] = .untested
                        continue
                    }
                     
                     
                     
                    let measured = group.memberResolvedNames[member] ?? member
                     
                     
                     
                     
                     
                     
                     
                    let reading = group.memberGroupNames.contains(member) && knownGroups.contains(member)
                        ? NodeInventory.routeDelay(from: member, byName: byName, delays: delays)
                        : NodeInventory.memberDelay(measured, in: group, delays: delays)
                    if testing.contains(measured) {
                        latency[member] = .testing
                        if let delay = reading {
                            lastReadings[member] = delay > 0 ? .measured(milliseconds: delay) : .failed
                        }
                    } else if let delay = reading {
                        latency[member] = delay > 0
                            ? .measured(milliseconds: delay)
                            : .failed
                    } else {
                        latency[member] = .untested
                    }
                }
                return Group(
                    name: group.name,
                    members: members,
                    now: group.now,
                    checked: isConnected ? group.now : configuredSelections[group.name],
                    type: group.type,
                    icon: group.iconURL,
                    latency: latency,
                    pinsOnRepick: ProxyGroupControlKind(rawType: group.type)
                        == .automatic,
                    emptyMembers: emptyGroups.intersection(members),
                    memberTotal: group.hasEveryMember ? nil : group.shownMemberTotal,
                    sort: sort,
                    lastReadings: lastReadings
                )
            }
        )
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func configuredSelections(
        offlineGroups groups: [ProxyGroup],
        selectedMap: [String: String]
    ) -> [String: String] {
        groups.reduce(into: [:]) { all, group in
            guard group.acceptsMemberChoice, group.name != ProxyBrowsingVisibility.kernelGlobalGroupName else { return }
            if let pick = selectedMap[group.name], group.members.contains(pick) || !group.hasEveryMember {
                all[group.name] = pick
            } else if ProxyGroupControlKind(rawType: group.type) == .manual, !group.now.isEmpty {
                all[group.name] = group.now
            }
        }
    }
}
