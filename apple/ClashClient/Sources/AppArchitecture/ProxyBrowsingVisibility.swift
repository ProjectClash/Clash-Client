import Foundation
import ClashClientKit

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ProxyBrowsingVisibility {

    enum Mode: Equatable {
        case rule
        case global
        case direct

         
         
         
         
         
        init(coreValue: String) {
            switch coreValue.lowercased() {
            case "global": self = .global
            case "direct": self = .direct
            default: self = .rule
            }
        }
    }

     
    enum Opening: Equatable, Hashable {
         
         
        case browsing
         
         
         
         
         
         
         
         
         
         
         
        case choosingInGlobal
    }

     
     
     
    static func browsingMode(_ mode: Mode, opening: Opening) -> Mode {
        opening == .choosingInGlobal && mode == .direct ? .rule : mode
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    enum OpeningEvent: Equatable {
         
        case request(Opening)
         
        case modeChanged(Mode)
         
        case shownChanged(Bool)
    }

    static func opening(_ current: Opening, after event: OpeningEvent) -> Opening {
        switch event {
        case .request(let requested): return requested
        case .modeChanged(let mode): return mode == .global ? .browsing : current
        case .shownChanged(let shown): return shown ? current : .browsing
        }
    }

     
     
    static let kernelGlobalGroupName = "GLOBAL"

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func members<Member>(
        _ members: [Member],
        of group: String,
        mode: Mode,
        opening: Opening = .browsing,
        name: (Member) -> String
    ) -> [Member] {
        guard mode == .global || opening == .choosingInGlobal, group == kernelGlobalGroupName else { return members }
        return members.filter { !LatencyProbeNamePolicy.builtinNames.contains(name($0)) }
    }

    static func standaloneNodes<Node>(
        _ nodes: [Node],
        mode: Mode,
        opening: Opening = .browsing
    ) -> [Node] {
        browsingMode(mode, opening: opening) == .direct ? [] : nodes
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func groups<Group>(
        _ groups: [Group],
        mode: Mode,
        opening: Opening = .browsing,
        name: (Group) -> String,
        isHidden: (Group) -> Bool
    ) -> [Group] {
        if opening == .choosingInGlobal {
            var listed = Self.groups(groups, mode: browsingMode(mode, opening: opening), name: name, isHidden: isHidden)
            if let global = groups.first(where: { name($0) == kernelGlobalGroupName }) {
                listed.removeAll { name($0) == kernelGlobalGroupName }
                listed.insert(global, at: 0)
            }
            return listed
        }
        switch mode {
        case .direct:
            return []
        case .global:
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            var shown = groups.filter { !isHidden($0) }
            if let index = shown.firstIndex(where: { name($0) == kernelGlobalGroupName }), index > 0 {
                shown.insert(shown.remove(at: index), at: 0)
            }
            return shown
        case .rule:
            return groups.filter { group in
                guard !isHidden(group) else { return false }
                 
                 
                 
                 
                 
                 
                 
                 
                 
                return name(group) != kernelGlobalGroupName
            }
        }
    }
}
