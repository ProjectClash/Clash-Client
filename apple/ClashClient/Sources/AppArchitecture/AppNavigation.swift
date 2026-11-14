import SwiftUI
import Foundation
import ClashClientUI
#if os(iOS)
import OSLog
import UIKit
#endif

 
 
 
 
 
 
 
 
enum AppTab: String, CaseIterable, Hashable, Sendable {
    case home
    case utilities
    case more
}
typealias AppNavigationDestination = ClashClientUI.AppleClientDestination

enum AppShellLayout: Equatable, Sendable {
    case compactTabs
    case regularSidebar
}

 
 
 
 
 
 
 
 
 
 
 
struct ClashShellLayoutKey: EnvironmentKey {
    static let defaultValue: AppShellLayout = .compactTabs
}

extension EnvironmentValues {
    var clashShellLayout: AppShellLayout {
        get { self[ClashShellLayoutKey.self] }
        set { self[ClashShellLayoutKey.self] = newValue }
    }
}

enum AppShellLayoutSelector {
    static func layout(
        isPad: Bool,
        hasRegularHorizontalSize: Bool
    ) -> AppShellLayout {
        isPad && hasRegularHorizontalSize ? .regularSidebar : .compactTabs
    }

     
     
     
     
     
     
     
     
     
    static func compactHandoff(
        for selectedRoot: ClashClientUI.ClashRootDestination
    ) -> AppShellCompactHandoff? {
        switch selectedRoot {
        case .proxies: .proxiesSheet
        case .rules: .rulesSheet
        case .profiles: .profileCenter
         
         
         
        case .home, .utilities, .more, .activity, .about:
            nil
        }
    }
}

 
enum AppShellCompactHandoff: Equatable, Sendable {
    case proxiesSheet
    case rulesSheet
    case profileCenter
}

extension AppShellLayoutSelector {
     
     
     
     
     
     
     
     
    static func regularHandoff(
        for profileCenter: AppNavigationDestination?,
        sessionPage: ClashClientUI.ClashRootDestination?
    ) -> ClashClientUI.ClashRootDestination? {
         
         
        if let sessionPage { return sessionPage }
        return profileCenter == .profiles ? .profiles : nil
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class LostPresentationRecovery {
     
     
    struct Claims {
         
        var kinds: @MainActor () -> [String]
        var clear: @MainActor () -> Void
         
         
         
        var place: @MainActor () -> AnyHashable = { AnyHashable(0) }

        static let none = Claims(kinds: { [] }, clear: {})
    }

     
    nonisolated static let settle: TimeInterval = 0.45
     
     
     
    nonisolated static let freshness: TimeInterval = 1
     
     
     
    nonisolated static let appearanceWindow: TimeInterval = 1.5
     
     
     
    nonisolated static let repeatWindow: TimeInterval = 5

    private let clock: () -> TimeInterval
    private let presented: @MainActor () -> String?
    private let isPresenting: @MainActor () -> Bool
    private let appearanceWindow: TimeInterval
    private let report: (String) -> Void
     
    private var latest = 0
    private var lastRaise: TimeInterval?
     
    private var home = Claims.none
     
     
    private var droppedByTheDoor: (kinds: [String], at: TimeInterval)?
     
     
    private(set) var appearances = 0
     
    private var confirming = 0
     
     
    private var pendingHealDue: TimeInterval?
     
     
    private var lastHeal: (kinds: Set<String>, at: TimeInterval)?

     
     
     
     
     
     
    init(
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        presented: @escaping @MainActor () -> String? = { nil },
        isPresenting: @escaping @MainActor () -> Bool = { false },
        appearanceWindow: TimeInterval = LostPresentationRecovery.appearanceWindow,
        report: @escaping (String) -> Void = {
            ClashLogStore.shared.append($0, stream: .app, level: .warning)
        }
    ) {
        self.clock = clock
        self.presented = presented
        self.isPresenting = isPresenting
        self.appearanceWindow = appearanceWindow
        self.report = report
    }

     
     
    func register(home claims: Claims) {
        home = claims
    }

     
     
    func noteDroppedByTheDoor(_ kinds: [String]) {
        droppedByTheDoor = (kinds, clock())
    }

     
     
     
    func supersede() {
        latest &+= 1
    }

     
    var generation: Int { latest }

     
    func noteRaised() {
        lastRaise = clock()
    }

     
    func noteAppeared() {
        appearances &+= 1
    }

     
     
     
    func confirmAppearance(
        stillAsked: @escaping @MainActor () -> Bool,
        fallBack: @escaping @MainActor () -> Void
    ) {
        let seen = appearances
        let request = latest
        let window = appearanceWindow
        confirming += 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(window * 1_000_000_000))
            self?.confirming -= 1
            guard let self,
                  self.appearances == seen,
                  self.latest == request,
                  !self.isPresenting(),
                  stillAsked()
            else { return }
            fallBack()
        }
    }

     
     
     
     
     
     
    func door(
        _ name: String,
        shell: Claims,
        afterHealing: (@MainActor () -> Void)? = nil,
        healedAgain: (@MainActor () -> Void)? = nil,
        _ open: @escaping @MainActor () -> Void
    ) {
        let now = clock()
        var cleared = takeDroppedByTheDoor(now: now)
        let claimed = (shell: shell.kinds(), home: home.kinds())
         
         
         
         
         
        let onItsWayUp = !(claimed.shell + claimed.home).isEmpty
            && lastRaise.map { now - $0 < Self.freshness } == true
        if !onItsWayUp {
            let healing = clear(claimed, shell: shell)
            if !healing.isEmpty {
                let kinds = Set(healing)
                if let lastHeal, now - lastHeal.at < Self.repeatWindow, !lastHeal.kinds.isDisjoint(with: kinds) {
                    report("lost presentation healed again  door=\(name)  cleared=\(healing.joined(separator: ","))")
                    healedAgain?()
                }
                lastHeal = (kinds, now)
            }
            cleared += healing
        }
        log(name, cleared: cleared)
         
         
         
         
         
         
         
        if onItsWayUp, cleared.isEmpty {
            let confirmationPending = confirming > 0
            let request = latest
            open()
            if confirmationPending, latest != request { afterHealing?() }
            return
        }
        let place = shell.place()
        let home = home
         
         
         
         
         
        let inherited = pendingHealDue.map { $0 - now }.flatMap { $0 > 0 ? $0 : nil }
        let healed = !cleared.isEmpty || inherited != nil
        let wait = cleared.isEmpty ? inherited : Self.settle
        raise(
            after: wait,
             
             
             
            unless: { !shell.kinds().isEmpty || !home.kinds().isEmpty || shell.place() != place },
            then: {
                open()
                if healed { afterHealing?() }
            }
        )
        if let wait { pendingHealDue = now + wait }
    }

     
     
     
     
     
     
     
    func afterDismissal(
        _ name: String,
        shell: Claims,
        lost: Bool,
        afterRaise: (@MainActor () -> Void)? = nil,
        _ open: @escaping @MainActor () -> Void
    ) {
        let cleared = lost ? clear((shell.kinds(), home.kinds()), shell: shell) : []
        log(name, cleared: cleared)
        raise(afterClearing: true) {
            open()
            afterRaise?()
        }
    }

     
     
     
     
    func raise(
        afterClearing clearedSomething: Bool,
        unless stale: @escaping @MainActor () -> Bool = { false },
        then open: @escaping @MainActor () -> Void
    ) {
        raise(after: clearedSomething ? Self.settle : nil, unless: stale, then: open)
    }

    private func raise(
        after wait: TimeInterval?,
        unless stale: @escaping @MainActor () -> Bool,
        then open: @escaping @MainActor () -> Void
    ) {
        latest &+= 1
        let request = latest
        guard let wait else {
            noteRaised()
            open()
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard let self, request == self.latest else { return }
            self.pendingHealDue = nil
            guard !stale() else { return }
            self.noteRaised()
            open()
        }
    }

     
     
    private func clear(_ claimed: (shell: [String], home: [String]), shell: Claims) -> [String] {
        if !claimed.shell.isEmpty { shell.clear() }
        if !claimed.home.isEmpty { home.clear() }
        return claimed.shell + claimed.home
    }

    private func takeDroppedByTheDoor(now: TimeInterval) -> [String] {
        guard let dropped = droppedByTheDoor else { return [] }
        droppedByTheDoor = nil
        return now - dropped.at < Self.freshness ? dropped.kinds : []
    }

     
     
     
    private func log(_ door: String, cleared: [String]) {
        let onScreen = presented()
        guard !cleared.isEmpty || onScreen != nil else { return }
        report(
            "lost presentation  door=\(door)  cleared=\(cleared.isEmpty ? "-" : cleared.joined(separator: ","))"
                + "  presented=\(onScreen ?? "-")"
        )
    }
}

 
 
 
 
 
 
 
struct ProfileSheetState: Equatable {
     
     
    enum Presenter: Equatable { case shell, second }

    enum Sheet: Equatable, Identifiable {
        case centre(AppNavigationDestination)
        case picker
         
         
         
        case inspector

         
        var id: Int {
            switch self {
            case .centre: return 0
            case .picker: return 1
            case .inspector: return 2
            }
        }
    }

    var centre: AppNavigationDestination?
    var isPicking = false
    var presenter: Presenter = .shell

     
     
    var claim: Sheet? {
        if let centre { return .centre(centre) }
        return isPicking ? .picker : nil
    }

    var onTheShellPresenter: Sheet? { presenter == .shell ? claim : nil }
    var onTheSecondPresenter: Sheet? { presenter == .second ? claim : nil }

     
     
     
    func item(on presenter: Presenter, inspector: Bool) -> Sheet? {
        guard self.presenter == presenter else { return nil }
        return claim ?? (inspector ? .inspector : nil)
    }

    mutating func raise(_ sheet: Sheet) {
        switch sheet {
        case .centre(let destination): centre = destination
        case .picker: isPicking = true
        case .inspector: break
        }
    }

    mutating func drop() {
        centre = nil
        isPicking = false
    }

     
     
     
     
     
    mutating func fallBack() -> Sheet? {
        let claim = claim
        drop()
        presenter = .second
        return claim
    }

     
     
     
     
    mutating func route(
        to destination: AppNavigationDestination,
        layout: AppShellLayout,
        navigationState: inout ClashClientUI.AppleClientNavigationState
    ) {
        AppShellNavigationRouter.navigate(
            to: destination,
            layout: layout,
            navigationState: &navigationState,
            profileCenterDestination: &centre
        )
        isPicking = false
    }

     
     
    mutating func narrow(into handoff: AppShellCompactHandoff) {
        guard handoff == .profileCenter else { return }
        centre = .profiles
        isPicking = false
    }

     
     
    mutating func widen(sessionPage: ClashClientUI.ClashRootDestination?) -> ClashClientUI.ClashRootDestination? {
        guard let root = AppShellLayoutSelector.regularHandoff(for: centre, sessionPage: sessionPage)
        else { return nil }
        centre = nil
        return root
    }
}

#if os(iOS)
 
 
 
@MainActor
enum ShellPresentationProbe {
     
    static func rootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        let active = scenes.first { $0.activationState == .foregroundActive }?.windows.first
        return (windows.first(where: \.isKeyWindow) ?? active ?? windows.first)?.rootViewController
    }

    static func presentedChain() -> [UIViewController] {
        var chain: [UIViewController] = []
        var next = rootViewController()?.presentedViewController
        while let controller = next {
            chain.append(controller)
            next = controller.presentedViewController
        }
        return chain
    }

     
     
    static func describe() -> String? {
        let chain = presentedChain()
        guard !chain.isEmpty else { return nil }
        return chain.map {
            String(describing: type(of: $0)) + ($0.isBeingDismissed ? "(dismissing)" : "")
        }.joined(separator: ">")
    }

     
     
     
     
     
     
    static var presentsMoreThanAnAlert: Bool {
        presentedChain().contains(where: isOnScreenAndNotAnAlert)
    }

    static func isOnScreenAndNotAnAlert(_ controller: UIViewController) -> Bool {
        !(controller is UIAlertController)
            && controller.viewIfLoaded?.window != nil
            && !controller.isBeingDismissed
    }
}

 
 
 
 
 
 
 
@MainActor
enum PresentationEvidence {
     
     
     
    static func windows() -> String {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var parts: [String] = []
        for (sceneIndex, scene) in scenes.enumerated() {
            for (windowIndex, window) in scene.windows.enumerated() {
                var chain: [String] = []
                var next = window.rootViewController?.presentedViewController
                while let controller = next {
                    chain.append(String(describing: type(of: controller))
                        + (controller.isBeingPresented ? "(presenting)" : "")
                        + (controller.isBeingDismissed ? "(dismissing)" : ""))
                    next = controller.presentedViewController
                }
                var flags = ["state=\(scene.activationState.rawValue)", "level=\(Int(window.windowLevel.rawValue))"]
                if window.isKeyWindow { flags.append("key") }
                if window.isHidden { flags.append("hidden") }
                if window.rootViewController?.transitionCoordinator != nil { flags.append("transitioning") }
                let root = window.rootViewController.map { String(describing: type(of: $0)) } ?? "-"
                parts.append("s\(sceneIndex)w\(windowIndex)[\(flags.joined(separator: " "))] \(root)"
                    + (chain.isEmpty ? "" : ">" + chain.joined(separator: ">")))
            }
        }
        return "windows=" + (parts.isEmpty ? "-" : parts.joined(separator: " | "))
    }

     
    enum Reason: String {
        case healedAgain
        case secondPresenterTakesOver
        case windowDidNotPresent
    }

     
    static func record(_ reason: Reason, door: String) {
        ClashLogStore.shared.append(
            "lost presentation evidence (\(reason.rawValue))  door=\(door)  " + windows(), stream: .app, level: .warning
        )
        captureSystemLog(reason: reason)
    }

    private static var lastCapture: Date?

     
     
     
     
    static func captureSystemLog(reason: Reason) {
        let now = Date()
        if let lastCapture, now.timeIntervalSince(lastCapture) < 60 { return }
        lastCapture = now
        Task.detached(priority: .utility) {
            let lines = systemLines(since: now.addingTimeInterval(-900))
            ClashLogStore.shared.append(
                "lost presentation system log (\(reason.rawValue))  lines=\(lines.count)", stream: .app, level: .warning
            )
            for line in lines.suffix(40) {
                ClashLogStore.shared.append("  " + line, stream: .app, level: .warning)
            }
        }
    }

    nonisolated static func systemLines(since start: Date) -> [String] {
        let store: OSLogStore
        do {
            store = try OSLogStore(scope: .currentProcessIdentifier)
        } catch {
            return ["(no store: \(error))"]
        }
         
        let predicate = NSComparisonPredicate(
            leftExpression: NSExpression(forKeyPath: "subsystem"),
            rightExpression: NSExpression(forConstantValue: ["com.apple.UIKit", "com.apple.SwiftUI"]),
            modifier: .direct,
            type: .in,
            options: []
        )
        let entries: AnySequence<OSLogEntry>
        do {
            entries = try store.getEntries(at: store.position(date: start), matching: predicate)
        } catch {
            return ["(no entries: \(error))"]
        }
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var lines: [String] = []
        for case let entry as OSLogEntryLog in entries where entry.date.timeIntervalSince(start) >= 0 {
            let message = entry.composedMessage
            let lowered = message.lowercased()
            guard ["present", "sheet", "transition", "detached"].contains(where: { lowered.contains($0) }) else { continue }
            lines.append("\(stamp.string(from: entry.date)) \(entry.subsystem)/\(entry.category) \(message)")
        }
        return lines
    }
}


#endif

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class HandoffCentreDebt {
    private(set) var owed = false

     
     
    func note(_ outcome: ProfileImportOutcome, centreOnScreen: Bool) {
        if !outcome.isEmpty, !centreOnScreen { owed = true }
    }

     
     
     
     
     
    func centreAppeared() {
        owed = false
    }

     
     
     
     
    func raiseIsDue(sceneIsActive: Bool, confirmationPending: Bool, routerHoldsSomething: Bool) -> Bool {
        guard owed else { return false }
        guard routerHoldsSomething else {
            owed = false
            return false
        }
        return sceneIsActive && !confirmationPending
    }
}

 
 
 
 
@MainActor
enum ReaderSelection {
    static func select(
        _ root: ClashClientUI.ClashRootDestination,
        in navigationState: inout ClashClientUI.AppleClientNavigationState,
        recovery: LostPresentationRecovery
    ) {
        recovery.supersede()
        navigationState.selectRoot(root)
    }
}

 
 
 
 
 
enum AppShellNavigationRouter {
     
     
    static func raisesTheProfileCentre(
        _ destination: AppNavigationDestination,
        layout: AppShellLayout
    ) -> Bool {
        switch destination {
        case .profiles: layout == .compactTabs
        case .profileImport, .profileDetail, .modules: true
        default: false
        }
    }

     
     
     
     
     
     
     
    static func heldPagesToOpen<Page>(
        route: Page?,
        centre: Page?,
        handoffCentrePending: Bool
    ) -> (open: [Page], dropped: Page?) {
        if let centre { return ([centre], route) }
        guard let route else { return ([], nil) }
        return handoffCentrePending ? ([], route) : ([route], nil)
    }

    static func navigate(
        to destination: AppNavigationDestination,
        layout: AppShellLayout,
        navigationState: inout ClashClientUI.AppleClientNavigationState,
        profileCenterDestination: inout AppNavigationDestination?
    ) {
        switch destination {
         
         
         
         
        case .profiles where layout == .regularSidebar:
            profileCenterDestination = nil
            navigationState.navigate(to: destination)
        case .profiles, .profileImport, .profileDetail, .modules:
            profileCenterDestination = destination
        default:
            profileCenterDestination = nil
            navigationState.navigate(to: destination)
        }
    }
}

extension ClashSystemRoute {
     
     
    var navigationDestination: AppNavigationDestination {
        switch self {
        case .vpn, .mode:
            return .home
        case .open(let destination):
            switch destination {
            case .overview, .home:
                return .home
            case .profiles:
                return .profiles
            case .nodes, .proxies:
                return .proxies
             
             
             
             
             
            case .logs:
                return .utilities(.activity)
            case .tools, .utilities:
                return .utilities(.root)
            case .more:
                return .more(.root)
            }
        }
    }
}
