import ClashClientUI
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum GlobalModeConfirmation {

    enum Verdict: Equatable {
         
        case confirmed
         
         
        case refused
         
         
         
        case notYetKnown
    }

     
     
     
     
     
     
     
     
     
     
     
    static func verdict(
        groupCount: Int,
        hasGlobalGroup: Bool = true,
        selectionConfirmed: Bool
    ) -> Verdict {
        guard groupCount > 0, hasGlobalGroup else { return .notYetKnown }
        return selectionConfirmed ? .confirmed : .refused
    }

     
     
     
    static func verdict(check: NodesModel.GlobalModeCheck, groupCount: Int) -> Verdict {
        guard check != .notYetKnown else { return .notYetKnown }
        return verdict(groupCount: groupCount, selectionConfirmed: check == .proxy)
    }

     
     
     
     
     
    typealias SwitchStep = ClashTunnelOutboundMode.GlobalSwitchStep

    static func switchStep(check: NodesModel.GlobalModeCheck, groups: [ProxyGroup]) -> SwitchStep {
        guard check != .notYetKnown else { return .notKnown }
        return ClashTunnelOutboundMode.globalSwitchStep(group: GlobalProxySelectionPolicy.walk(groups))
    }

     
     
    static let switchNotConfirmed =
        "Clash couldn't confirm what GLOBAL is set to, so Global mode wasn't turned on. Try again in a moment."

     
     
     
    static let putBackToRule =
        "GLOBAL has no proxy chosen, so Clash has switched back to Rule mode for now. Choose a node in GLOBAL, then switch to Global again."

     
     
     
    static let notConfirmedPutBackToRule =
        "Clash couldn't confirm GLOBAL's choice, so it has switched back to Rule mode for now."

     
     
     
     
     
     
    static func runsByRulesOnConnect(
        check: NodesModel.GlobalModeCheck,
        groupCount: Int,
        hasGlobalGroup: Bool,
        directChosenByReader: Bool
    ) -> Bool {
        guard check == .notProxy, !directChosenByReader else { return false }
        return verdict(groupCount: groupCount, hasGlobalGroup: hasGlobalGroup, selectionConfirmed: false) == .refused
    }
}

 
 
 
 
 
 
 
final class GlobalOverDirectConsent: @unchecked Sendable {
    static let shared = GlobalOverDirectConsent()

    private let lock = NSLock()
    private var profiles: Set<String> = []

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var holdsAny: Bool { locked { !profiles.isEmpty } }

    func grant(profileID: String) {
        _ = locked { profiles.insert(profileID) }
    }

    func holds(profileID: String?) -> Bool {
        guard let profileID else { return false }
        return locked { profiles.contains(profileID) }
    }

    func revoke(profileID: String?) {
        guard let profileID else { return }
        _ = locked { profiles.remove(profileID) }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class ConnectedGlobalModeEnforcer {
    static let shared = ConnectedGlobalModeEnforcer()

     
    struct World {
         
        var isConnected: () -> Bool
         
        var isConnectedUnderGlobal: () -> Bool
         
        var runningMode: () -> String
         
        var check: () async -> NodesModel.GlobalModeCheck
         
        var inventory: () -> (groupCount: Int, hasGlobalGroup: Bool)
         
        var consentHolds: () -> Bool
         
        var refusal: () -> String?
         
        var intentSequence: () -> UInt64
        var intentIsCurrent: (UInt64) -> Bool
         
         
        var runByRules: () async -> Bool
         
         
        var storedModeIsGlobal: () -> Bool
         
         
        var modeChosenSince: (Date) -> Bool
         
        var runGlobal: () async -> Void
         
         
        var putBackToRule: (String) async -> Void
         
         
         
        var say: (String) async -> Void
         
        var pause: () async -> Void
    }

     
    static let rechecks = 3

    private var running = false
    private var askedAgain = false

    func enforce(_ world: World) async {
        guard !running else {
            askedAgain = true
            return
        }
        running = true
        defer { running = false }
        repeat {
            askedAgain = false
            await once(world)
        } while askedAgain
    }

    private func once(_ world: World) async {
        guard world.isConnectedUnderGlobal() else { return }
        let observed = world.intentSequence()
        var check = await world.check()
         
         
        guard world.intentIsCurrent(observed), world.isConnectedUnderGlobal(), !world.consentHolds() else { return }
        if check == .notYetKnown {
             
             
             
             
             
            let waitBegan = Date()
            func readersWordStands() -> Bool {
                world.intentIsCurrent(observed) && world.isConnected() && world.storedModeIsGlobal()
                    && !world.modeChosenSince(waitBegan) && world.runningMode() != "direct"
            }
             
             
             
             
            var ruled = await world.runByRules()
            if !ruled { ruled = await world.runByRules() }
            guard ruled else {
                guard readersWordStands() else { return }
                await world.say(GlobalModeConfirmation.switchNotConfirmed)
                return
            }
            var asked = 0
            while check == .notYetKnown, asked < Self.rechecks {
                asked += 1
                await world.pause()
                guard readersWordStands() else { return }
                check = await world.check()
            }
            guard readersWordStands() else { return }
            switch check {
            case .proxy:
                if world.runningMode() != "global" { await world.runGlobal() }
                return
            case .notYetKnown:
                 
                 
                 
                var backOnRule = world.runningMode() == "rule"
                if !backOnRule { backOnRule = await world.runByRules() }
                await world.say(backOnRule ? GlobalModeConfirmation.notConfirmedPutBackToRule
                                           : GlobalModeConfirmation.switchNotConfirmed)
                return
            case .notProxy:
                 
                await world.putBackToRule(world.refusal() ?? GlobalModeConfirmation.putBackToRule)
                return
            }
        }
        switch check {
        case .proxy, .notYetKnown:
            return
        case .notProxy:
            let inventory = world.inventory()
            guard GlobalModeConfirmation.runsByRulesOnConnect(
                check: check, groupCount: inventory.groupCount,
                hasGlobalGroup: inventory.hasGlobalGroup, directChosenByReader: false
            ) else { return }
            await world.putBackToRule(world.refusal() ?? GlobalModeConfirmation.putBackToRule)
        }
    }
}
