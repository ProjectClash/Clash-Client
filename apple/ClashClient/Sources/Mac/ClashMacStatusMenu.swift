import AppKit
import Combine
import ClashClientUI

 
 
 
 
 
 
struct ClashMacStatusMenuSnapshot: Equatable {
    var phase: AppleClientConnectionPhase
    var primaryIntent: AppleClientConnectionIntent?
    var outboundMode: AppleClientOutboundMode
    var selectedRouteName: String?
    var proxies: ClashMacMenuProxyCatalog
    var showsSpeedInMenuBar: Bool
    var hidesDockIcon: Bool
    var upLine: String
    var downLine: String
     
     
    var offersQuitLeavingTunnel: Bool
     
     
     
    var offersShellCommand: Bool
    var offersExternalShellCommand: Bool
     
     
     
    var prefersLoopbackShellCommand: Bool
     
     
     
    var speedIsPaused = false
     
     
     
    var runsPreviousRevision = false
     
    var runningPreviousProfileName: String?
}

 
 
struct ClashMacStatusMenuActions {
    var primary: () -> Void = {}
    var cancelStart: () -> Void = {}
    var setOutboundMode: (AppleClientOutboundMode) -> Void = { _ in }
    var select: (_ group: String, _ member: String) -> Void = { _, _ in }
     
     
     
    var testGroup: (_ group: String) -> Bool = { _ in false }
     
     
    var openGroup: (_ group: String) -> Void = { _ in }
     
     
     
    var currentMember: (_ group: String) -> String? = { _ in nil }
    var setShowsSpeedInMenuBar: (Bool) -> Void = { _ in }
    var setHidesDockIcon: (Bool) -> Void = { _ in }
    var openSettings: () -> Void = {}
    var openApp: () -> Void = {}
    var quitLeavingTunnel: () -> Void = {}
    var quit: () -> Void = {}
     
     
    var copyShellCommand: (_ externalIP: Bool) -> Void = { _ in }

    static let none = ClashMacStatusMenuActions()
}

 
 
 
final class ClashMacMenuRowAction: NSObject {
    private let perform: () -> Void

    init(_ perform: @escaping () -> Void) {
        self.perform = perform
    }

    @objc func fire(_ sender: Any?) {
        perform()
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
enum ClashMacStatusMenuBuilder {
    static func makeMenu(
        _ snapshot: ClashMacStatusMenuSnapshot,
        actions: ClashMacStatusMenuActions,
        locale: Locale = .current,
        showsIconImages: Bool? = nil
    ) -> NSMenu {
        let menu = plainMenu()

        func copy(_ key: String) -> String {
            ClashCopy.string(key, locale: locale)
        }

        if snapshot.runsPreviousRevision {
            let notice = label(snapshot.runningPreviousProfileName.map {
                ClashCopy.format("Still running %@", locale: locale, $0)
            } ?? copy("Still running the previous version"))
            notice.setAccessibilityIdentifier("menu-bar.previous-revision")
            menu.addItem(notice)
            menu.addItem(.separator())
        }

         
         
         
         
        switch ClashMacMenuPrimaryRow.resolve(
            phase: snapshot.phase,
            intent: snapshot.primaryIntent
        ) {
        case .intent(let intent):
            menu.addItem(row(copy(intent.toolbarTitle), actions.primary))
        case .cancelStart:
            menu.addItem(row(copy("Cancel"), identifier: "menu-bar.cancel-start", actions.cancelStart))
        case .none:
            menu.addItem(label(copy(snapshot.phase.statusTitle)))
        }

         
         
         
         
         
         
        let mode = ClashMacTrailingMenuItem(title: copy("Mode"))
        mode.setAccessibilityIdentifier("menu-bar.outbound-mode")
        setTrailing(copy(snapshot.outboundMode.menuTitle), on: mode)
        let modes = plainMenu()
        for candidate in AppleClientOutboundMode.allCases {
            modes.addItem(row(
                copy(candidate.menuTitle),
                state: candidate == snapshot.outboundMode ? .on : .off
            ) { actions.setOutboundMode(candidate) })
        }
        mode.submenu = modes
        menu.addItem(mode)

        if let route = snapshot.selectedRouteName {
             
            menu.addItem(label(ClashMacMenuRowMetrics.middleTruncated(route, width: ClashMacMenuRowMetrics.routeNameCap)))
        }

         
         
         
         
         
         
         
         
        let connected = snapshot.phase == .connected
        let justConnected = connected && !Self.lastBuiltConnected
        Self.lastBuiltConnected = connected
        if !snapshot.proxies.groups.isEmpty {
            menu.addItem(.separator())
            let drawsImages = showsIconImages ?? Self.proxiesPageDrawsIconImages()
            for group in snapshot.proxies.groups {
                let item = ClashMacTrailingMenuItem(title: group.name)
                item.setAccessibilityIdentifier("menu-bar.proxy-group")
                setGroupTitle(group, on: item, showsIconImages: drawsImages, forgetsRefusal: justConnected)
                if group.isEmpty {
                     
                    setTrailing(copy("No nodes"), on: item)
                    item.isEnabled = false
                    menu.addItem(item)
                    continue
                }
                setGroupTrailing(
                    member: group.checked, reading: group.checked.map(group.orderReading(of:)), on: item,
                    reserving: reservedTrailingWidth(group, live: actions.currentMember(group.name)))
                let submenu = plainMenu()
                let lazy = ClashMacProxySubmenuController(
                    group: { group }, actions: actions, locale: locale
                )
                submenu.delegate = lazy
                 
                item.representedObject = lazy
                item.submenu = submenu
                menu.addItem(item)
            }
        }

         
         
         
         
         
        menu.addItem(.separator())
        if snapshot.prefersLoopbackShellCommand {
            let loopback = row(
                copy("Copy Shell Command (127.0.0.1)"),
                identifier: "menu-bar.copy-shell-command-loopback"
            ) { actions.copyShellCommand(false) }
            loopback.isEnabled = snapshot.offersShellCommand
            menu.addItem(loopback)
        } else {
            let external = snapshot.offersExternalShellCommand
            let line = row(
                copy("Copy Shell Command"),
                identifier: "menu-bar.copy-shell-command"
            ) { actions.copyShellCommand(external) }
            line.isEnabled = snapshot.offersShellCommand
            menu.addItem(line)
        }

         
         
        menu.addItem(.separator())
        menu.addItem(row(
            copy("Show Speed in Menu Bar"),
            identifier: "menu-bar.shows-speed",
            state: snapshot.showsSpeedInMenuBar ? .on : .off
        ) { actions.setShowsSpeedInMenuBar(!snapshot.showsSpeedInMenuBar) })
        menu.addItem(row(
            copy("Hide Dock Icon"),
            identifier: "menu-bar.hides-dock-icon",
            state: snapshot.hidesDockIcon ? .on : .off
        ) { actions.setHidesDockIcon(!snapshot.hidesDockIcon) })
        if !snapshot.showsSpeedInMenuBar, !snapshot.speedIsPaused {
            menu.addItem(label(snapshot.upLine))
            menu.addItem(label(snapshot.downLine))
        }

         
        menu.addItem(.separator())
        menu.addItem(row(copy("Settings…"), identifier: "menu-bar.settings", actions.openSettings))
        menu.addItem(row(copy("Open Clash"), actions.openApp))

         
        menu.addItem(.separator())
        if snapshot.offersQuitLeavingTunnel {
            menu.addItem(row(
                copy("Quit (Leave VPN Active)"),
                identifier: "menu-bar.quit-leaving-tunnel",
                actions.quitLeavingTunnel
            ))
        }
        menu.addItem(row(copy("Quit Clash"), identifier: "menu-bar.quit", actions.quit))
         
        layOutTrailing(menu)
        return menu
    }

     
     
    private static func plainMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        return menu
    }

     

     
    static func readingSuffix(_ reading: ClashProxyLatencyState?) -> String {
        let text = reading.map(ClashMacMenuRowModel.latencyText) ?? ""
        return text.isEmpty ? "" : "  \(text)"
    }

    private static func trailingWidth(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: ClashMacMenuRowMetrics.trailingFont]).width
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func reservedTrailingWidth(_ group: ClashMacMenuProxyCatalog.Group, live: String? = nil) -> CGFloat {
        let held = group.latency.values.compactMap { state -> Int? in
            if case .measured(let milliseconds) = state { return milliseconds } else { return nil }
        }.max() ?? 0
        let digits = max(4, String(held).count)
        let attributes: [NSAttributedString.Key: Any] = [.font: ClashMacMenuRowMetrics.trailingFont]
        func width(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: attributes).width }
        let reading = width(readingSuffix(.measured(milliseconds: Int(String(repeating: "8", count: digits)) ?? 8_888)))
        let picked = [group.checked, live].compactMap { $0 }
        let members = group.pinsOnRepick ? group.members + picked : picked
        var widest: CGFloat = 0
        for member in members {
            widest = max(widest, width(member))
            if widest + reading >= ClashMacMenuRowMetrics.menuWidthCap { break }
        }
        return widest == 0 ? 0 : widest + reading
    }

     
    static func setTrailing(_ text: String, on item: NSMenuItem) {
        guard let row = item as? ClashMacTrailingMenuItem else { return }
        row.plain = text
        row.reserved = trailingWidth(text)
        row.compose()
    }

     
     
     
    static func setGroupTrailing(
        member: String?, reading: ClashProxyLatencyState?, on item: NSMenuItem, reserving reserved: CGFloat? = nil
    ) {
        guard let row = item as? ClashMacTrailingMenuItem else { return }
        row.member = member
        row.reading = reading
        if let reserved { row.reserved = reserved }
        row.compose()
    }

     
     
    static func setName(_ name: NSAttributedString, on item: NSMenuItem) {
        guard let row = item as? ClashMacTrailingMenuItem else {
            item.attributedTitle = name
            return
        }
        row.name = name
        row.compose(rewriting: true)
    }

     
     
     
     
     
     
     
     
     
     
    static func layOutTrailing(_ menu: NSMenu) {
        let rows = menu.items.compactMap { $0 as? ClashMacTrailingMenuItem }
        guard !rows.isEmpty else { return }
        let needed = rows.map { $0.name.size().width + ClashMacMenuRowMetrics.trailingGap + $0.reserved }.max() ?? 0
        let widestOther = menu.items.filter { !($0 is ClashMacTrailingMenuItem) && !$0.isSeparatorItem }.map { item in
            (item.attributedTitle ?? NSAttributedString(string: item.title, attributes: [.font: ClashMacMenuRowMetrics.font])).size().width
        }.max() ?? 0
        func lay(_ stop: CGFloat) {
            for row in rows {
                row.stop = stop
                row.compose(rewriting: true)
            }
        }
        var stop = max(min(needed, ClashMacMenuRowMetrics.menuWidthCap), widestOther).rounded(.up)
        lay(stop)
        let over = menu.size.width - ClashMacMenuRowMetrics.menuWidthCap
        guard over > 0 else { return }
        let widestName = rows.map { $0.name.size().width }.max() ?? 0
        let least = max(widestOther, widestName + ClashMacMenuRowMetrics.trailingGap + ClashMacMenuRowMetrics.leastTrailingRoom)
        stop = max(stop - over, least).rounded(.down)
        lay(stop)
    }

     
     
     
    static func trailingText(member: String?, reading: ClashProxyLatencyState?, room: CGFloat) -> String {
        guard let member, !member.isEmpty else { return "" }
        let suffix = readingSuffix(reading)
        let cut = ClashMacMenuRowMetrics.middleTruncated(
            member, width: room - trailingWidth(suffix), font: ClashMacMenuRowMetrics.trailingFont, keepsTail: true
        )
        return (trailingWidth(cut) < trailingWidth(member) ? cut : member) + suffix
    }

     
     
    enum GroupIcon {
        case text(String)
        case image(NSImage)
    }

     
     
    static var groupIconSide: CGFloat { (ClashMacMenuRowMetrics.pointSize + 2).rounded() }

     
     
     
     
     
    static func groupIcon(_ icon: String?, showsIconImages: Bool) -> GroupIcon? {
        switch ClashProxyGroupIconKind.of(icon) {
        case .emoji(let text):
            return .text(text)
        case .symbol(let symbol):
             
             
            let configuration = NSImage.SymbolConfiguration(pointSize: ClashMacMenuRowMetrics.pointSize, weight: .regular)
                .applying(.init(hierarchicalColor: .secondaryLabelColor))
            let image = symbol.isCustom
                ? NSImage(named: symbol.rawValue)
                : NSImage(systemSymbolName: ClashSymbol.platformName(symbol), accessibilityDescription: nil)
            return image?.withSymbolConfiguration(configuration).map(GroupIcon.image)
        case .remote where showsIconImages:
            return .image(roundedIcon(nil))
        case .remote, .unrecognized, .none:
            return nil
        }
    }

     
     
    static func roundedIcon(_ image: CGImage?) -> NSImage {
        let side = groupIconSide
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let corner = side * ClashClientUI.ClashTheme.Layout.proxyGroupIconCornerRadius
                / ClashClientUI.ClashTheme.Layout.proxyGroupIconSize
            NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner).addClip()
            if let image {
                 
                let scale = min(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
                let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                NSGraphicsContext.current?.cgContext.draw(image, in: CGRect(
                    x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                    width: size.width, height: size.height))
            } else {
                NSColor.quaternaryLabelColor.setFill()
                rect.fill()
            }
            return true
        }
    }

     
     
     
     
    static func groupTitle(name: String, icon: GroupIcon? = nil) -> NSAttributedString {
        let font = ClashMacMenuRowMetrics.font
        let title = NSMutableAttributedString()
        switch icon {
        case .text(let text):
             
             
            let icon = ClashMacMenuRowMetrics.middleTruncated(text, width: ClashMacMenuRowMetrics.groupNameCap / 4, font: font)
            title.append(NSAttributedString(string: icon + " ", attributes: [.font: font]))
        case .image(let image):
            let attachment = NSTextAttachment()
            attachment.image = image
             
             
            let side = groupIconSide
            let width = image.size.height > 0 ? (side * image.size.width / image.size.height).rounded() : side
            attachment.bounds = CGRect(x: 0, y: (font.capHeight - side) / 2, width: width, height: side)
            title.append(NSAttributedString(attachment: attachment))
            title.append(NSAttributedString(string: " ", attributes: [.font: font]))
        case nil:
            break
        }
        let room = ClashMacMenuRowMetrics.groupNameCap - title.size().width
        title.append(NSAttributedString(string: ClashMacMenuRowMetrics.middleTruncated(name, width: room, font: font),
                                        attributes: [.font: font]))
        return title
    }

     
     
     
    private static func setGroupTitle(
        _ group: ClashMacMenuProxyCatalog.Group,
        on item: NSMenuItem,
        showsIconImages: Bool,
        forgetsRefusal: Bool
    ) {
        let icon = groupIcon(group.icon, showsIconImages: showsIconImages)
        setName(groupTitle(name: group.name, icon: icon), on: item)
        guard case .remote = ClashProxyGroupIconKind.of(group.icon), showsIconImages, let address = group.icon else { return }
        let name = group.name
         
         
        let key = address.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor [weak item] in
            if forgetsRefusal { await ProxyGroupIconStore.shared.forgetRefusal(for: key) }
            let image = await ProxyGroupIconStore.shared.image(for: key)
            guard let item else { return }
             
             
            setName(groupTitle(name: name, icon: image.map { .image(roundedIcon($0)) }), on: item)
        }
    }

     
    private static var lastBuiltConnected = false

     
     
    static func proxiesPageDrawsIconImages() -> Bool {
        (ClashProxiesDisplayPreferences.uiTestOverride() ?? ClashProxiesDisplayPreferences.load()).groupIconImages
    }

     
    private static func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private static func row(
        _ title: String,
        identifier: String? = nil,
        state: NSControl.StateValue = .off,
        _ perform: @escaping () -> Void
    ) -> NSMenuItem {
        let target = ClashMacMenuRowAction(perform)
        let item = NSMenuItem(
            title: title,
            action: #selector(ClashMacMenuRowAction.fire(_:)),
            keyEquivalent: ""
        )
        item.target = target
        item.representedObject = target
        item.state = state
        if let identifier {
            item.setAccessibilityIdentifier(identifier)
        }
        return item
    }
}

extension AppleClientConnectionPhase {
     
     
     
    var statusTitle: String {
        switch self {
        case .disconnected: "Disconnected"
        case .preparing: "STARTING"
        case .connected: "Connected"
        case .disconnecting: "STOPPING"
        case .unavailable: "Unavailable"
        }
    }
}

extension AppleClientConnectionIntent {
    var toolbarTitle: String {
        switch self {
        case .connect: "START"
        case .disconnect: "STOP"
        case .installConfiguration: "Set Up"
        case .activateSystemExtension: "Activate"
        case .updateSystemExtension: "Update"
        }
    }
}

extension AppleClientOutboundMode {
    var menuTitle: String {
        switch self {
        case .global: "Global"
        case .rule: "Rule"
        case .direct: "Direct"
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class ClashMacStatusMenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu()

    private let snapshot: () -> ClashMacStatusMenuSnapshot
    private let actions: ClashMacStatusMenuActions
    private let locale: Locale
    private let optionIsHeld: () -> Bool
    private let tunnelIsUp: () -> Bool
    private let latency: AnyPublisher<[String: [String: ClashProxyLatencyState]], Never>?
    private let testing: AnyPublisher<Bool, Never>?
    private let listenerUpdates: AnyPublisher<Void, Never>?
    private var listening: Set<AnyCancellable> = []

     
     
    var isListening: Bool { !listening.isEmpty }
     
     
    private var latestLatency: [String: [String: ClashProxyLatencyState]] = [:]

    init(
        snapshot: @escaping () -> ClashMacStatusMenuSnapshot,
        actions: ClashMacStatusMenuActions,
        locale: Locale = .current,
        optionIsHeld: @escaping () -> Bool = { NSEvent.modifierFlags.contains(.option) },
        tunnelIsUp: @escaping () -> Bool = { false },
        latency: AnyPublisher<[String: [String: ClashProxyLatencyState]], Never>? = nil,
        testing: AnyPublisher<Bool, Never>? = nil,
        listenerUpdates: AnyPublisher<Void, Never>? = nil
    ) {
        self.snapshot = snapshot
        self.actions = actions
        self.locale = locale
        self.optionIsHeld = optionIsHeld
        self.tunnelIsUp = tunnelIsUp
        self.latency = latency
        self.testing = testing
        self.listenerUpdates = listenerUpdates
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
    }

     
     
     
     
     
     
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.items.isEmpty else { return }
        var current = snapshot()
        current.offersQuitLeavingTunnel = optionIsHeld() && tunnelIsUp()
         
        current.prefersLoopbackShellCommand = optionIsHeld()
        let built = ClashMacStatusMenuBuilder.makeMenu(current, actions: actions, locale: locale)
        for item in built.items {
            built.removeItem(item)
            menu.addItem(item)
            if let submenu = item.representedObject as? ClashMacProxySubmenuController,
               let name = submenu.groupName {
                submenu.latestReadings = { [weak self] in self?.latestLatency[name] }
            }
        }
    }

     
     
     
    func menuWillOpen(_ menu: NSMenu) {
         
         
         
         
        if let container = ClashAppIdentifiers.appGroupContainer, ModuleEngineReadinessSource.observesInThisProcess {
            ModuleEngineReadinessSource.shared(container).scheduleRecheck()
        }
        listening.removeAll()
        listenerUpdates?
            .sink { [weak self] in self?.refreshCopyCommand() }
            .store(in: &listening)
         
        if listenerUpdates != nil { refreshCopyCommand() }
        latency?
            .sink { [weak self] latency in self?.apply(latency: latency) }
            .store(in: &listening)
        testing?
            .sink { [weak self] isTesting in self?.setTesting(isTesting) }
            .store(in: &listening)
    }

    private func refreshCopyCommand() {
        guard let item = menu.items.first(where: {
            ["menu-bar.copy-shell-command", "menu-bar.copy-shell-command-loopback"].contains($0.accessibilityIdentifier())
        }) else { return }
        let current = snapshot()
        let external = item.accessibilityIdentifier() != "menu-bar.copy-shell-command-loopback"
            && current.offersExternalShellCommand
        let copy = actions.copyShellCommand
        let target = ClashMacMenuRowAction { copy(external) }
        item.target = target
        item.representedObject = target
        item.isEnabled = current.offersShellCommand
    }

     
     
     
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for case let row as ClashMacTrailingMenuItem in menu.items {
            row.isUnderHighlight = row === item
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        listening.removeAll()
        latestLatency = [:]
        menu.removeAllItems()
    }

     
     
     
     
    func apply(latency: [String: [String: ClashProxyLatencyState]]) {
        latestLatency = latency
        for item in menu.items {
            guard let submenu = item.representedObject as? ClashMacProxySubmenuController,
                  let name = submenu.groupName else { continue }
            submenu.apply(latency: latency[name] ?? [:])
             
             
             
            let member = actions.currentMember(name) ?? submenu.checkedName
            if let member, let fresh = latency[name]?[member], fresh != .testing {
                ClashMacStatusMenuBuilder.setGroupTrailing(member: member, reading: fresh, on: item)
            }
        }
    }

     
    func setTesting(_ isTesting: Bool) {
        for item in menu.items {
            (item.representedObject as? ClashMacProxySubmenuController)?.setTesting(isTesting)
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
enum ClashMacStatusItemLabel {
     
     
    static let dimmedCatAlpha: CGFloat = 0.5

    static func image(showsSpeed: Bool, upLine: String, downLine: String, tunnelIsUp: Bool) -> NSImage? {
        let catAlpha: CGFloat = tunnelIsUp ? 1 : dimmedCatAlpha
        if showsSpeed,
           let drawn = ClashMacMenuBarSpeed.menuBarImage(upLine: upLine, downLine: downLine, catAlpha: catAlpha) {
            drawn.isTemplate = true
            return drawn
        }
         
         
        guard let cat = NSImage(named: ClashMacAsset.menuBarTemplate.rawValue) else { return nil }
        cat.isTemplate = true
        if catAlpha == 1 { return cat }
        let dimmed = NSImage(size: cat.size, flipped: false) { rect in
            cat.draw(in: rect, from: .zero, operation: .sourceOver, fraction: catAlpha)
            return true
        }
        dimmed.isTemplate = true
        return dimmed
    }

    static func accessibilityLabel(showsSpeed: Bool, upLine: String, downLine: String) -> String {
        showsSpeed ? "Clash — \(upLine), \(downLine)" : "Clash"
    }
}

extension ClashMacStatusMenuSnapshot {
     
    static let empty = ClashMacStatusMenuSnapshot(
        phase: .unavailable,
        primaryIntent: nil,
        outboundMode: .rule,
        selectedRouteName: nil,
        proxies: ClashMacMenuProxyCatalog(groups: []),
        showsSpeedInMenuBar: false,
        hidesDockIcon: false,
        upLine: "",
        downLine: "",
        offersQuitLeavingTunnel: false,
        offersShellCommand: false,
        offersExternalShellCommand: false,
        prefersLoopbackShellCommand: false
    )
}



 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class ClashMacTrailingMenuItem: NSMenuItem {
     
    let spokenName: String
    var name: NSAttributedString
    var plain: String?
    var member: String?
    var reading: ClashProxyLatencyState?
     
    var reserved: CGFloat = 0
     
    var stop: CGFloat = 0
    var isUnderHighlight = false {
        didSet { if isUnderHighlight != oldValue { compose(rewriting: true) } }
    }

    init(title: String) {
        spokenName = title
        name = NSAttributedString(string: title, attributes: [.font: ClashMacMenuRowMetrics.font])
        super.init(title: title, action: nil, keyEquivalent: "")
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("not archived")
    }

     
    var trailingText: String {
        if let plain { return plain }
        let room = stop - ClashMacMenuRowMetrics.trailingGap - name.size().width
        return ClashMacStatusMenuBuilder.trailingText(member: member, reading: reading, room: room)
    }

    func compose(rewriting: Bool = false) {
         
        guard stop > 0 else {
            attributedTitle = name
            return
        }
        let text = trailingText
         
        let spokenTrailing = plain ?? ((member ?? "") + ClashMacStatusMenuBuilder.readingSuffix(reading))
        setAccessibilityTitle(spokenTrailing.isEmpty ? spokenName : "\(spokenName), \(spokenTrailing)")
         
        if !rewriting, attributedTitle?.string == name.string + (text.isEmpty ? "" : "\t" + text) { return }
        guard !text.isEmpty else {
            attributedTitle = name
            return
        }
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: stop)]
        style.lineBreakMode = .byClipping
        let title = NSMutableAttributedString(attributedString: name)
        let font = ClashMacMenuRowMetrics.trailingFont
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
             
            .baselineOffset: (ClashMacMenuRowMetrics.font.capHeight - font.capHeight) / 2,
        ]
         
         
        if isEnabled, !isUnderHighlight { attributes[.foregroundColor] = NSColor.secondaryLabelColor }
        title.append(NSAttributedString(string: "\t" + text, attributes: attributes))
        title.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: title.length))
        attributedTitle = title
    }
}
