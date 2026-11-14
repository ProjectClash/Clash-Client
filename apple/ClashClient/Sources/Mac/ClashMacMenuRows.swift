import AppKit
import ClashClientUI
import SwiftUI

 
 
 
@MainActor
final class ClashMacMenuRowModel: ObservableObject {
    enum Kind: Equatable {
         
        case member
         
        case test
         
         
        case more
    }

    let kind: Kind
    let name: String
     
     
    var emptyNote: String?
    @Published var latency: ClashProxyLatencyState
    @Published var isCurrent: Bool
    @Published var isHighlighted = false
    @Published var isTesting = false

    init(
        kind: Kind,
        name: String,
        latency: ClashProxyLatencyState = .untested,
        isCurrent: Bool = false,
        emptyNote: String? = nil
    ) {
        self.kind = kind
        self.name = name
        self.emptyNote = emptyNote
        self.latency = latency
        self.isCurrent = isCurrent
    }

     
     
     
    var badgeText: String {
        if let emptyNote { return emptyNote }
        return Self.latencyText(latency)
    }

     
     
     
    static func latencyText(_ latency: ClashProxyLatencyState) -> String {
        switch latency {
        case .measured(let milliseconds): "\(milliseconds) ms"
        case .failed, .timedOut: "—"
        case .untested, .testing: ""
        }
    }
}

 
 
 
 
struct ClashMacMenuRow: View {
    @ObservedObject var model: ClashMacMenuRowModel
    let pointSize: CGFloat

    var body: some View {
        HStack(spacing: 0) {
             
            Group {
                if model.isCurrent {
                    Image(systemName: ClashSymbol.checkmark.rawValue)
                        .font(.system(size: pointSize - 2, weight: .semibold))
                } else {
                    Color.clear
                }
            }
            .frame(width: ClashMacMenuRowMetrics.leadingColumn, alignment: .center)

            ClashRegionalFlag.label(model.name, pointSize: pointSize, relativeTo: .body)
                .font(.system(size: pointSize))
                .lineLimit(1)
                .truncationMode(.middle)
                 
                 
                 
                 
                 

            Spacer(minLength: 8)

            switch model.kind {
            case .test:
                 
                 
                if model.isTesting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: ClashSymbol.bolt.rawValue)
                        .font(.system(size: pointSize - 1, weight: .semibold))
                        .foregroundStyle(model.isHighlighted ? .white : .secondary)
                }
            case .member:
                badge
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            case .more:
                EmptyView()
            }
        }
        .padding(.trailing, 8)
        .frame(height: ClashMacMenuRowHost.rowHeight)
        .background(
            model.isHighlighted
                ? Color(nsColor: .selectedContentBackgroundColor)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
        )
        .padding(.horizontal, ClashMacMenuRowMetrics.highlightInset)
        .foregroundStyle(model.isHighlighted ? Color.white : Color(nsColor: .labelColor))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityDescription))
         
         
        .accessibilityValue(model.isCurrent ? "Selected" : "")
    }

     
     
     
     
    @ViewBuilder
    private var badge: some View {
        if let note = model.emptyNote {
            Text(verbatim: note)
                .font(.system(size: pointSize - 3, weight: .medium))
                .foregroundStyle(model.isHighlighted ? .white : .secondary)
                .padding(.horizontal, 6)
        } else {
            latencyBadge
        }
    }

    @ViewBuilder
    private var latencyBadge: some View {
        switch model.latency {
        case .measured:
             
             
             
             
             
             
             
            Text(verbatim: model.badgeText)
                .font(.system(size: pointSize - 3, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(model.isHighlighted ? Color.white : tierInk)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    tierColor.opacity(model.isHighlighted ? 0.45 : 0.22),
                    in: Capsule()
                )
        case .failed, .timedOut:
            Text(verbatim: model.badgeText)
                .font(.system(size: pointSize - 3, weight: .medium, design: .monospaced))
                .foregroundStyle(model.isHighlighted ? .white : .secondary)
                .padding(.horizontal, 6)
        case .testing:
            ProgressView()
                .controlSize(.mini)
        case .untested:
            EmptyView()
        }
    }

     
     
    private var tierColor: Color {
        switch model.latency.tier {
        case .fast: .green
        case .slow: .yellow
        case .slower: .orange
        case nil: .secondary
        }
    }

     
     
     
     
    private var tierInk: Color {
        let tier = tierColor
        return Color(nsColor: NSColor(name: nil) { appearance in
            let base = NSColor(tier)
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua { return base }
            return base.blended(withFraction: 0.4, of: .black) ?? base
        })
    }

    private var accessibilityDescription: String {
        var parts = [model.name]
        if !model.badgeText.isEmpty { parts.append(model.badgeText) }
        return parts.joined(separator: ", ")
    }
}

 
 
 
 
 
 
 
 
 
@MainActor
final class ClashMacMenuRowHost: NSHostingView<ClashMacMenuRow> {
     
     
     
     
     
    static let rowHeight: CGFloat = {
        func height(rows: Int) -> CGFloat {
            let menu = NSMenu()
            for _ in 0..<rows {
                menu.addItem(NSMenuItem(title: "Sample", action: nil, keyEquivalent: ""))
            }
            return menu.size.height
        }
        let measured = height(rows: 2) - height(rows: 1)
        return measured > 0 ? measured : 22
    }()

    var model: ClashMacMenuRowModel { rootView.model }
     
     
    var closesMenuOnClick = true
    var onClick: () -> Void = {}

    static func make(
        model: ClashMacMenuRowModel,
        width: CGFloat,
        pointSize: CGFloat,
        closesMenuOnClick: Bool,
        onClick: @escaping () -> Void
    ) -> ClashMacMenuRowHost {
        let host = ClashMacMenuRowHost(rootView: ClashMacMenuRow(model: model, pointSize: pointSize))
        host.closesMenuOnClick = closesMenuOnClick
        host.onClick = onClick
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: width, height: rowHeight)
        host.autoresizingMask = [.width]
        return host
    }

    required init(rootView: ClashMacMenuRow) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ClashMacMenuRowHost is built in code")
    }

    override func mouseUp(with event: NSEvent) {
        performClick()
    }

     
     
    func performClick() {
        if closesMenuOnClick {
            enclosingMenuItem?.menu?.cancelTracking()
        }
        onClick()
    }
}

 
 
 
 
 
 
 
@MainActor
enum ClashMacMenuRowMetrics {
    static var font: NSFont { NSFont.menuFont(ofSize: 0) }
    static var pointSize: CGFloat { font.pointSize }

     
     
     
    static let memberCap: CGFloat = 300

     
     
     
     
     
     
     
     
    static let groupNameCap: CGFloat = 148

     
    static let routeNameCap: CGFloat = 240

     
     
    static var trailingFont: NSFont { NSFont.menuFont(ofSize: NSFont.smallSystemFontSize) }

     
     
     
     
     
    static let menuWidthCap: CGFloat = 335

     
    static let leastTrailingRoom: CGFloat = 96

     
    static let trailingGap: CGFloat = 12

     
     
     
     
     
    static func middleTruncated(_ text: String, width: CGFloat, font given: NSFont? = nil, keepsTail: Bool = false) -> String {
        let attributes: [NSAttributedString.Key: Any] = [.font: given ?? font]
        func fits(_ candidate: String) -> Bool { (candidate as NSString).size(withAttributes: attributes).width <= width }
        guard !fits(text) else { return text }
        let characters = Array(text)
        func cut(keeping kept: Int) -> String {
            let head = keepsTail ? kept / 3 : (kept + 1) / 2
            return String(characters[..<head]) + "…" + String(characters[(characters.count - (kept - head))...])
        }
        var low = 0, high = characters.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if fits(cut(keeping: middle)) { low = middle } else { high = middle - 1 }
        }
        return cut(keeping: low)
    }

     
    static let highlightInset: CGFloat = 5
     
     
    static let leadingColumn: CGFloat = 19

     
     
     
    private static let chrome: CGFloat = highlightInset * 2 + leadingColumn + 8 + 8

    private static func widest(_ strings: [String]) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return (strings + [""]).map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 0
    }

     
     
     
     
    static func memberRowWidth(names: [String], note: String? = nil) -> CGFloat {
        let sample = ClashMacMenuRowModel(kind: .member, name: "", latency: .measured(milliseconds: 999)).badgeText
        let digits = (sample as NSString).size(withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: pointSize - 3, weight: .medium),
        ]).width
        let words = ((note ?? "") as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: pointSize - 3, weight: .medium),
        ]).width
        let badge = max(digits, words) + 12
        return min(memberCap, (chrome + widest(names) + badge).rounded(.up))
    }
}

 
 
 
 
 
 
 
 
@MainActor
final class ClashMacProxySubmenuController: NSObject, NSMenuDelegate {
    private let group: () -> ClashMacMenuProxyCatalog.Group?
    private let actions: ClashMacStatusMenuActions
    private let locale: Locale
    private(set) var rows: [String: ClashMacMenuRowModel] = [:]
    private(set) var testRow: ClashMacMenuRowModel?
     
     
     
    private var delayOrderBase: [String]?
     
     
    private var orderReadings: [String: ClashProxyLatencyState] = [:]
     
     
    private var readingsChanged = false

     
    var groupName: String? { group()?.name }
     
     
    var checkedName: String? { group()?.checked }
     
     
     
    var latestReadings: (() -> [String: ClashProxyLatencyState]?)?

    init(
        group: @escaping () -> ClashMacMenuProxyCatalog.Group?,
        actions: ClashMacStatusMenuActions,
        locale: Locale
    ) {
        self.group = group
        self.actions = actions
        self.locale = locale
    }

     
     
     
     
     
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.items.isEmpty else { return }
        rows = [:]
        testRow = nil
        guard var group = group() else { return }
        for (name, fresh) in latestReadings?() ?? [:] {
            guard let shown = group.latency[name], shown != fresh else { continue }
            if fresh == .testing, shown != .testing {
                group.lastReadings[name] = shown
            } else if fresh != .testing {
                group.lastReadings[name] = nil
            }
            group.latency[name] = fresh
        }
         
        let members = group.listed
        delayOrderBase = group.sortsItsRows && group.sort == .delay ? group.members : nil
        orderReadings = delayOrderBase == nil ? [:]
            : Dictionary(members.map { ($0, group.orderReading(of: $0)) }, uniquingKeysWith: { first, _ in first })
        readingsChanged = false
        let pointSize = ClashMacMenuRowMetrics.pointSize
        let noNodes = ClashCopy.string("No nodes", locale: locale)
         
         
        let showAll = group.memberTotal.map {
            ClashCopy.format("Show All %@ Nodes…", locale: locale, $0.formatted(.number.locale(locale)))
        }
        let width = ClashMacMenuRowMetrics.memberRowWidth(
            names: members + [ClashCopy.string("Test latency", locale: locale)] + (showAll.map { [$0] } ?? []),
            note: group.emptyMembers.isEmpty ? nil : noNodes
        )

        let test = ClashMacMenuRowModel(kind: .test, name: ClashCopy.string("Test latency", locale: locale))
        let runTest = { [weak self, weak test] in
            if self?.actions.testGroup(group.name) == true { test?.isTesting = true }
        }
         
         
        let testTarget = ClashMacMenuRowAction(runTest)
        let testItem = NSMenuItem(title: test.name, action: #selector(ClashMacMenuRowAction.fire(_:)), keyEquivalent: "")
        testItem.target = testTarget
        testItem.representedObject = testTarget
        testItem.setAccessibilityIdentifier("menu-bar.test-group")
        testItem.view = ClashMacMenuRowHost.make(
            model: test, width: width, pointSize: pointSize, closesMenuOnClick: false, onClick: runTest
        )
        testRow = test
        menu.addItem(testItem)
        menu.addItem(.separator())

        for member in members {
             
            let isCurrent = member == group.checked
            let model = ClashMacMenuRowModel(
                kind: .member,
                name: member,
                latency: group.latency[member] ?? .untested,
                isCurrent: isCurrent,
                emptyNote: group.emptyMembers.contains(member) ? noNodes : nil
            )
            let pick = { [actions] in
                 
                 
                guard !isCurrent || group.pinsOnRepick else { return }
                actions.select(group.name, member)
            }
            let target = ClashMacMenuRowAction(pick)
            let item = NSMenuItem(
                title: member,
                action: #selector(ClashMacMenuRowAction.fire(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = target
            item.state = isCurrent ? .on : .off
            item.view = ClashMacMenuRowHost.make(
                model: model, width: width, pointSize: pointSize, closesMenuOnClick: true, onClick: pick
            )
            rows[member] = model
            menu.addItem(item)
        }
        if let showAll {
            menu.addItem(.separator())
            let more = ClashMacMenuRowModel(kind: .more, name: showAll)
            let open = { [actions] in actions.openGroup(group.name) }
            let target = ClashMacMenuRowAction(open)
            let item = NSMenuItem(title: showAll, action: #selector(ClashMacMenuRowAction.fire(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = target
            item.setAccessibilityIdentifier("menu-bar.show-all-members")
            item.view = ClashMacMenuRowHost.make(
                model: more, width: width, pointSize: pointSize, closesMenuOnClick: true, onClick: open
            )
            menu.addItem(item)
        }
    }

     
     
     
     
     
    func menuDidClose(_ menu: NSMenu) {
        for item in menu.items {
            (item.view as? ClashMacMenuRowHost)?.model.isHighlighted = false
        }
    }

     
     
     
     
     
     
    func menuWillOpen(_ menu: NSMenu) {
        takeTheSweepsOrder(in: menu)
    }

     
     
     
     
    private func takeTheSweepsOrder(in menu: NSMenu) {
        guard let base = delayOrderBase, readingsChanged else { return }
        let items = menu.items
         
        let run = items.indices.filter { (items[$0].view as? ClashMacMenuRowHost)?.model.kind == .member }
        guard let first = run.first, run.last.map({ $0 - first + 1 }) == run.count else { return }
        let byName = Dictionary(run.map { (items[$0].title, items[$0]) }, uniquingKeysWith: { first, _ in first })
        let ordered = ClashProxiesDisplayPreferences.Sort.delay
            .ordered(base.filter { byName[$0] != nil }, name: { $0 }, latency: { orderReadings[$0] ?? .untested })
            .compactMap { byName[$0] }
        guard ordered.count == run.count else { return }
        readingsChanged = false
        guard !zip(ordered, run.map { items[$0] }).allSatisfy({ $0 === $1 }) else { return }
        var reordered = items
        reordered.replaceSubrange(first..<(first + run.count), with: ordered)
        menu.items = reordered
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for candidate in menu.items {
            (candidate.view as? ClashMacMenuRowHost)?.model.isHighlighted = candidate === item
        }
    }

     
    func apply(latency: [String: ClashProxyLatencyState]) {
        for (name, model) in rows where model.emptyNote == nil {
            if let fresh = latency[name], fresh != model.latency {
                model.latency = fresh
                 
                if delayOrderBase != nil, fresh != .testing, orderReadings[name] != fresh {
                    orderReadings[name] = fresh
                    readingsChanged = true
                }
            }
        }
    }

    func setTesting(_ isTesting: Bool) {
        testRow?.isTesting = isTesting
    }
}
