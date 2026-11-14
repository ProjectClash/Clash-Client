#if os(macOS)
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashActivityTable: NSViewRepresentable {
    let kind: ClashActivityTableKind
    let rows: [ClashActivityTableRow]
    let locale: Locale
    let canClose: Bool
     
     
    var followsNewest: Bool = true
    var onOpen: (ClashActivityTableRow) -> Void
    var onClose: ([ClashActivityTableRow]) -> Void = { _ in }
    var onFilter: (String) -> Void
    var onSelectionCount: (Int) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(kind: kind)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        coordinator.parent = self
        let table = ClashActivityNSTableView()
        table.coordinator = coordinator
         
         
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .clear
        table.gridStyleMask = []
        table.rowHeight = Coordinator.rowHeight
        table.intercellSpacing = NSSize(width: 12, height: 0)
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.allowsColumnSelection = false
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.focusRingType = .none
        table.headerView = NSTableHeaderView()

        for column in ClashActivityTableColumn.columns(for: kind) {
            let tableColumn = NSTableColumn(identifier: .init(column.rawValue))
            tableColumn.title = ClashCopy.string(column.title, locale: locale)
            tableColumn.headerToolTip = column == .status
                ? ClashCopy.string("Status", locale: locale) : nil
            tableColumn.width = column.width.ideal
            tableColumn.minWidth = column.width.min
            tableColumn.isHidden = column.hiddenByDefault
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(
                key: column.rawValue,
                ascending: !column.sortsDescendingFirst
            )
            if column == .status {
                tableColumn.maxWidth = column.width.ideal
                tableColumn.resizingMask = []
            } else {
                tableColumn.resizingMask = column.flexes
                    ? [.autoresizingMask, .userResizingMask]
                    : .userResizingMask
            }
            switch column.alignment {
            case .trailing: tableColumn.headerCell.alignment = .right
            case .center: tableColumn.headerCell.alignment = .center
            case .leading: break
            }
            table.addTableColumn(tableColumn)
        }
         
         
        table.autosaveName = "clash.activity.\(kind.rawValue).columns.v6"
        table.autosaveTableColumns = true
         
         
         
        let statusIndex = table.column(withIdentifier: .init(ClashActivityTableColumn.status.rawValue))
        if statusIndex > 0 { table.moveColumn(statusIndex, toColumn: 0) }
         
        table.sortDescriptors = [
            NSSortDescriptor(
                key: ClashActivityTableColumn.time.rawValue,
                ascending: false
            ),
        ]

        let headerMenu = NSMenu()
        headerMenu.delegate = coordinator
        coordinator.headerMenu = headerMenu
        table.headerView?.menu = headerMenu

        let rowMenu = NSMenu()
        rowMenu.delegate = coordinator
        coordinator.rowMenu = rowMenu
        table.menu = rowMenu

        table.dataSource = coordinator
        table.delegate = coordinator
        table.target = coordinator
        table.doubleAction = #selector(Coordinator.openClicked(_:))

        let scroll = ClashActivityScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        coordinator.table = table
        coordinator.scroll = scroll
        coordinator.apply(rows)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
         
        let resumed = followsNewest && coordinator.parent?.followsNewest == false
        coordinator.parent = self
        coordinator.apply(rows)
        if resumed { coordinator.scrollToNewest() }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        static let rowHeight: CGFloat = 28
        static let font = NSFont.systemFont(ofSize: 13)
         
         
        static let digits = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        let kind: ClashActivityTableKind
        var parent: ClashActivityTable?
        weak var table: NSTableView?
        weak var scroll: NSScrollView?
        var headerMenu: NSMenu?
        var rowMenu: NSMenu?
         
        private(set) var rows: [ClashActivityTableRow] = []
         
         
        private var incoming: [ClashActivityTableRow] = []
        private let bytes: ByteCountFormatter = {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .binary
            formatter.includesUnit = true
            return formatter
        }()
         
        private let clock: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm:ss"
            return formatter
        }()
        private var styledLocale: Locale?
         
         
        private var reportedSelectionCount: Int?

        init(kind: ClashActivityTableKind) {
            self.kind = kind
        }

         

         
         
        func scrollToNewest() {
            guard let table, let index = ClashActivityTableRow.newestIndex(in: rows) else { return }
            table.scrollRowToVisible(index)
        }

        func apply(_ newRows: [ClashActivityTableRow]) {
            incoming = newRows
            if let locale = parent?.locale, locale != styledLocale {
                styledLocale = locale
                if !rows.isEmpty { table?.reloadData() }
            }
            let next = sorted(newRows)
            let columns = visibleColumns()
            switch ClashActivityTableChange.between(rows, next, columns: columns) {
            case .none:
                rows = next
            case .cells(let changed):
                rows = next
                guard let table else { return }
                let visible = table.rows(in: table.visibleRect)
                for (index, columnsChanged) in changed
                where NSLocationInRange(index, visible) {
                    let indexes = IndexSet(
                        columnsChanged.compactMap { column in
                            let i = table.column(withIdentifier: .init(column.rawValue))
                            return i >= 0 ? i : nil
                        }
                    )
                    table.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: indexes)
                }
            case .reload:
                reload(to: next)
            }
        }

         
         
         
        private func reload(to next: [ClashActivityTableRow]) {
            guard let table, let scroll else {
                rows = next
                return
            }
            let selectedIDs = Set(table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
            let clip = scroll.contentView
            let visible = table.rows(in: clip.bounds)
            var anchor: (id: String, offset: CGFloat)?
            let atTop = visible.location == 0
            if !(atTop && (parent?.followsNewest ?? true)),
               rows.indices.contains(visible.location) {
                anchor = (
                    rows[visible.location].id,
                    clip.bounds.minY - table.rect(ofRow: visible.location).minY
                )
            }
            if !applyIncrementally(to: next, in: table) {
                rows = next
                table.reloadData()
            }
            if !selectedIDs.isEmpty {
                let indexes = IndexSet(rows.indices.filter { selectedIDs.contains(rows[$0].id) })
                table.selectRowIndexes(indexes, byExtendingSelection: false)
            }
            if let anchor, let index = rows.firstIndex(where: { $0.id == anchor.id }) {
                let y = table.rect(ofRow: index).minY + anchor.offset
                clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
                scroll.reflectScrolledClipView(clip)
            }
            reportSelectionCount()
        }

         
         
         
         
         
         
         
         
         
         
        private func reportSelectionCount() {
            let count = table?.selectedRowIndexes.count ?? 0
            guard count != reportedSelectionCount else { return }
            reportedSelectionCount = count
            DispatchQueue.main.async { [weak self] in
                self?.parent?.onSelectionCount(count)
            }
        }

         
         
         
         
         
         
         
         
        private func applyIncrementally(to next: [ClashActivityTableRow], in table: NSTableView) -> Bool {
            let old = rows
            let newIDs = Set(next.map(\.id))
            let oldIDs = Set(old.map(\.id))
            let survivorsOld = old.filter { newIDs.contains($0.id) }
            let survivorsNew = next.filter { oldIDs.contains($0.id) }
            guard survivorsOld.map(\.id) == survivorsNew.map(\.id) else { return false }
            let removed = IndexSet(old.indices.filter { !newIDs.contains(old[$0].id) })
            let inserted = IndexSet(next.indices.filter { !oldIDs.contains(next[$0].id) })
            table.beginUpdates()
            if !removed.isEmpty { table.removeRows(at: removed, withAnimation: []) }
            rows = next
            if !inserted.isEmpty { table.insertRows(at: inserted, withAnimation: []) }
            table.endUpdates()
             
             
            let columns = visibleColumns()
            let before = Dictionary(uniqueKeysWithValues: survivorsOld.map { ($0.id, $0) })
            let visible = table.rows(in: table.visibleRect)
            for index in next.indices where NSLocationInRange(index, visible) {
                guard let was = before[next[index].id] else { continue }
                let indexes = IndexSet(columns.compactMap { column in
                    guard column.differs(was, next[index]) else { return nil }
                    let i = table.column(withIdentifier: .init(column.rawValue))
                    return i >= 0 ? i : nil
                })
                if !indexes.isEmpty {
                    table.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: indexes)
                }
            }
            return true
        }

        private func sorted(_ values: [ClashActivityTableRow]) -> [ClashActivityTableRow] {
            guard let descriptor = table?.sortDescriptors.first,
                  let key = descriptor.key,
                  let column = ClashActivityTableColumn(rawValue: key)
            else { return values }
            return ClashActivityTableSorting.sorted(values, by: column, ascending: descriptor.ascending)
        }

        private func visibleColumns() -> [ClashActivityTableColumn] {
            guard let table else { return ClashActivityTableColumn.columns(for: kind) }
            return table.tableColumns.compactMap {
                $0.isHidden ? nil : ClashActivityTableColumn(rawValue: $0.identifier.rawValue)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let identifier = NSUserInterfaceItemIdentifier("clash.activity.row")
            let view = tableView.makeView(withIdentifier: identifier, owner: nil) as? ClashActivityRowView
                ?? ClashActivityRowView()
            view.identifier = identifier
            view.isStriped = row % 2 == 1
            return view
        }


        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            reload(to: sorted(incoming))
        }

        func tableView(_ tableView: NSTableView, shouldReorderColumn columnIndex: Int, toColumn newColumnIndex: Int) -> Bool {
            columnIndex != 0 && newColumnIndex != 0
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            reportSelectionCount()
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row index: Int) -> NSView? {
            guard let tableColumn,
                  let column = ClashActivityTableColumn(rawValue: tableColumn.identifier.rawValue),
                  rows.indices.contains(index)
            else { return nil }
            let row = rows[index]
            switch column {
            case .status:
                let cell = reuse(tableView, "status") { ClashActivityStatusCell() }
                cell.show(row.status)
                return cell
            case .process:
                let cell = reuse(tableView, "icon") { ClashActivityTextCell(showsIcon: true) }
                configure(cell, column, row)
                cell.icon.image = ClashActivityProcessIcons.icon(for: row.connection.processPath)
                return cell
            case .network, .proxy:
                let cell = reuse(tableView, "badge") { ClashActivityBadgeCell() }
                cell.show(
                    column.text(of: row, bytes: bytes, time: clock.string(from:)),
                    badge: column.badge(of: row)
                )
                cell.toolTip = column == .proxy ? row.proxyPath : nil
                return cell
            case .rule:
                let cell = reuse(tableView, "badge") { ClashActivityBadgeCell() }
                cell.show(row.ruleKind, badge: column.badge(of: row), detail: row.connection.rulePayload)
                cell.toolTip = row.connection.ruleDescription
                return cell
            default:
                let cell = reuse(tableView, "text") { ClashActivityTextCell(showsIcon: false) }
                configure(cell, column, row)
                return cell
            }
        }

        private func reuse<Cell: NSView>(_ tableView: NSTableView, _ id: String, make: () -> Cell) -> Cell {
            let identifier = NSUserInterfaceItemIdentifier("clash.activity.\(id)")
            if let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? Cell {
                return cell
            }
            let cell = make()
            cell.identifier = identifier
            return cell
        }

        private func configure(_ cell: ClashActivityTextCell, _ column: ClashActivityTableColumn, _ row: ClashActivityTableRow) {
            let label = cell.label
            label.stringValue = column.text(of: row, bytes: bytes, time: clock.string(from:))
            label.alignment = column.alignment == .trailing ? .right : .left
            label.lineBreakMode = column.truncatesInMiddle ? .byTruncatingMiddle : .byTruncatingTail
            label.textColor = column.isSecondaryText ? .secondaryLabelColor : .labelColor
            label.font = column == .download || column == .upload || column == .time
                ? Coordinator.digits : Coordinator.font
            cell.toolTip = column.truncatesInMiddle || column == .rule ? label.stringValue : nil
        }

         

         
         
        private func targetRows() -> [ClashActivityTableRow] {
            guard let table else { return [] }
            let clicked = table.clickedRow
            let indexes: IndexSet
            if clicked >= 0, !table.selectedRowIndexes.contains(clicked) {
                indexes = IndexSet(integer: clicked)
            } else {
                indexes = table.selectedRowIndexes
            }
            return indexes.compactMap { rows.indices.contains($0) ? rows[$0] : nil }
        }

        @objc func openClicked(_ sender: Any?) {
            guard let table, rows.indices.contains(table.clickedRow) else { return }
            parent?.onOpen(rows[table.clickedRow])
        }

        func openSelection() {
            guard let table, let index = table.selectedRowIndexes.first, rows.indices.contains(index) else { return }
            parent?.onOpen(rows[index])
        }

        func closeSelection() {
            guard parent?.canClose == true, kind == .connections else { return }
            let targets = table?.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0] : nil } ?? []
            if !targets.isEmpty { parent?.onClose(targets) }
        }

        func copySelection() {
            guard let table else { return }
            let hosts = table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].connection.destination : nil }
            guard !hosts.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hosts.joined(separator: "\n"), forType: .string)
        }

        @objc private func menuOpen(_ item: NSMenuItem) {
            if let row = targetRows().first { parent?.onOpen(row) }
        }

        @objc private func menuClose(_ item: NSMenuItem) {
            let targets = targetRows()
            if !targets.isEmpty { parent?.onClose(targets) }
        }

        @objc private func menuCopy(_ item: NSMenuItem) {
            let hosts = targetRows().map(\.connection.destination)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hosts.joined(separator: "\n"), forType: .string)
        }

        @objc private func menuFilter(_ item: NSMenuItem) {
            if let keyword = item.representedObject as? String { parent?.onFilter(keyword) }
        }

        @objc private func toggleColumn(_ item: NSMenuItem) {
            guard let id = item.representedObject as? String,
                  let column = table?.tableColumn(withIdentifier: .init(id))
            else { return }
            column.isHidden.toggle()
             
             
            table?.reloadData()
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            let locale = parent?.locale ?? .current
            func text(_ key: String) -> String { ClashCopy.string(key, locale: locale) }
            if menu === headerMenu {
                for tableColumn in table?.tableColumns ?? [] {
                    guard let column = ClashActivityTableColumn(rawValue: tableColumn.identifier.rawValue),
                          column != .host
                    else { continue }
                    let title = column == .status ? text("Status") : text(column.title)
                    let item = NSMenuItem(title: title, action: #selector(toggleColumn(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = column.rawValue
                    item.state = tableColumn.isHidden ? .off : .on
                    menu.addItem(item)
                }
                return
            }
            let targets = targetRows()
            guard let first = targets.first else { return }
            let open = NSMenuItem(
                title: text(kind == .connections ? "Connection Details" : "Request Details"),
                action: #selector(menuOpen(_:)), keyEquivalent: ""
            )
            open.target = self
            menu.addItem(open)
            if kind == .connections, parent?.canClose == true {
                let title = targets.count == 1
                    ? text("Close Connection")
                    : ClashCopy.format("Close %@ Connections", locale: locale, String(targets.count))
                let close = NSMenuItem(title: title, action: #selector(menuClose(_:)), keyEquivalent: "")
                close.target = self
                menu.addItem(close)
            }
            menu.addItem(.separator())
            let copy = NSMenuItem(title: text("Copy Host"), action: #selector(menuCopy(_:)), keyEquivalent: "")
            copy.target = self
            menu.addItem(copy)
            var filters: [(String, String)] = []
            if !first.connection.process.isEmpty {
                filters.append((text("Show Only This Process"), first.connection.process))
            }
            if !first.proxy.isEmpty, !first.connection.chains.isEmpty {
                filters.append((text("Show Only This Proxy"), first.proxy))
            }
            if targets.count == 1, !filters.isEmpty {
                menu.addItem(.separator())
                for (title, keyword) in filters {
                    let item = NSMenuItem(title: title, action: #selector(menuFilter(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = keyword
                    menu.addItem(item)
                }
            }
        }
    }
}

 
 
 
 
final class ClashActivityScrollView: NSScrollView {
    private var fitted = false

    override func tile() {
        super.tile()
        guard !fitted, contentView.bounds.width > 0,
              let table = documentView as? NSTableView
        else { return }
        fitted = true
        table.sizeToFit()
    }
}

 
 
 
final class ClashActivityRowView: NSTableRowView {
    var isStriped = false {
        didSet { if isStriped != oldValue { needsDisplay = true } }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isStriped else { return }
         
         
         
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        NSColor.labelColor.withAlphaComponent(dark ? 0.05 : 0.025).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 0), xRadius: 6, yRadius: 6).fill()
    }
}

 
 
final class ClashActivityNSTableView: NSTableView {
    weak var coordinator: ClashActivityTable.Coordinator?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:  
            coordinator?.openSelection()
        case 51, 117:  
            coordinator?.closeSelection()
        default:
            super.keyDown(with: event)
        }
    }

    @objc func copy(_ sender: Any?) {
        coordinator?.copySelection()
    }
}

final class ClashActivityTextCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    let icon = NSImageView()

    init(showsIcon: Bool) {
        super.init(frame: .zero)
        label.font = ClashActivityTable.Coordinator.font
        label.cell?.truncatesLastVisibleLine = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        textField = label
        if showsIcon {
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.imageScaling = .scaleProportionallyUpOrDown
            addSubview(icon)
            imageView = icon
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            ])
        } else {
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2).isActive = true
        }
        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

 
 
 
 
 
final class ClashActivityStatusCell: NSTableCellView {
    private let dot = NSView()
    private var status: ClashActivityTableRow.Status = .live

    override init(frame: NSRect) {
        super.init(frame: frame)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)
        NSLayoutConstraint.activate([
            dot.centerXAnchor.constraint(equalTo: centerXAnchor),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),
        ])
    }

    convenience init() { self.init(frame: .zero) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func show(_ status: ClashActivityTableRow.Status) {
        self.status = status
        paint()
        setAccessibilityLabel(status == .closed ? "Closed" : "Live")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    private func paint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            dot.layer?.backgroundColor = Self.color(for: status).cgColor
        }
    }

     
    static func color(for status: ClashActivityTableRow.Status) -> NSColor {
        status == .live
            ? .systemOrange
            : NSColor.secondaryLabelColor.withAlphaComponent(0.5)
    }
}

 
 
 
 
final class ClashActivityBadgeCell: NSTableCellView {
    private let pill = NSView()
    private let label = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private var badge: ClashActivityTableColumn.Badge?

    override init(frame: NSRect) {
        super.init(frame: frame)
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 4
        pill.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pill.addSubview(label)
        addSubview(pill)
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .labelColor
        detail.lineBreakMode = .byTruncatingTail
        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        addSubview(detail)
        textField = label
        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            pill.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
            detail.leadingAnchor.constraint(equalTo: pill.trailingAnchor, constant: 6),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
            detail.centerYAnchor.constraint(equalTo: centerYAnchor),
            pill.centerYAnchor.constraint(equalTo: centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: 17),
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
    }

    convenience init() { self.init(frame: .zero) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func show(_ text: String, badge: ClashActivityTableColumn.Badge?, detail: String = "") {
        label.stringValue = text
        self.detail.stringValue = detail
        self.badge = badge
        paint()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { if backgroundStyle != oldValue { paint() } }
    }

    private func paint() {
        let selected = backgroundStyle == .emphasized
        let text: NSColor
        let fill: NSColor?
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if let badge {
            (text, fill) = Self.colors(badge, dark: dark)
        } else {
            (text, fill) = (.labelColor, nil)
        }
        label.textColor = selected ? .white : text
        effectiveAppearance.performAsCurrentDrawingAppearance {
            pill.layer?.backgroundColor = fill.map { selected ? NSColor.white.withAlphaComponent(0.2).cgColor : $0.cgColor }
        }
    }
}

 
 
@MainActor
enum ClashActivityProcessIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for path: String) -> NSImage? {
        guard !path.isEmpty else { return nil }
        if let hit = cache[path] { return hit }
         
         
        var url = URL(fileURLWithPath: path)
        var bundle: URL?
        while url.pathComponents.count > 1 {
            if url.pathExtension == "app" { bundle = url }
            url.deleteLastPathComponent()
        }
        let image = NSWorkspace.shared.icon(forFile: (bundle ?? URL(fileURLWithPath: path)).path)
        image.size = NSSize(width: 16, height: 16)
        if cache.count > 512 { cache.removeAll() }
        cache[path] = image
        return image
    }

     
    static func largeIcon(for path: String) -> NSImage {
        var url = URL(fileURLWithPath: path)
        var bundle: URL?
        while url.pathComponents.count > 1 {
            if url.pathExtension == "app" { bundle = url }
            url.deleteLastPathComponent()
        }
        let image = path.isEmpty
            ? NSWorkspace.shared.icon(for: .applicationBundle)
            : NSWorkspace.shared.icon(forFile: (bundle ?? URL(fileURLWithPath: path)).path)
        image.size = NSSize(width: 48, height: 48)
        return image
    }
}

 
 
struct ClashActivityTableCard<Content: View>: View {
    let palette: ClashProductPalette
    @ViewBuilder let content: () -> Content

    var body: some View {
        ClashCardSurface(
            fill: palette.card,
            separator: palette.separator,
            cornerRadius: ClashTheme.Radius.card,
            paintsInSettingsIdiom: true
        ) {
            content()
                .padding(.vertical, 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: ClashTheme.Radius.card, style: .continuous))
    }
}

 
 
 
 
struct ClashActivityMacFilterBar: View {
    let summaries: [ClashActivityChainSummary]
    let total: Int
    @Binding var keywords: Set<String>

    private struct Outbound: Identifiable {
        let id: String
        var count = 0
        var upload: Int64 = 0
        var download: Int64 = 0
        var chains: Set<String> = []
    }

    private var outbounds: [Outbound] {
        var byName: [String: Outbound] = [:]
        for summary in summaries {
            guard let name = summary.chains.first else { continue }
            var value = byName[name] ?? Outbound(id: name)
            value.count += summary.connectionCount
            value.upload &+= summary.upload
            value.download &+= summary.download
            value.chains.insert(summary.chains.joined(separator: " → "))
            byName[name] = value
        }
        return byName.values.sorted { ($0.count, $1.id) > ($1.count, $0.id) }
    }

    var body: some View {
        let outbounds = outbounds
        let names = Set(outbounds.map(\.id))
        let others = keywords.subtracting(names).sorted()
        if !outbounds.isEmpty || !keywords.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if !outbounds.isEmpty {
                        word(
                            Text("All"), count: total,
                            traffic: (outbounds.reduce(0) { $0 &+ $1.download }, outbounds.reduce(0) { $0 &+ $1.upload }),
                            on: keywords.isDisjoint(with: names)
                        ) {
                            keywords.subtract(names)
                        }
                        ForEach(outbounds) { outbound in
                            word(
                                Text(verbatim: outbound.id), count: outbound.count,
                                traffic: (outbound.download, outbound.upload),
                                on: keywords.contains(outbound.id)
                            ) {
                                let wasOn = keywords.contains(outbound.id)
                                keywords.subtract(names)
                                if !wasOn { keywords.insert(outbound.id) }
                            }
                            .help(Text(verbatim: outbound.chains.sorted().joined(separator: "\n")))
                        }
                    }
                    ForEach(others, id: \.self) { keyword in
                        Button {
                            keywords.remove(keyword)
                        } label: {
                            HStack(spacing: 4) {
                                Text(verbatim: keyword)
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(ClashActivityFilterWordStyle(isOn: true))
                    }
                }
                .font(.subheadline)
            }
        }
    }

     
     
     
    private func word(
        _ title: Text, count: Int, traffic: (download: Int64, upload: Int64),
        on: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                title
                Text(verbatim: "\(count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .buttonStyle(ClashActivityFilterWordStyle(isOn: on))
    }
}

 
struct ClashActivityFilterWordStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isOn ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(isOn ? 0.10 : (configuration.isPressed ? 0.05 : 0)))
            )
            .contentShape(Capsule())
    }
}

 
 
 
struct ClashActivityMacStatusLine: View {
    let count: Int
    let total: Int
    let selected: Int
    let upload: Int64?
    let download: Int64?
    let kind: ClashActivityTableKind

    var body: some View {
        HStack(spacing: 12) {
            summary
            Spacer(minLength: 8)
            if let upload, let download {
                Text(verbatim: "↓ \(ClashActivityByteFormatter.count(download))  ↑ \(ClashActivityByteFormatter.count(upload))")
                    .monospacedDigit()
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private var summary: Text {
        let rows: Text = total > count
            ? Text(clash: .format("Showing first %@ of %@ connections", ["\(count)", "\(total)"]))
            : kind == .connections
                ? Text(clash: .format(count == 1 ? "%@ connection" : "%@ connections", ["\(count)"]))
                : Text(clash: .format(count == 1 ? "%@ request" : "%@ requests", ["\(count)"]))
        guard selected > 0 else { return rows }
        return Text(clash: .format("%@/%@ rows selected", ["\(selected)", "\(count)"]))
    }
}

 
struct ClashActivityMacBanner: View {
    let message: String
    let retry: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(verbatim: message)
                .lineLimit(2)
            Spacer(minLength: 8)
            if let retry {
                Button("Retry", action: retry)
                    .controlSize(.small)
            }
        }
        .font(.callout)
        .padding(.horizontal, 4)
    }
}

extension ClashActivityBadgeCell {
     
     
     
     
    static func colors(_ badge: ClashActivityTableColumn.Badge, dark: Bool) -> (NSColor, NSColor) {
        func rgb(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        let hex = ClashActivityBadgeStyle.hex(badge, dark: dark)
        return (rgb(hex.text), rgb(hex.fill))
    }
}

 
struct ClashActivityPill: View {
    let text: String
    let badge: ClashActivityTableColumn.Badge
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let (ink, fill) = ClashActivityBadgeCell.colors(badge, dark: colorScheme == .dark)
        Text(verbatim: text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color(nsColor: ink))
            .padding(.horizontal, 6)
            .frame(height: 17)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color(nsColor: fill)))
    }
}

 
 
 
 
 
struct ClashActivityMacConnectionDetail: View {
    let connection: ClashActivityConnectionSnapshot
    let title: String
    let palette: ClashProductPalette
    let copy: (String) -> Void
    @Environment(\.clashThroughputUnit) private var throughputUnit

    private var row: ClashActivityTableRow { ClashActivityTableRow(connection: connection) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                ForEach(sections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(clash: .copy(section.title))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        ClashActivityTableCard(palette: palette) {
                            VStack(spacing: 0) {
                                ForEach(Array(section.rows.enumerated()), id: \.offset) { index, fact in
                                    if index > 0 { Divider().padding(.leading, 16) }
                                    factRow(fact)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .clashPageTitle(.copy(title))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(nsImage: ClashActivityProcessIcons.largeIcon(for: connection.processPath))
                .resizable()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: connection.process.isEmpty ? connection.destination : connection.process)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
                Text(verbatim: connection.host.isEmpty ? connection.destination : "\(connection.host):\(connection.destinationPort)")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    if let badge = ClashActivityTableColumn.network.badge(of: row) {
                        ClashActivityPill(text: row.trafficProtocol.label, badge: badge)
                    }
                    if !connection.rule.isEmpty {
                        ClashActivityPill(text: row.ruleKind, badge: .ruleKind)
                        if !connection.rulePayload.isEmpty {
                            Text(verbatim: connection.rulePayload).font(.callout)
                        }
                    }
                    Text(verbatim: "→").foregroundStyle(.tertiary)
                    if row.isRejected {
                        ClashActivityPill(text: row.proxy, badge: .refused)
                    } else {
                        Text(verbatim: row.proxyPath).font(.callout)
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private struct Fact {
        let label: String
        let value: String
        var copyable = false
    }

    private struct Section {
        let title: String
        let rows: [Fact]
    }

    private var sections: [Section] {
        let c = connection
        let all: [Section] = [
            Section(title: "Session", rows: [
                Fact(label: "Created", value: c.start?.formatted(date: .abbreviated, time: .standard) ?? ""),
                Fact(label: "Protocol", value: row.trafficProtocol.label),
                Fact(label: "Process", value: c.process, copyable: true),
                Fact(label: "Process path", value: c.processPath, copyable: true),
                Fact(label: "User ID", value: c.uid > 0 ? String(c.uid) : ""),
                Fact(label: "Rule", value: c.ruleDescription),
            ]),
            Section(title: "Endpoints", rows: [
                Fact(label: "Host", value: c.host, copyable: true),
                Fact(label: "Source", value: c.source, copyable: true),
                Fact(label: "Destination", value: ipDestination, copyable: true),
                Fact(label: "Remote destination", value: c.remoteDestination, copyable: true),
            ]),
            Section(title: "Traffic", rows: [
                Fact(label: "Upload", value: ClashActivityByteFormatter.count(c.upload)),
                Fact(label: "Download", value: ClashActivityByteFormatter.count(c.download)),
                Fact(label: "Upload speed", value: c.uploadSpeed.map { ClashThroughputFormatter.rate($0, unit: throughputUnit) } ?? ""),
                Fact(label: "Download speed", value: c.downloadSpeed.map { ClashThroughputFormatter.rate($0, unit: throughputUnit) } ?? ""),
            ]),
            Section(title: "Proxy chain", rows: c.chains.map { Fact(label: "Proxy", value: $0) }),
            Section(title: "Metadata", rows: [
                Fact(label: "Destination GeoIP", value: c.destinationGeoIP.joined(separator: " ")),
                Fact(label: "Destination ASN", value: c.destinationIPASN),
                Fact(label: "Source GeoIP", value: c.sourceGeoIP.joined(separator: " ")),
                Fact(label: "Source ASN", value: c.sourceIPASN),
                Fact(label: "DNS mode", value: c.dnsMode),
                Fact(label: "Special proxy", value: c.specialProxy),
                Fact(label: "Special rules", value: c.specialRules),
            ]),
        ]
        return all
            .map { Section(title: $0.title, rows: $0.rows.filter { !$0.value.isEmpty }) }
            .filter { !$0.rows.isEmpty }
    }

    private var ipDestination: String {
        let c = connection
        guard !c.destinationIP.isEmpty else { return c.destination }
        guard !c.destinationPort.isEmpty, c.destinationPort != "0" else { return c.destinationIP }
        return c.destinationIP.contains(":") ? "[\(c.destinationIP)]:\(c.destinationPort)" : "\(c.destinationIP):\(c.destinationPort)"
    }

    private func factRow(_ fact: Fact) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(clash: .copy(fact.label))
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(verbatim: fact.value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if fact.copyable {
                Button { copy(fact.value) } label: {
                    Image(systemName: ClashSymbol.docOnClipboard.rawValue)
                }
                .buttonStyle(.borderless)
                .help(Text(clash: .copy("Copy")))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}
 
 
 
 
 
 
struct ClashActivityMacChainTotals: View {
    let summaries: [ClashActivityChainSummary]
    let palette: ClashProductPalette
    let onChoose: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    private let rowHeight: CGFloat = 28
    private let numberWidth: CGFloat = 90

    var body: some View {
        let lines = summaries.sorted { ($0.connectionCount, $1.path) > ($1.connectionCount, $0.path) }
        ClashActivityTableCard(palette: palette) {
            VStack(spacing: 0) {
                row(
                    Text(clash: .copy("Chain Totals")), Text(clash: .copy("Connections")),
                    Text(clash: .copy("Download")), Text(clash: .copy("Upload"))
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(height: 24)
                Divider()
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, summary in
                            Button {
                                if let outbound = summary.chains.first { onChoose(outbound) }
                            } label: {
                                row(
                                    Text(verbatim: summary.path),
                                    Text(verbatim: "\(summary.connectionCount)"),
                                    Text(verbatim: ClashActivityByteFormatter.count(summary.download)),
                                    Text(verbatim: ClashActivityByteFormatter.count(summary.upload))
                                )
                                .font(.system(size: 13))
                                .frame(height: rowHeight)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color(nsColor: .labelColor).opacity(
                                            index.isMultiple(of: 2) ? 0 : (colorScheme == .dark ? 0.05 : 0.025)
                                        ))
                                        .padding(.horizontal, 6)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: min(CGFloat(lines.count), 4) * rowHeight)
            }
        }
    }

     
    private func row(_ chain: Text, _ count: Text, _ down: Text, _ up: Text) -> some View {
        HStack(spacing: 0) {
            chain.lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            count.frame(width: numberWidth, alignment: .trailing)
            down.frame(width: numberWidth, alignment: .trailing)
            up.frame(width: numberWidth, alignment: .trailing)
        }
        .monospacedDigit()
        .padding(.horizontal, 18)
    }
}
#endif
