import Foundation
import ClashClientUI
import WidgetKit

 
 
 
 
 
 
 
 
 
 
enum ClashWidgetFactsPublisher {
     
     
     
     
    static var countsWired: Bool { ClashWidgetPlatform.countsWired }

     
     
     
     
     
     
    static func facts(
        activeLabel: String?, effectiveYAML: String?, mode: ClashWidgetMode? = nil,
        storedGlobal: ClashTunnelOutboundMode.StoredGlobalChoice? = nil, now: Date
    ) -> ClashWidgetAppFacts {
        guard let effectiveYAML, !effectiveYAML.isEmpty else {
            return ClashWidgetAppFacts(
                profile: activeLabel, firstGroup: nil, groups: [], mode: mode, countsWired: countsWired,
                globalVerdict: storedGlobal.map(ClashTunnelOutboundMode.storedGlobalVerdict), writtenAt: now
            )
        }
         
         
         
         
         
         
         
         
         
        let declared = ProxiesOverviewModel.make(sourceYAML: effectiveYAML).groups
            .filter { $0.name != "GLOBAL" }
        let groups = declared.map(\.name)
        let firstSelector = declared.first {
            ProxiesOverviewModel.canonicalAdapterType($0.type) == "selector"
        }?.name
        let manualGroups = declared.filter { ProxiesOverviewModel.canonicalAdapterType($0.type) == "selector" }.map(\.name)
        let globalVerdict = storedGlobal.map { ClashTunnelOutboundMode.storedGlobalVerdict($0.reading(manualGroups: manualGroups)) }
         
         
         
        var members: [String: [String]] = [:]
        var selections: [String: String] = [:]
        for group in declared {
             
             
             
             
             
            let named = group.members.filter {
                $0.name != "COMPATIBLE" && ProxiesOverviewModel.canonicalAdapterType($0.type) != "compatible"
            }
            members[group.name] = named.prefix(ClashWidgetMailbox.groupMemberLimit).map(\.name)
            if let selection = group.configuredSelection, named.contains(where: { $0.name == selection }) {
                selections[group.name] = selection
            }
        }
        return ClashWidgetAppFacts(
            profile: activeLabel,
            firstGroup: firstSelector ?? groups.first,
            groups: groups,
            members: members,
            selections: selections,
            mode: mode,
            countsWired: countsWired,
            globalVerdict: globalVerdict,
            writtenAt: now
        )
    }

    static var store: ClashWidgetMailboxStore {
        ClashWidgetMailboxStore(root: ClashAppIdentifiers.appGroupContainer ?? FileManager.default.temporaryDirectory)
    }

     
     
    static func appChoseMode(store: ClashWidgetMailboxStore = store, reload: () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        store.clearModeChoice()
        reload()
    }

     
     
     
     
     
    static func tunnelChanged(reload: () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        reload()
    }

     
     
     
     
     
    static func takeModeChosenOnACard(store: ClashWidgetMailboxStore = store) -> String? {
        guard let choice = store.readModeChoice() else { return nil }
        store.clearModeChoice()
         
         
        if !(choice.at < (lastModeChoiceTaken?.at ?? .distantPast)) { lastModeChoiceTaken = choice }
        return choice.mode.rawValue
    }

     
    static var lastModeChoiceTaken: ClashWidgetModeChoice?

     
     
     
     
     
    static func modeChosen(after date: Date, store: ClashWidgetMailboxStore = store) -> Bool {
        let newest = [store.readModeChoice(), lastModeChoiceTaken].compactMap { $0 }.max { $0.at < $1.at }
        guard let newest, newest.at > date else { return false }
        return newest.mode != .global
    }

    static func write(_ facts: ClashWidgetAppFacts, to store: ClashWidgetMailboxStore) {
        do {
            try store.writeAppFacts(facts)
        } catch {
            ClashLogStore.shared.append(
                "widget facts: not written  \(error.localizedDescription)",
                stream: .app, level: .warning
            )
        }
    }

     
     
     
     
    static func publish(
        activeLabel: String?, mode: ClashWidgetMode? = nil,
        storedGlobal: ClashTunnelOutboundMode.StoredGlobalChoice? = nil, effectiveYAML: String?
    ) {
        Task.detached(priority: .utility) {
            let facts = facts(activeLabel: activeLabel, effectiveYAML: effectiveYAML, mode: mode,
                              storedGlobal: storedGlobal, now: Date())
            write(facts, to: store)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
