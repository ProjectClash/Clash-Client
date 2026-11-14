import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public enum ClashTunnelOutboundMode {
     
     
    public static let runtimeLayerKey = "config.runtime.flclash.v1"


     
    static let modes: Set<String> = ["rule", "global", "direct"]

     
    public static func chosen(in defaults: UserDefaults?) -> String? {
        guard let data = defaults?.data(forKey: runtimeLayerKey),
              let layer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let patchJSON = layer["patchJSON"] as? String else { return nil }
        return chosen(inPatchJSON: patchJSON)
    }

     
     
    public static func chosen(inPatchJSON patchJSON: String) -> String? {
        guard let patch = try? JSONSerialization.jsonObject(with: Data(patchJSON.utf8)) as? [String: Any],
              let mode = (patch["mode"] as? String)?.lowercased(),
              modes.contains(mode) else { return nil }
        return mode
    }

     
     
     
     
    public static let cardChoiceFile = "widgets/mode.json"

     
     
    public static func chosen(in defaults: UserDefaults?, cardsAt container: URL?) -> String? {
        chosenOnACard(in: container) ?? chosen(in: defaults)
    }

     
     
    static func chosenOnACard(in container: URL?) -> String? {
        guard let container,
              let data = try? Data(contentsOf: container.appendingPathComponent(cardChoiceFile)),
              let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let mode = (record["mode"] as? String)?.lowercased(),
              modes.contains(mode) else { return nil }
        return mode
    }

     
     
    public static func applyingChoice(in defaults: UserDefaults?, cardsAt container: URL?, to yaml: String) -> String {
        chosen(in: defaults, cardsAt: container).map { applying($0, to: yaml) } ?? yaml
    }

     
     
     
     
     
     
     
     
     
    public static func firstTextWithAModeWrittenIn(_ published: String, where matches: (String) -> Bool) -> String? {
        for mode in ["rule", "global", "direct"] {
            guard let text = writing(mode, into: published) else { continue }
            if matches(text) { return text }
        }
        return nil
    }

     
     
     
    public static func applying(_ mode: String, to yaml: String) -> String {
        writing(mode, into: yaml) ?? yaml
    }

     
    private static func writing(_ mode: String, into yaml: String) -> String? {
        guard let line = topLevelModeLine(in: yaml) else { return "mode: \(mode)\n" + yaml }
        if value(of: yaml[line]).lowercased() == mode { return nil }
        var replaced = yaml
        replaced.replaceSubrange(line, with: "mode: \(mode)")
        return replaced
    }

     
    private static func topLevelModeLine(in yaml: String) -> Range<String.Index>? {
        var start = yaml.startIndex
        while start < yaml.endIndex {
            let end = yaml[start...].firstIndex(where: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) ?? yaml.endIndex
            let line = yaml[start..<end]
            if isModeKey(line) { return start..<end }
            guard end < yaml.endIndex else { return nil }
            start = yaml.index(after: end)
        }
        return nil
    }

    private static func isModeKey(_ line: Substring) -> Bool {
        for key in ["mode", "\"mode\"", "'mode'"] where line.hasPrefix(key) {
            let rest = line.dropFirst(key.count).drop(while: { $0 == " " || $0 == "\t" })
            if rest.first == ":" { return true }
        }
        return false
    }

     
    private static func value(of line: Substring) -> String {
        guard let colon = line.firstIndex(of: ":") else { return "" }
        var value = line[line.index(after: colon)...]
        if let comment = value.range(of: " #") { value = value[..<comment.lowerBound] }
        return value.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

     

     
     
     
     
    public enum GlobalExit: String, Codable, Equatable, Sendable {
         
        case proxy
         
        case direct
         
        case reject
         
        case other
    }

     
    public static let builtinExits: Set<String> = ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE"]

     
    public static func exit(ofResolved name: String, isGroup: Bool) -> GlobalExit {
        switch name {
        case "DIRECT": return .direct
        case "REJECT", "REJECT-DROP": return .reject
        default: return name.isEmpty || isGroup || builtinExits.contains(name) ? .other : .proxy
        }
    }

     
     
    public struct WalkedGroup: Equatable, Sendable {
        public let now: String?
        public let members: [String]?
        public let listsEveryMember: Bool

        public init(now: String?, members: [String]?, listsEveryMember: Bool = true) {
            self.now = now
            self.members = members
            self.listsEveryMember = listsEveryMember
        }
    }

     
     
    public static let membersRead = 256

     
     
     
     
     
     
    public static func exit(following name: String, group: (String) -> WalkedGroup?) -> GlobalExit? {
        var path: Set<String> = []
        func walk(_ name: String) -> GlobalExit? {
            guard let found = group(name) else { return exit(ofResolved: name, isGroup: false) }
            guard path.insert(name).inserted else { return .other }
            defer { path.remove(name) }
            if let now = found.now, !now.isEmpty { return walk(now) }
            guard let members = found.members, found.listsEveryMember, !members.isEmpty else { return nil }
            var exits: [GlobalExit] = []
            for member in members {
                guard let exit = walk(member) else { return nil }
                exits.append(exit)
            }
            if exits.allSatisfy({ $0 == .proxy }) { return .proxy }
            if exits.allSatisfy({ $0 == .direct }) { return .direct }
            if exits.allSatisfy({ $0 == .reject }) { return .reject }
            return .other
        }
        return walk(name)
    }

     
     
     
     
     
    public static func globalExit(summaryJSON: String, members: (String) -> String? = { _ in nil }) -> GlobalExit? {
        guard let groups = summaryGroups(summaryJSON) else { return nil }
        return exit(following: "GLOBAL") { walkedGroup($0, in: groups, members: members, readingGlobalsMembers: false) }
    }

     
     
     
     
    public struct StoredGlobalChoice: Codable, Equatable, Sendable {
        public let pickedInGlobal: Bool
        public let selectedMap: [String: String]
        public let currentGroupName: String?
        public let manualGroups: [String]?

        public init(
            selectedMap: [String: String], currentGroupName: String?, globalPickedByReader: Bool,
            manualGroups: [String]? = nil
        ) {
            pickedInGlobal = globalPickedByReader
            self.selectedMap = selectedMap
            self.currentGroupName = currentGroupName
            self.manualGroups = manualGroups
        }

         
        public func reading(manualGroups: [String]) -> StoredGlobalChoice {
            StoredGlobalChoice(selectedMap: selectedMap, currentGroupName: currentGroupName,
                               globalPickedByReader: pickedInGlobal, manualGroups: manualGroups)
        }

        public var globalPick: String? { selectedMap["GLOBAL"] }

         
         
         
         
         
        public var candidateGroups: [String] {
            let manual = manualGroups.map(Set.init)
            func counts(_ group: String) -> Bool { !group.isEmpty && group != "GLOBAL" && (manual?.contains(group) ?? true) }
            let current = currentGroupName.flatMap { counts($0) ? $0 : nil }
            let stored: [String]
            if let manualGroups {
                stored = manualGroups.first { counts($0) && selectedMap[$0] != nil }.map { [$0] } ?? []
            } else {
                stored = selectedMap.keys.sorted().filter(counts)
            }
            var groups: [String] = []
            for group in [current].compactMap({ $0 }) + stored where !groups.contains(group) { groups.append(group) }
            return groups
        }
    }

     
     
    public enum StoredGlobalVerdict: Codable, Equatable, Sendable {
         
         
        case keep
         
         
        case refuse(GlobalExit)
    }

     
     
     
     
     
     
     
     
    public static func storedGlobalVerdict(_ stored: StoredGlobalChoice?) -> StoredGlobalVerdict {
        guard let stored else { return .keep }
        if !stored.pickedInGlobal, stored.candidateGroups.contains(where: { group in
            stored.selectedMap[group].map { exit(ofResolved: $0, isGroup: false) == .proxy } ?? true
        }) {
            return .keep
        }
        let found = exit(ofResolved: stored.globalPick ?? "", isGroup: false)
        return found == .proxy ? .keep : .refuse(found)
    }

     
     
     
    public static func groupsToRead(following name: String, group: (String) -> WalkedGroup?) -> [String] {
        var wanting: [String] = []
        var path: Set<String> = []
        func visit(_ name: String) {
            guard let found = group(name), path.insert(name).inserted else { return }
            defer { path.remove(name) }
            if let now = found.now, !now.isEmpty { return visit(now) }
            guard let members = found.members, found.listsEveryMember else {
                if !wanting.contains(name) { wanting.append(name) }
                return
            }
            members.forEach(visit)
        }
        visit(name)
        return wanting
    }

     
     
     
     
    public static func groupsToRead(forStepOn summaryJSON: String, members: (String) -> String?) -> [String] {
        guard let groups = summaryGroups(summaryJSON) else { return [] }
        return groupsToRead(forStepIn: groups, members: members)
    }

    private static func groupsToRead(forStepIn groups: [String: Any], members: (String) -> String?) -> [String] {
        let walk: (String) -> WalkedGroup? = { walkedGroup($0, in: groups, members: members, readingGlobalsMembers: false) }
        let onTheRoute = groupsToRead(following: "GLOBAL", group: walk)
        guard onTheRoute.isEmpty else { return onTheRoute }
        guard let found = exit(following: "GLOBAL", group: walk), found != .proxy else { return [] }
        let global = walkedGroup("GLOBAL", in: groups, members: members, readingGlobalsMembers: true)
        guard let globalMembers = global?.members else { return ["GLOBAL"] }
         
        guard global?.listsEveryMember == true else { return [] }
        var wanting: [String] = []
        for member in globalMembers {
            for group in groupsToRead(following: member, group: walk) where !wanting.contains(group) { wanting.append(group) }
        }
        return wanting
    }

     
     
     
    public static let readRounds = 4

     
     
     
     
     
     
     
     
     
     
    public static func readGlobalStep(
        summaryJSON: String,
        members: (String) async -> String?,
        isCurrent: () async -> Bool = { true }
    ) async -> GlobalSwitchStep? {
         
        guard let groups = summaryGroups(summaryJSON) else { return await isCurrent() ? .notKnown : nil }
        var pages: [String: String] = [:]
        for _ in 0..<readRounds {
            let read = pages
            let wanted = groupsToRead(forStepIn: groups, members: { read[$0] }).filter { pages[$0] == nil }
            guard !wanted.isEmpty else { break }
            for group in wanted {
                guard await isCurrent() else { return nil }
                pages[group] = await members(group) ?? ""
            }
        }
        guard await isCurrent() else { return nil }
        let read = pages
        return globalSwitchStep(group: { walkedGroup($0, in: groups, members: { read[$0] }, readingGlobalsMembers: true) })
    }

     
    public static func readGlobalStep(
        summary: () async -> String?, members: (String) async -> String?
    ) async -> GlobalSwitchStep {
        guard let summaryJSON = await summary() else { return .notKnown }
        return await readGlobalStep(summaryJSON: summaryJSON, members: members) ?? .notKnown
    }

     
     
     
     
     
    public static func readGlobalExit(summary: () -> String?, members: (String) -> String?) -> GlobalExit? {
        guard let summaryJSON = summary(), let groups = summaryGroups(summaryJSON) else { return nil }
        var pages: [String: String] = [:]
        for _ in 0..<readRounds {
            let read = pages
            let wanted = groupsToRead(following: "GLOBAL", group: {
                walkedGroup($0, in: groups, members: { read[$0] }, readingGlobalsMembers: false)
            }).filter { pages[$0] == nil }
            guard !wanted.isEmpty else { break }
            for group in wanted { pages[group] = members(group) ?? "" }
        }
        let read = pages
        return exit(following: "GLOBAL") { walkedGroup($0, in: groups, members: { read[$0] }, readingGlobalsMembers: false) }
    }

     
    private static func summaryGroups(_ summaryJSON: String) -> [String: Any]? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(summaryJSON.utf8)) as? [String: Any],
              object["error"] == nil,
              let groups = object["groups"] as? [String: Any],
              groups["GLOBAL"] is [String: Any] else { return nil }
        return groups
    }

     
     
     
    private static func walkedGroup(
        _ name: String, in groups: [String: Any], members: (String) -> String?, readingGlobalsMembers: Bool
    ) -> WalkedGroup? {
        guard let entry = groups[name] as? [String: Any] else { return nil }
        let now = (entry["now"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard now == nil || (readingGlobalsMembers && name == "GLOBAL") else { return WalkedGroup(now: now, members: nil) }
        let page = members(name).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        let names = (page?["members"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        let total = page?["total"] as? Int
        var complete = false
        if let names { complete = total.map { names.count >= $0 } ?? true }
        return WalkedGroup(now: now, members: names, listsEveryMember: complete)
    }

     
     
     
     
     

     
     
     
    public static func questionKey(_ exit: GlobalExit) -> String {
        switch exit {
        case .direct:
            return "GLOBAL is set to DIRECT. In Global mode no traffic goes through a proxy, and your device's real network address is used."
        case .reject:
            return "GLOBAL is set to REJECT. In Global mode all traffic is rejected, and the network stops working."
        case .other, .proxy:
            return "GLOBAL has no proxy chosen. In Global mode traffic doesn't go through a proxy."
        }
    }

     
     
     
    public static func notTurnedOnKey(_ exit: GlobalExit?) -> String {
        switch exit {
        case .direct?:
            return "GLOBAL is set to DIRECT, so Global mode wasn't turned on. Choose a node for GLOBAL in Clash, then try again."
        case .reject?:
            return "GLOBAL is set to REJECT, so Global mode wasn't turned on. Choose a node for GLOBAL in Clash, then try again."
        case .other?, .proxy?:
            return "GLOBAL has no proxy chosen, so Global mode wasn't turned on. Choose a node for GLOBAL in Clash, then try again."
        case nil:
            return "Clash couldn't confirm what GLOBAL is set to, so Global mode wasn't turned on. Open Clash, then try again."
        }
    }

     
     
    public static let notTurnedOnKeys: [String] = ([nil, .direct, .reject, .other] as [GlobalExit?]).map(notTurnedOnKey)

     
    public static func refusalKey(onto exit: GlobalExit?) -> String? {
        exit == .proxy ? nil : notTurnedOnKey(exit)
    }

     
    public static let globalNotLoadedKey = "The GLOBAL group hasn't loaded yet. Reconnect, then try again."

     
     
     
    public static let nothingToChooseKey =
        "The GLOBAL group in this profile has no node or policy group to choose, so Global mode can't be used. Switch to a profile that has nodes first."

     
     
     
    public static func unusableKey(group: (String) -> WalkedGroup?) -> String? {
        guard let global = group("GLOBAL") else { return globalNotLoadedKey }
        guard let members = global.members, global.listsEveryMember else { return nil }
        let exits = members.map { exit(following: $0, group: group) }
         
        guard !exits.contains(.proxy), !exits.contains(nil) else { return nil }
        return nothingToChooseKey
    }

     
     
    public enum GlobalSwitchStep: Equatable, Sendable {
         
        case switchNow
         
         
        case ask(GlobalExit)
         
        case refuse(String)
         
        case notKnown
    }

     
    public static func globalSwitchStep(group: (String) -> WalkedGroup?) -> GlobalSwitchStep {
        guard group("GLOBAL") != nil, let found = exit(following: "GLOBAL", group: group) else { return .notKnown }
        if found == .proxy { return .switchNow }
        if let key = unusableKey(group: group) { return .refuse(key) }
        return .ask(found)
    }

     
     
     
    public static func globalSwitchStep(summaryJSON: String, members: (String) -> String?) -> GlobalSwitchStep {
        guard let groups = summaryGroups(summaryJSON) else { return .notKnown }
        return globalSwitchStep(group: { walkedGroup($0, in: groups, members: members, readingGlobalsMembers: true) })
    }
}
