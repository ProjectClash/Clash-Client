import Combine
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class ClashNodePicks {
     
    typealias Perform = @MainActor (_ group: String, _ member: String) async -> Void

     
    enum Repick {
         
         
         
         
        case skipped
         
         
         
         
         
        case madeAtOnce
    }

    private struct Pick {
        let group: String
        let member: String
         
         
        let profile: String?
        let repick: Repick
        let perform: Perform
         
        let heldWhenPicked: Bool
         
        var waited = false
    }

     
    private enum NotMade {
        case configurationSwitched, groupIsOnIt, laterPick, pickUnderWay, unpinned
    }

     
    private weak var nodes: NodesModel?
    private var pending: [Pick] = []
    private var picking = false
     
    private var making: (group: String, member: String)?
    private var switchEnds: AnyCancellable?

    init(nodes: NodesModel) {
        self.nodes = nodes
         
         
        switchEnds = nodes.$isSwitchingProxy
            .filter { !$0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.next() }
    }

     
     
     
     
    @discardableResult
    func pick(_ group: String, _ member: String, repick: Repick, perform: @escaping Perform) -> Bool {
        guard let nodes else { return false }
        dropWaiting(in: group, .laterPick)
         
         
         
         
        if let making, making.group == group, making.member == member {
            note(group, member, .pickUnderWay)
            return false
        }
        let held = nodes.groups.first(where: { $0.name == group }).map {
            !ProxyGroupControlKind(rawType: $0.type).canBeUnpinned && $0.holdsSelection(member)
        } ?? false
        pending.append(Pick(group: group, member: member, profile: nodes.activeProfileID,
                            repick: repick, perform: perform, heldWhenPicked: held))
        next()
        guard let waiting = pending.firstIndex(where: { $0.group == group }) else { return false }
        pending[waiting].waited = true
        return true
    }

     
     
     
     
    func withdraw(group: String) {
        dropWaiting(in: group, .unpinned)
    }

    private func next() {
        guard !picking, let nodes, !nodes.isSwitchingProxy, !pending.isEmpty else { return }
        let wanted = pending.removeFirst()
        picking = true
        Task {
            defer { picking = false; next() }
             
             
             
            if nodes.isSwitchingProxy {
                if pending.contains(where: { $0.group == wanted.group }) {
                    note(wanted.group, wanted.member, .laterPick)
                } else {
                    var waiting = wanted
                    waiting.waited = true
                    pending.insert(waiting, at: 0)
                }
                return
            }
            guard nodes.activeProfileID == wanted.profile else {
                note(wanted.group, wanted.member, .configurationSwitched)
                return
            }
             
            if let group = nodes.groups.first(where: { $0.name == wanted.group }),
               !ProxyGroupControlKind(rawType: group.type).canBeUnpinned,
               group.holdsSelection(wanted.member),
               wanted.repick == .skipped || (wanted.waited && !wanted.heldWhenPicked) {
                note(wanted.group, wanted.member, .groupIsOnIt)
                return
            }
            making = (wanted.group, wanted.member)
            defer { making = nil }
            await wanted.perform(wanted.group, wanted.member)
        }
    }

    private func dropWaiting(in group: String, _ why: NotMade) {
        for dropped in pending where dropped.group == group {
            note(dropped.group, dropped.member, why)
        }
        pending.removeAll { $0.group == group }
    }

     
     
    private func note(_ group: String, _ member: String, _ why: NotMade) {
        let line: String
        switch why {
        case .configurationSwitched:
            line = "proxy pick not made  group=\(group) member=\(member)  the configuration was switched since it was picked"
        case .groupIsOnIt:
            line = "proxy pick not made  group=\(group) member=\(member)  the group is on it already"
        case .laterPick:
            line = "proxy pick not made  group=\(group) member=\(member)  a later pick in the group took its place"
        case .pickUnderWay:
            line = "proxy pick not made  group=\(group) member=\(member)  it is the pick under way, tapped again"
        case .unpinned:
            line = "proxy pick not made  group=\(group) member=\(member)  Unpin withdrew it"
        }
        ClashLogStore.shared.append(line, stream: .app, level: .info)
    }
}
