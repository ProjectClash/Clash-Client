import AppKit
import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
@MainActor
public final class ClashMacSourceViewerModel: ObservableObject {
    public enum Phase: Equatable {
        case counting
        case ready
        case failed
    }

     
    public struct Reveal: Equatable {
        public let line: Int
        let serial: Int
         
         
        let selects: Bool
         
        var match: ConfigurationSourceMatch?
    }

     
     
     
    public static let matchCap = 100_000

    @Published public private(set) var phase: Phase = .counting
    @Published public private(set) var byteCount = 0
    @Published public private(set) var matches: [ConfigurationSourceMatch] = []
    @Published public private(set) var isSearching = false
    @Published public private(set) var hasMoreMatches = false
    @Published public private(set) var current: Int?
    @Published public private(set) var reveal: Reveal?
     
    @Published public var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }

    public var lineCount: Int { index?.lineCount ?? 0 }
     
    public var widestLineColumns: Int { index?.widestLineColumns ?? 0 }
    public var sections: [ConfigurationSourceSection] { index?.sections ?? [] }

    private let url: URL
    private let matchCap: Int
    private var text: ConfigurationSourceText?
    private var index: ConfigurationSourceIndex?
    private var byLine: [Int: [ConfigurationSourceMatch]] = [:]
    private var searchTask: Task<Void, Never>?
    private var pendingSearch: Task<Void, Never>?
    private var generation = 0
    private var serial = 0

    public init(url: URL, matchCap: Int = ClashMacSourceViewerModel.matchCap) {
        self.url = url
        self.matchCap = matchCap
    }

     
    public func open() async {
        guard index == nil else { return }
        let url = url
        let opened = await Task.detached(priority: .userInitiated) { () -> (ConfigurationSourceText, ConfigurationSourceIndex)? in
            guard let text = try? ConfigurationSourceText(contentsOf: url),
                  let index = try? text.buildIndex() else { return nil }
            return (text, index)
        }.value
        guard let opened else {
            phase = .failed
            return
        }
        (text, index) = opened
        byteCount = opened.0.byteCount
        phase = .ready
    }

     
    public func line(_ number: Int) -> String {
        guard let text, let index, number >= 0, number < index.lineCount else { return "" }
        return text.line(number, in: index)
    }

    public func matches(onLine number: Int) -> [ConfigurationSourceMatch] {
        byLine[number] ?? []
    }

     
    public var currentMatch: ConfigurationSourceMatch? {
        current.flatMap { matches.indices.contains($0) ? matches[$0] : nil }
    }

    public func next() { step(by: 1) }

    public func previous() { step(by: -1) }

     
    public func goTo(lineNumber: Int) {
        guard lineCount > 0 else { return }
        show(line: min(max(lineNumber, 1), lineCount) - 1, selects: true)
    }

    public func show(_ section: ConfigurationSourceSection) {
        show(line: section.line, selects: true)
    }

     
     
    public func search(_ query: String) async {
        pendingSearch?.cancel()
        searchTask?.cancel()
        generation &+= 1
        let generation = generation
        matches = []
        byLine = [:]
        current = nil
        hasMoreMatches = false
        guard !query.isEmpty, let text, let index else {
            isSearching = false
            return
        }
        isSearching = true
        let cap = matchCap
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            var kept = 0
             
             
            try? text.search(query, in: index, batchSize: 512) { batch in
                guard kept < cap else { return }
                let taken = Array(batch.prefix(cap - kept))
                kept += taken.count
                let full = kept >= cap
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.take(taken, full: full, generation: generation) }
                }
                if full { withUnsafeCurrentTask { $0?.cancel() } }
            }
            await MainActor.run { self?.finish(generation) }
        }
        searchTask = task
        await task.value
    }

     
    public func stopSearching() {
        query = ""
    }

    private func scheduleSearch() {
        pendingSearch?.cancel()
        let query = query
        pendingSearch = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            await self?.search(query)
        }
    }

    private func take(_ batch: [ConfigurationSourceMatch], full: Bool, generation: Int) {
        guard generation == self.generation, !batch.isEmpty else { return }
        matches.append(contentsOf: batch)
        for match in batch { byLine[match.line, default: []].append(match) }
        if full { hasMoreMatches = true }
        if current == nil {
            current = 0
            show(line: batch[0].line, selects: false, match: batch[0])
        }
    }

    private func finish(_ generation: Int) {
        guard generation == self.generation else { return }
        isSearching = false
    }

    private func step(by offset: Int) {
        guard !matches.isEmpty else { return }
        let count = matches.count
        let next = ((current ?? -offset) + offset + count) % count
        current = next
        show(line: matches[next].line, selects: false, match: matches[next])
    }

    private func show(line: Int, selects: Bool, match: ConfigurationSourceMatch? = nil) {
        serial &+= 1
        reveal = Reveal(line: line, serial: serial, selects: selects, match: match)
    }
}

 
 
 
 
 
 
 
 
 
 
 
struct ClashMacSourceViewerTable: NSViewRepresentable {
    @ObservedObject var model: ClashMacSourceViewerModel
    @Environment(\.locale) private var locale

    static let textColumn = NSUserInterfaceItemIdentifier("text")

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> ClashMacSourceLinesContainer {
        let table = ClashMacSourceLinesTable()
        table.headerView = nil
        table.style = .plain
        table.rowHeight = Coordinator.rowHeight
        table.intercellSpacing = .zero
        table.gridStyleMask = []
        table.allowsMultipleSelection = true
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.backgroundColor = .textBackgroundColor
        let text = NSTableColumn(identifier: Self.textColumn)
        text.width = 1_200
        table.addTableColumn(text)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.lines = { [weak coordinator = context.coordinator] rows in
            rows.map { coordinator?.model.line($0) ?? "" }
        }
        let menu = NSMenu()
        let copy = NSMenuItem(title: ClashCopy.string("Copy Line", locale: locale),
                              action: #selector(ClashMacSourceLinesTable.copyClickedLines(_:)), keyEquivalent: "")
        copy.target = table
        menu.addItem(copy)
        table.menu = menu
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        let numbers = ClashMacSourceLineNumbers(table: table, scrollView: scroll)
        scroll.verticalRulerView = numbers
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        context.coordinator.table = table
        context.coordinator.numbers = numbers
        context.coordinator.observeScrolling(of: scroll)
        return ClashMacSourceLinesContainer(scroll: scroll, table: table)
    }

    func updateNSView(_ container: ClashMacSourceLinesContainer, context: Context) {
        context.coordinator.model = model
        context.coordinator.apply()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let rowHeight: CGFloat = 17
         
        static let textInset: CGFloat = 12
        static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
         
        static let advance = ("0" as NSString).size(withAttributes: [.font: font]).width

        var model: ClashMacSourceViewerModel
        weak var table: NSTableView?
        weak var numbers: ClashMacSourceLineNumbers?
        private var shownLines = -1
        private var shownMatches = 0
        private var shownCurrent: Int?
        private var shownReveal: ClashMacSourceViewerModel.Reveal?

        init(model: ClashMacSourceViewerModel) {
            self.model = model
        }

         
        func observeScrolling(of scroll: NSScrollView) {
            scroll.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(rowsMoved(_:)),
                                                   name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        }

        @objc private func rowsMoved(_ notification: Notification) {
            numbers?.needsDisplay = true
        }

         
         
         
        static func contentWidth(columns: Int) -> CGFloat {
            CGFloat(columns) * advance + textInset
        }

         
         
        func apply() {
            guard let table else { return }
            if shownLines != model.lineCount {
                shownLines = model.lineCount
                numbers?.lineCount = model.lineCount
                (table as? ClashMacSourceLinesTable)?.contentWidth = Self.contentWidth(columns: model.widestLineColumns)
                table.enclosingScrollView?.superview?.needsLayout = true
                table.reloadData()
            } else if shownMatches != model.matches.count || shownCurrent != model.current {
                let visible = table.rows(in: table.visibleRect)
                if visible.length > 0 {
                    table.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<NSMaxRange(visible)),
                                     columnIndexes: IndexSet(integer: 0))
                }
            }
            shownMatches = model.matches.count
            shownCurrent = model.current
            if let reveal = model.reveal, reveal != shownReveal, reveal.line < table.numberOfRows {
                shownReveal = reveal
                scroll(to: reveal, in: table)
                if reveal.selects { table.selectRowIndexes(IndexSet(integer: reveal.line), byExtendingSelection: false) }
            }
        }

         
         
        private func scroll(to reveal: ClashMacSourceViewerModel.Reveal, in table: NSTableView) {
            guard let clip = table.enclosingScrollView?.contentView else {
                table.scrollRowToVisible(reveal.line)
                return
            }
            let rect = table.rect(ofRow: reveal.line)
            let top = max(rect.minY - clip.bounds.height / 3, 0)
            clip.scroll(to: NSPoint(x: clip.bounds.minX, y: min(top, max(table.bounds.height - clip.bounds.height, 0))))
            table.enclosingScrollView?.reflectScrolledClipView(clip)
            guard let lines = table as? ClashMacSourceLinesTable, let match = reveal.match, let span = span(of: match, in: table) else { return }
            if span.lowerBound < lines.across || span.upperBound > lines.across + lines.room {
                 
                 
                lines.setAcross(span.upperBound <= lines.room ? 0 : span.lowerBound - lines.room / 3)
            }
        }

         
        private func span(of match: ConfigurationSourceMatch, in table: NSTableView? = nil) -> ClosedRange<CGFloat>? {
            let line = model.line(match.line) as NSString
            let range = match.utf16Range(in: line as String)
            guard range.location != NSNotFound, NSMaxRange(range) <= line.length else { return nil }
             
             
            if let table, let cell = table.view(atColumn: 0, row: match.line, makeIfNecessary: false),
               let row = cell.subviews.first as? ClashMacSourceLineView, row.line.string == line as String {
                let start = row.x(ofOffset: range.location)
                return start...max(row.x(ofOffset: NSMaxRange(range)), start)
            }
            let drawn = ClashMacSourceLineView.onOneRow(NSAttributedString(string: line as String, attributes: [.font: Self.font]))
            let runs = ClashMacSourceLineView.runs(of: drawn, advance: Self.advance)
            let start = ClashMacSourceLineView.x(ofOffset: range.location, in: drawn, runs: runs)
            return start...max(ClashMacSourceLineView.x(ofOffset: NSMaxRange(range), in: drawn, runs: runs), start)
        }

        func numberOfRows(in tableView: NSTableView) -> Int { model.lineCount }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let column = tableColumn?.identifier else { return nil }
            let cell = (tableView.makeView(withIdentifier: column, owner: nil) as? NSTableCellView) ?? Self.cell(column)
            let line = model.line(row)
            let view = cell.subviews.first as? ClashMacSourceLineView
            view?.line = ClashMacSourceLineStyle.attributed(
                line, matches: model.matches(onLine: row), current: model.currentMatch, font: Self.font)
            view?.across = (tableView as? ClashMacSourceLinesTable)?.across ?? 0
            return cell
        }

        private static func cell(_ column: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = column
            let line = ClashMacSourceLineView()
            line.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(line)
            NSLayoutConstraint.activate([
                line.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: textInset),
                line.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                line.topAnchor.constraint(equalTo: cell.topAnchor),
                line.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
            ])
            return cell
        }
    }
}

 
 
public final class ClashMacSourceLinesContainer: NSView {
    let scroll: NSScrollView
    let table: ClashMacSourceLinesTable
    let scroller = NSScroller(frame: NSRect(x: 0, y: 0, width: 200, height: 15))
    private var fade: DispatchWorkItem?
     
     
    let indicator = NSView()
    private var showsWhenScrolling: Bool { NSScroller.preferredScrollerStyle == .overlay }

    @objc private func scrollerStyleChanged() {
        needsLayout = true
    }

    init(scroll: NSScrollView, table: ClashMacSourceLinesTable) {
        self.scroll = scroll
        self.table = table
        super.init(frame: .zero)
        addSubview(scroll)
         
        scroll.clipsToBounds = true
        clipsToBounds = true
         
         
         
         
         
         
        scroller.scrollerStyle = .legacy
        indicator.wantsLayer = true
        indicator.layer?.cornerRadius = 3
        indicator.alphaValue = 0
        addSubview(indicator)
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrollerStyleChanged),
            name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil
        )
         
         
         
        scroll.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrollerStyleChanged),
            name: NSView.frameDidChangeNotification, object: scroll.contentView
        )
        scroller.target = self
        scroller.action = #selector(scrolled(_:))
        scroller.isEnabled = true
        scroller.setAccessibilityIdentifier("source-viewer.across")
        addSubview(scroller)
        table.acrossChanged = { [weak self] in self?.reflect() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public override func layout() {
        super.layout()
        let overlaid = showsWhenScrolling
        let thickness = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
         
         
         
         
        if scroll.frame.width != bounds.width {
            scroll.frame = NSRect(x: 0, y: scroll.frame.minY, width: bounds.width, height: scroll.frame.height)
            scroll.tile()
        }
        table.tableColumns.last?.width = max(scroll.contentView.bounds.width - scroll.contentView.contentInsets.left, 0)
        let shows = table.furthestAcross > 0
        scroller.isHidden = !shows || overlaid
        indicator.isHidden = !shows || !overlaid
        scroller.frame = NSRect(x: 0, y: 0, width: bounds.width, height: thickness)
        let rows = shows && !overlaid
            ? NSRect(x: 0, y: thickness, width: bounds.width, height: max(bounds.height - thickness, 0)) : bounds
        if scroll.frame != rows { scroll.frame = rows }
        table.setAcross(table.across)
        reflect()
    }

    private func reflect() {
        let furthest = table.furthestAcross
        if (scroller.isHidden && indicator.isHidden) != (furthest <= 0) { needsLayout = true }
        guard furthest > 0, table.contentWidth > 0 else { return }
        scroller.knobProportion = min(table.room / table.contentWidth, 1)
        scroller.doubleValue = Double(table.across / furthest)
        guard showsWhenScrolling else { return }
        let track = max(bounds.width - 4, 0)
        let knob = min(max(track * table.room / table.contentWidth, 28), track)
        indicator.frame = NSRect(x: 2 + (track - knob) * table.across / furthest, y: 3, width: knob, height: 6)
        indicator.layer?.backgroundColor = NSColor.secondaryLabelColor.cgColor
         
        guard table.across != shownAcross else { return }
        shownAcross = table.across
        indicator.alphaValue = 1
        fade?.cancel()
        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                self?.indicator.animator().alphaValue = 0
            }
        }
        fade = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
    private var shownAcross: CGFloat = 0

    @objc private func scrolled(_ sender: NSScroller) {
        switch sender.hitPart {
        case .decrementPage: table.setAcross(table.across - table.room * 0.9)
        case .incrementPage: table.setAcross(table.across + table.room * 0.9)
        default: table.setAcross(CGFloat(sender.doubleValue) * table.furthestAcross)
        }
    }
}

 
 
 
 
 
 
final class ClashMacSourceLineView: NSView {
    static let runLength = 128

     
    var line = NSAttributedString() {
        didSet {
             
             
            let sameCharacters = line.string == oldValue.string
            guard !sameCharacters || line != oldValue else { return }
            drawn = Self.onOneRow(line)
            if !sameCharacters {
                runs = nil
                setAccessibilityValue(line.string)
            }
            needsDisplay = true
        }
    }

     
    private var drawn = NSAttributedString()

     
     
     
     
     
    static func onOneRow(_ text: NSAttributedString) -> NSAttributedString {
        let string = text.string as NSString
        var breaks: [Int] = []
        for index in 0..<string.length {
            switch string.character(at: index) {
            case 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029: breaks.append(index)
            default: break
            }
        }
        guard !breaks.isEmpty else { return text }
        let copy = NSMutableAttributedString(attributedString: text)
        for index in breaks { copy.replaceCharacters(in: NSRange(location: index, length: 1), with: "\u{2424}") }
        return copy
    }

     
    private var runs: [(range: NSRange, x: CGFloat)]?

     
    var across: CGFloat = 0 {
        didSet { if across != oldValue { needsDisplay = true } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
         
         
        clipsToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

     
     
    static func runs(of text: NSAttributedString, advance: CGFloat) -> [(range: NSRange, x: CGFloat)] {
        let string = text.string as NSString
        var out: [(NSRange, CGFloat)] = []
        var location = 0
        var x: CGFloat = 0
        while location < string.length {
            var end = min(location + runLength, string.length)
            if end < string.length { end = string.rangeOfComposedCharacterSequence(at: end).location }
            if end <= location { end = NSMaxRange(string.rangeOfComposedCharacterSequence(at: location)) }
            let range = NSRange(location: location, length: end - location)
            out.append((range, x))
            var plain = true
            for index in location..<end {
                let unit = string.character(at: index)
                if unit < 0x20 || unit > 0x7E { plain = false; break }
            }
            x += plain ? CGFloat(range.length) * advance : text.attributedSubstring(from: range).size().width
            location = end
        }
        return out
    }

     
     
    static func x(ofOffset offset: Int, in text: NSAttributedString, runs: [(range: NSRange, x: CGFloat)]) -> CGFloat {
        guard !runs.isEmpty else { return 0 }
        var low = 0, high = runs.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if runs[middle].range.location <= offset { low = middle } else { high = middle - 1 }
        }
        let run = runs[low]
        let inside = NSRange(location: run.range.location, length: max(min(offset, NSMaxRange(run.range)) - run.range.location, 0))
        return run.x + (inside.length == 0 ? 0 : text.attributedSubstring(from: inside).size().width)
    }

     
    func x(ofOffset offset: Int) -> CGFloat {
        Self.x(ofOffset: offset, in: drawn, runs: measured())
    }

    private func measured() -> [(range: NSRange, x: CGFloat)] {
        if let runs { return runs }
        let made = Self.runs(of: drawn, advance: ClashMacSourceViewerTable.Coordinator.advance)
        runs = made
        return made
    }

    override func draw(_ dirtyRect: NSRect) {
        let all = measured()
        guard !all.isEmpty else { return }
         
        let from = across + dirtyRect.minX, to = across + dirtyRect.maxX
         
        var low = 0, high = all.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if all[middle].x <= from { low = middle } else { high = middle - 1 }
        }
        let height = drawn.attributedSubstring(from: all[low].range).size().height
        let y = ((bounds.height - height) / 2).rounded()
        var index = low
        while index < all.count, all[index].x < to {
            drawn.attributedSubstring(from: all[index].range).draw(at: NSPoint(x: all[index].x - across, y: y))
            index += 1
        }
    }
}

 
 
final class ClashMacSourceLineNumbers: NSRulerView {
    private weak var table: NSTableView?
    var lineCount = 0 {
        didSet {
            guard lineCount != oldValue else { return }
            ruleThickness = Self.thickness(lineCount: lineCount)
            needsDisplay = true
        }
    }

     
    static func thickness(lineCount: Int) -> CGFloat {
        (CGFloat(String(max(lineCount, 1)).count) * ClashMacSourceViewerTable.Coordinator.advance + 20).rounded(.up)
    }

    init(table: NSTableView, scrollView: NSScrollView) {
        self.table = table
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = table
        ruleThickness = Self.thickness(lineCount: 0)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

     
     
    func numbers(in rect: NSRect) -> [(line: Int, rect: NSRect)] {
        guard let table, table.numberOfRows > 0 else { return [] }
        let inTable = convert(rect, to: table)
        let rows = table.rows(in: NSRect(x: table.bounds.minX, y: inTable.minY, width: 1, height: inTable.height))
        guard rows.length > 0 else { return [] }
        return (rows.location..<NSMaxRange(rows)).map { row in
            let rowRect = convert(table.rect(ofRow: row), from: table)
            return (row + 1, NSRect(x: 0, y: rowRect.minY, width: ruleThickness, height: rowRect.height))
        }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
         
         
        let font = ClashMacSourceViewerTable.Coordinator.font
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        for number in numbers(in: rect) {
            let text = String(number.line) as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: ruleThickness - 8 - size.width, y: number.rect.midY - size.height / 2),
                      withAttributes: attributes)
        }
    }
}

 
 
final class ClashMacSourceLinesTable: NSTableView {
    var lines: (([Int]) -> [String])?

     
     
     
     
    func restBesideTheNumbers() {
        guard let scroll = enclosingScrollView else { return }
        let clip = scroll.contentView
        let home = -clip.contentInsets.left
        guard clip.bounds.minX <= 0, clip.bounds.minX > home else { return }
        clip.scroll(to: NSPoint(x: home, y: clip.bounds.minY))
        scroll.reflectScrolledClipView(clip)
    }

    override func layout() {
        super.layout()
        restBesideTheNumbers()
        placeLines()
    }

     
    var contentWidth: CGFloat = 0 {
        didSet {
            guard contentWidth != oldValue else { return }
            setAcross(across)
            acrossChanged?()
        }
    }

     
    private(set) var across: CGFloat = 0

     
    var room: CGFloat { max((tableColumns.last?.width ?? 0) - ClashMacSourceViewerTable.Coordinator.textInset, 0) }
    var furthestAcross: CGFloat { max(contentWidth - room, 0) }

     
    var acrossChanged: (() -> Void)?

    func setAcross(_ wanted: CGFloat) {
        let next = min(max(wanted, 0), furthestAcross)
        guard next != across else { return }
        across = next
        placeLines()
        acrossChanged?()
    }

     
     
     
     
    func placeLines() {
        enumerateAvailableRowViews { rowView, _ in
            guard let cell = rowView.view(atColumn: 0) as? NSView else { return }
            (cell.subviews.first as? ClashMacSourceLineView)?.across = across
        }
    }

     
     
    override class var isCompatibleWithResponsiveScrolling: Bool { true }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private enum Swipe { case none, undecided, across, acrossCoasting }
    private var swipe = Swipe.none
    private var moved = NSSize.zero
     
     
     
    private var heldOpening: NSEvent?
    static let swipeDecidedAfter: CGFloat = 3

     
    override func scrollWheel(with event: NSEvent) {
        guard furthestAcross > 0 else {
            swipe = .none
            heldOpening = nil
            return super.scrollWheel(with: event)
        }
        let coasting = event.phase == [] && event.momentumPhase != []
         
        if event.phase == [] && event.momentumPhase == [] {
            swipe = .none
            heldOpening = nil
            return abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? move(by: event) : super.scrollWheel(with: event)
        }
         
        if swipe == .acrossCoasting {
            if coasting {
                move(by: event)
                if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) { swipe = .none }
                return
            }
            swipe = .none
        }
        if swipe == .across {
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                swipe = .none
            } else {
                move(by: event)
                if event.phase.contains(.ended) || event.phase.contains(.cancelled) { swipe = .acrossCoasting }
                return
            }
        }
        if swipe == .none {
             
            if event.phase.contains(.mayBegin) { return }
             
            if coasting { return super.scrollWheel(with: event) }
            swipe = .undecided
            moved = .zero
            heldOpening = event.phase.contains(.began) ? event : nil
        }
        moved.width += event.scrollingDeltaX
        moved.height += event.scrollingDeltaY
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
             
            swipe = .none
            heldOpening = nil
            return
        }
        guard max(abs(moved.width), abs(moved.height)) >= Self.swipeDecidedAfter else { return }
        if abs(moved.width) > abs(moved.height) {
            swipe = .across
            heldOpening = nil
            setAcross(across - moved.width)
        } else {
             
             
             
            swipe = .none
            let opening = heldOpening
            heldOpening = nil
            super.scrollWheel(with: opening ?? event)
        }
    }

    private func move(by event: NSEvent) {
        setAcross(across - event.scrollingDeltaX * (event.hasPreciseScrollingDeltas ? 1 : 10))
    }

    @objc func copy(_ sender: Any?) {
        put(Array(selectedRowIndexes))
    }

    @objc func copyClickedLines(_ sender: Any?) {
        let clicked = clickedRow
        guard clicked >= 0 else { return put(Array(selectedRowIndexes)) }
        put(selectedRowIndexes.contains(clicked) ? Array(selectedRowIndexes) : [clicked])
    }

     
     
     
     
    override func accessibilityChildren() -> [Any]? {
        onScreenRows
    }

     
     
    override func accessibilityRows() -> [NSAccessibilityRow]? {
        onScreenRows
    }

     
     
    @available(macOS, deprecated: 10.10)
    override func accessibilityAttributeValue(_ attribute: NSAccessibility.Attribute) -> Any? {
        switch attribute {
        case .rows, .children, .visibleRows: return onScreenRows
        default: return super.accessibilityAttributeValue(attribute)
        }
    }

    private var onScreenRows: [NSTableRowView] {
        let visible = rows(in: visibleRect)
        guard visible.length > 0 else { return [] }
        return (visible.location..<NSMaxRange(visible)).compactMap { rowView(atRow: $0, makeIfNecessary: false) }
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) { return !selectedRowIndexes.isEmpty }
        return super.validateUserInterfaceItem(item)
    }

     
     
    private func put(_ rows: [Int]) {
        guard !rows.isEmpty, let lines else { return }
        let text = lines(Array(rows.prefix(100_000))).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

 
 
enum ClashMacSourceLineStyle {
    static func attributed(_ line: String, matches: [ConfigurationSourceMatch],
                           current: ConfigurationSourceMatch?, font: NSFont) -> NSAttributedString {
        let text = NSMutableAttributedString(string: line, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        for token in ConfigurationSourceHighlight.tokens(in: line) {
            text.addAttribute(.foregroundColor, value: color(token.kind), range: token.range)
        }
        for match in matches {
            let range = match.utf16Range(in: line)
            guard range.location != NSNotFound, NSMaxRange(range) <= text.length else { continue }
            if match == current {
                text.addAttributes([.backgroundColor: NSColor.systemOrange.withAlphaComponent(0.9),
                                    .foregroundColor: NSColor.black], range: range)
            } else {
                text.addAttribute(.backgroundColor, value: matchBackground, range: range)
            }
        }
        return text
    }

    private static let matchBackground = NSColor(name: nil) { appearance in
        NSColor.systemYellow.withAlphaComponent(appearance.isDark ? 0.30 : 0.45)
    }

    private static func color(_ kind: ConfigurationSourceHighlight.Kind) -> NSColor {
        switch kind {
        case .key: return dynamic(light: 0x0B4F79, dark: 0x6BDFFF)
        case .string: return dynamic(light: 0xC41A16, dark: 0xFC6A5D)
        case .literal: return dynamic(light: 0x1C00CF, dark: 0xD0BF69)
        case .comment: return dynamic(light: 0x5D6C79, dark: 0x7F8C98)
        case .punctuation: return .secondaryLabelColor
        }
    }

    private static func dynamic(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.isDark ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                           blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        }
    }
}

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

 
public struct ClashMacSourceViewer: View {
    @StateObject private var model: ClashMacSourceViewerModel
    private let title: String
    @State private var asksLine = false
    @State private var typedLine = ""
    @Environment(\.locale) private var locale

    public init(url: URL, title: String) {
        _model = StateObject(wrappedValue: ClashMacSourceViewerModel(url: url))
        self.title = title
    }

    public var body: some View {
        content
            .frame(minWidth: 640, minHeight: 480)
            .navigationTitle(Text(verbatim: title))
            .navigationSubtitle(subtitle)
            .searchable(text: $model.query, placement: .toolbar, prompt: Text(clash: .copy("Find in Source")))
            .onSubmit(of: .search) { model.next() }
            .toolbar {
                ToolbarItemGroup {
                    findStatus
                    Button { model.previous() } label: {
                        Label { Text(clash: .copy("Previous Match")) } icon: { Image(systemName: "chevron.up") }
                    }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(model.matches.isEmpty)
                    .help(Text(clash: .copy("Previous Match")))
                    .accessibilityIdentifier("source-viewer.previous")
                    Button { model.next() } label: {
                        Label { Text(clash: .copy("Next Match")) } icon: { Image(systemName: "chevron.down") }
                    }
                    .keyboardShortcut("g", modifiers: .command)
                    .disabled(model.matches.isEmpty)
                    .help(Text(clash: .copy("Next Match")))
                    .accessibilityIdentifier("source-viewer.next")
                }
                ToolbarItem(placement: .primaryAction) { outline }
            }
            .sheet(isPresented: $asksLine) { goToLineSheet }
            .task { await model.open() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .counting:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            Text(clash: .copy("The source could not be opened."))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            ClashMacSourceViewerTable(model: model)
                .accessibilityIdentifier("source-viewer.lines")
        }
    }

     
    private var subtitle: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(model.byteCount), countStyle: .file)
        guard model.phase == .ready else {
            return model.byteCount > 0 ? size + " · " + ClashCopy.string("Counting lines…", locale: locale)
                : ClashCopy.string("Counting lines…", locale: locale)
        }
        return size + " · " + ClashDisplayText.format("%@ lines", [Self.number(model.lineCount, locale)]).resolved(locale: locale)
    }

     
     
    @ViewBuilder
    private var findStatus: some View {
        if !model.query.isEmpty {
            Group {
                if let current = model.current {
                    Text(verbatim: Self.number(current + 1, locale) + " / " + Self.number(model.matches.count, locale)
                        + (model.isSearching || model.hasMoreMatches ? "+" : ""))
                        .monospacedDigit()
                } else if model.isSearching {
                    Text(clash: .copy("Searching…"))
                } else {
                    Text(clash: .copy("No Results"))
                }
            }
            .foregroundStyle(.secondary)
            .help(model.isSearching ? Text(clash: .copy("Still searching. What's found so far is ready.")) : Text(verbatim: ""))
            .accessibilityIdentifier("source-viewer.find-status")
        }
    }

     
     
    private var outline: some View {
        Menu {
            Button { model.goTo(lineNumber: 1) } label: { Text(clash: .copy("Start of File")) }
            Divider()
            ForEach(model.sections, id: \.line) { section in
                Button { model.show(section) } label: { Text(verbatim: outlineTitle(section)) }
            }
            Divider()
            Button {
                typedLine = ""
                asksLine = true
            } label: { Text(clash: .copy("Go to Line…")) }
                .keyboardShortcut("l", modifiers: .command)
        } label: {
            Label { Text(clash: .copy("Outline")) } icon: { Image(systemName: "list.bullet.indent") }
        }
        .disabled(model.phase != .ready)
        .accessibilityIdentifier("source-viewer.outline")
    }

     
    private func outlineTitle(_ section: ConfigurationSourceSection) -> String {
        var parts = [section.name, ClashDisplayText.format("Line %@", [Self.number(section.line + 1, locale)]).resolved(locale: locale)]
        if section.items > 0 {
            let noun: String
            switch section.name {
            case "proxies": noun = "%@ nodes"
            case "proxy-groups": noun = "%@ groups"
            case "rules": noun = "%@ rules"
            default: noun = "%@ items"
            }
            parts.append(ClashDisplayText.format(noun, [Self.number(section.items, locale)]).resolved(locale: locale))
        }
        return parts.joined(separator: " · ")
    }

    private var goToLineSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(clash: .copy("Go to Line")).font(.headline)
            Text(clash: .format("%@ lines in all", [Self.number(model.lineCount, locale)]))
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField(text: $typedLine) { Text(clash: .copy("Go to Line")) }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .onSubmit(goToTypedLine)
                .accessibilityIdentifier("source-viewer.go-to-line.field")
            HStack {
                Spacer()
                Button(role: .cancel) { asksLine = false } label: { Text(clash: .copy("Cancel")) }
                    .keyboardShortcut(.cancelAction)
                Button(action: goToTypedLine) { Text(clash: .copy("Go")) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(Int(typedLine.filter(\.isNumber)) == nil)
                    .accessibilityIdentifier("source-viewer.go-to-line.go")
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func goToTypedLine() {
        guard let number = Int(typedLine.filter(\.isNumber)) else { return }
        asksLine = false
        model.goTo(lineNumber: number)
    }

    private static func number(_ value: Int, _ locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
