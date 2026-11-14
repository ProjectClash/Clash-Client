#if os(iOS)
import ClashClientKit
import ClashClientUI
import SwiftUI
import UIKit

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ConfigurationSourceViewerPage: View {
    let url: URL
    let title: String
    @StateObject private var model = ConfigurationSourceViewerModel()
    @Environment(\.locale) private var locale

    var body: some View {
         
         
        ConfigurationSourceViewerContent(url: url, locale: locale, model: model)
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(verbatim: title)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(verbatim: model.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("configuration.source-viewer.summary")
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    outline
                    Spacer()
                    Button { model.openFind() } label: {
                        Image(systemName: ClashSymbol.magnifyingglass.rawValue)
                    }
                    .disabled(model.outline == nil)
                    .accessibilityLabel(Text(clash: .copy("Find in Source")))
                    .accessibilityIdentifier("configuration.source-viewer.find")
                }
            }
            .modifier(ConfigurationSourceViewerBottomBar(hidden: model.finding))
    }

     
    private var outline: some View {
        Menu {
            if let entries = model.outline {
                Section {
                    ForEach(entries) { entry in
                        Button { model.go(toLine: entry.line) } label: {
                            Text(verbatim: entry.title)
                            Text(verbatim: entry.detail)
                        }
                    }
                }
                Button { model.askForLine() } label: {
                    Label { Text(clash: .copy("Go to Line…")) } icon: { Image(systemName: ClashSymbol.arrowRightToLine.rawValue) }
                }
            } else {
                Button {} label: { Text(clash: .copy("Counting lines…")) }
                    .disabled(true)
            }
        } label: {
            Label { Text(clash: .copy("Outline")) } icon: { Image(systemName: ClashSymbol.listBulletIndent.rawValue) }
        }
        .accessibilityIdentifier("configuration.source-viewer.outline")
    }
}

 
 
private struct ConfigurationSourceViewerBottomBar: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.toolbar(hidden ? .hidden : .visible, for: .bottomBar)
        } else {
            content
        }
    }
}

 
@MainActor
final class ConfigurationSourceViewerModel: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let id: Int
        let title: String
        let detail: String
        let line: Int
    }

     
    @Published var summary = ""
     
    @Published var outline: [Entry]?
     
    @Published var finding = false
    weak var controller: ConfigurationSourceViewerController?

    func go(toLine line: Int) { controller?.show(line: line, match: nil) }
    func askForLine() { controller?.askForLine() }
    func openFind() { controller?.openFind() }
}

struct ConfigurationSourceViewerContent: UIViewControllerRepresentable {
    let url: URL
    let locale: Locale
    let model: ConfigurationSourceViewerModel

    func makeUIViewController(context: Context) -> ConfigurationSourceViewerController {
        let controller = ConfigurationSourceViewerController(url: url, locale: locale, model: model)
        model.controller = controller
        return controller
    }

    func updateUIViewController(_ controller: ConfigurationSourceViewerController, context: Context) {}
}

@MainActor
final class ConfigurationSourceViewerController: UIViewController, UITableViewDataSource, UITableViewDelegate,
    UITextFieldDelegate {
    private let url: URL
    private let locale: Locale
    private weak var model: ConfigurationSourceViewerModel?

    private var source: ConfigurationSourceText?
    private var index: ConfigurationSourceIndex?
    private var indexTask: Task<Void, Never>?

    private let table = ConfigurationSourceTable(frame: .zero, style: .plain)
     
     
    private let across = UIScrollView()
    private var widths: [NSLayoutConstraint] = []
     
     
    private var contentWidth: NSLayoutConstraint?
     
     
    private var metrics: Metrics?
     
     
    private var measuredRuns: [Int: ConfigurationSourceLineRuns] = [:]
    private static let runsKept = 4096
    private let failure = UILabel()
    private let findBar = ConfigurationSourceFindBar()

    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var pendingQuery: DispatchWorkItem?
    private var matches: [ConfigurationSourceMatch] = []
    private var matchesByLine: [Int: [Int]] = [:]
    private var current: Int?
    private var searching = false

    init(url: URL, locale: Locale, model: ConfigurationSourceViewerModel) {
        self.url = url
        self.locale = locale
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        indexTask?.cancel()
        searchTask?.cancel()
    }

     

    private var wraps: Bool { traitCollection.horizontalSizeClass != .regular }

    private struct Metrics {
        let textFont: UIFont
        let gutterFont: UIFont
        let gutterWidth: CGFloat
    }

    private var measures: Metrics {
        if let metrics { return metrics }
        let textFont = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .monospacedSystemFont(ofSize: wraps ? 12.5 : 13.5, weight: .regular), compatibleWith: traitCollection)
        let gutterFont = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: .monospacedDigitSystemFont(ofSize: wraps ? 11 : 12, weight: .regular), compatibleWith: traitCollection)
        let digits = String(repeating: "0", count: max(String(index?.lineCount ?? 1).count, 3))
        let made = Metrics(
            textFont: textFont, gutterFont: gutterFont,
            gutterWidth: ceil((digits as NSString).size(withAttributes: [.font: gutterFont]).width) + 14)
        metrics = made
        return made
    }

    private var textFont: UIFont { measures.textFont }
    private var gutterFont: UIFont { measures.gutterFont }
    private var gutterWidth: CGFloat { measures.gutterWidth }
     
    private var textStart: CGFloat { gutterWidth + 10 }

     
    private var acrossOffset: CGFloat {
        wraps ? 0 : max(0, across.contentOffset.x + across.adjustedContentInset.left)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "configuration.source-viewer"

        across.translatesAutoresizingMaskIntoConstraints = false
        across.alwaysBounceHorizontal = false
        across.showsVerticalScrollIndicator = false
        across.delegate = self
        view.addSubview(across)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self
        table.delegate = self
        table.separatorStyle = .none
        table.allowsSelection = false
        table.register(ConfigurationSourceLineCell.self, forCellReuseIdentifier: ConfigurationSourceLineCell.identifier)
        table.accessibilityIdentifier = "configuration.source-viewer.lines"
        across.addSubview(table)
         
         
         
        setContentScrollView(table, for: .top)
        setContentScrollView(table, for: .bottom)
        NSLayoutConstraint.activate([
            across.topAnchor.constraint(equalTo: view.topAnchor),
            across.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            across.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            across.bottomAnchor.constraint(equalTo: view.bottomAnchor),
             
             
             
             
             
            table.topAnchor.constraint(equalTo: across.frameLayoutGuide.topAnchor),
            table.bottomAnchor.constraint(equalTo: across.frameLayoutGuide.bottomAnchor),
            table.leadingAnchor.constraint(equalTo: across.frameLayoutGuide.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: across.frameLayoutGuide.trailingAnchor),
            across.contentLayoutGuide.heightAnchor.constraint(equalTo: across.frameLayoutGuide.heightAnchor),
        ])

        failure.translatesAutoresizingMaskIntoConstraints = false
        failure.text = copy("The source could not be opened.")
        failure.textColor = .secondaryLabel
        failure.font = .preferredFont(forTextStyle: .body)
        failure.adjustsFontForContentSizeCategory = true
        failure.isHidden = true
        view.addSubview(failure)
        NSLayoutConstraint.activate([
            failure.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            failure.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
        ])

        findBar.translatesAutoresizingMaskIntoConstraints = false
        findBar.isHidden = true
        findBar.configure(locale: locale)
        findBar.field.delegate = self
        findBar.field.addTarget(self, action: #selector(queryChanged), for: .editingChanged)
        findBar.previousButton.addAction(UIAction { [weak self] _ in self?.step(-1) }, for: .primaryActionTriggered)
        findBar.nextButton.addAction(UIAction { [weak self] _ in self?.step(1) }, for: .primaryActionTriggered)
        findBar.done.addAction(UIAction { [weak self] _ in self?.closeFind() }, for: .primaryActionTriggered)
        view.addSubview(findBar)
        NSLayoutConstraint.activate([
            findBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            findBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            findBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])

        applyWidth()
        open()
    }

     
     
     
     
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        followTheLines()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
         
        followTheLines()
    }

    private func followTheLines() {
        var page = parent
        while let candidate = page, let above = candidate.parent, !(above is UINavigationController) { page = above }
        page?.setContentScrollView(table, for: .top)
        page?.setContentScrollView(table, for: .bottom)
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
         
         
        guard isViewLoaded else { return }
        guard previous?.horizontalSizeClass != traitCollection.horizontalSizeClass
            || previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else { return }
        applyWidth()
        table.reloadData()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
         
         
         
        let bottom = findBar.isHidden ? 0 : max(0, view.bounds.maxY - findBar.frame.minY - view.safeAreaInsets.bottom)
        if table.contentInset.bottom != bottom {
            table.contentInset.bottom = bottom
            table.verticalScrollIndicatorInsets.bottom = bottom
        }
    }

     
     
     
     
    private func applyWidth() {
        NSLayoutConstraint.deactivate(widths)
        metrics = nil
        measuredRuns = [:]
        let font = textFont
        let lineHeight = ceil(font.lineHeight + 2)
        table.estimatedRowHeight = lineHeight
        table.rowHeight = wraps ? UITableView.automaticDimension : lineHeight
        if wraps {
            contentWidth = nil
            widths = [across.contentLayoutGuide.widthAnchor.constraint(equalTo: across.frameLayoutGuide.widthAnchor)]
            across.contentOffset.x = -across.adjustedContentInset.left
        } else {
             
             
             
             
            let column = ("0" as NSString).size(withAttributes: [.font: font]).width
            let wide = across.contentLayoutGuide.widthAnchor.constraint(
                equalToConstant: textStart + CGFloat(index?.widestLineColumns ?? 0) * column + 24)
            wide.priority = .defaultHigh
            contentWidth = wide
            widths = [wide, across.contentLayoutGuide.widthAnchor.constraint(greaterThanOrEqualTo: across.frameLayoutGuide.widthAnchor)]
        }
        NSLayoutConstraint.activate(widths)
        across.isScrollEnabled = !wraps
    }

     
     
    private func runs(ofLine line: Int, _ text: NSString) -> ConfigurationSourceLineRuns {
        if let known = measuredRuns[line] { return known }
        let runs = ConfigurationSourceLineRuns.measure(text, font: textFont)
        if measuredRuns.count >= Self.runsKept { measuredRuns.removeAll(keepingCapacity: true) }
        measuredRuns[line] = runs
        if let contentWidth, textStart + runs.width + 24 > contentWidth.constant {
            contentWidth.constant = ceil(textStart + runs.width + 24)
        }
        return runs
    }

     
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === across else { return }
        let offset = acrossOffset
        for case let cell as ConfigurationSourceLineCell in table.visibleCells {
            cell.scrollAcross(to: offset)
        }
    }

     

    private func open() {
        let url = url
        do {
            let text = try ConfigurationSourceText(contentsOf: url)


            source = text
            model?.summary = size(text.byteCount) + " · " + copy("Counting lines…")
            indexTask = Task { [weak self] in
                let built = await Task.detached(priority: .userInitiated) { try? text.buildIndex() }.value
                guard let self, !Task.isCancelled else { return }
                guard let built else { self.showFailure(); return }


                self.index = built
                self.model?.summary = self.size(text.byteCount) + " · "
                    + ClashCopy.string(for: .format("%@ lines", [self.number(built.lineCount)]), locale: self.locale)
                self.model?.outline = self.outlineEntries(built)
                self.applyWidth()
                self.table.reloadData()
            }
        } catch {
            showFailure()
        }
    }

    private func showFailure() {
        failure.isHidden = false
        across.isHidden = true
        model?.summary = ""
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { index?.lineCount ?? 0 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ConfigurationSourceLineCell.identifier, for: indexPath)
        guard let cell = cell as? ConfigurationSourceLineCell, let source, let index else { return cell }
        let line = source.line(indexPath.row, in: index)
        let drawn = attributed(line, row: indexPath.row)
        cell.show(number: String(indexPath.row + 1), text: drawn,
                  textFont: textFont, gutterFont: gutterFont, gutterWidth: gutterWidth, wraps: wraps,
                  runs: wraps ? nil : runs(ofLine: indexPath.row, drawn.string as NSString), offset: acrossOffset)
        return cell
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath,
                   point: CGPoint) -> UIContextMenuConfiguration? {
        guard let source, let index else { return nil }
        let row = indexPath.row
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            return UIMenu(children: [
                UIAction(title: self.copy("Copy Line"), image: UIImage(systemName: ClashSymbol.docOnDoc.rawValue)) { _ in
                    UIPasteboard.general.string = source.line(row, in: index)
                },
            ])
        }
    }

     
    private func attributed(_ line: String, row: Int) -> NSAttributedString {
         
         
        let text = NSMutableAttributedString(string: line, attributes: [.foregroundColor: UIColor.label, .font: textFont])
        for token in ConfigurationSourceHighlight.tokens(in: line) {
            text.addAttribute(.foregroundColor, value: ConfigurationSourcePalette.color(token.kind), range: token.range)
        }
        for found in matchesByLine[row] ?? [] {
            let range = matches[found].utf16Range(in: line)
            guard range.location != NSNotFound, range.upperBound <= text.length else { continue }
            if found == current {
                text.addAttributes([.backgroundColor: ConfigurationSourcePalette.currentMatch,
                                    .foregroundColor: UIColor.black], range: range)
            } else {
                text.addAttribute(.backgroundColor, value: ConfigurationSourcePalette.match, range: range)
            }
        }
        return text
    }

     

     
     
    private func outlineEntries(_ index: ConfigurationSourceIndex) -> [ConfigurationSourceViewerModel.Entry] {
        var entries = [ConfigurationSourceViewerModel.Entry(id: 0, title: copy("Start of File"), detail: lineWord(0), line: 0)]
        for section in index.sections {
            var detail = lineWord(section.line)
            if section.items > 0 { detail += " · " + itemsWord(section) }
            entries.append(.init(id: entries.count, title: section.name, detail: detail, line: section.line))
        }
        return entries
    }

    private func itemsWord(_ section: ConfigurationSourceSection) -> String {
        let count = number(section.items)
        let format: String
        switch section.name {
        case "proxies": format = "%@ nodes"
        case "proxy-groups": format = "%@ groups"
        case "rules", "sub-rules": format = "%@ rules"
        default: format = "%@ items"
        }
        return ClashCopy.string(for: .format(format, [count]), locale: locale)
    }

    private func lineWord(_ line: Int) -> String {
        ClashCopy.string(for: .format("Line %@", [number(line + 1)]), locale: locale)
    }

    func askForLine() {
        guard let index else { return }
        let alert = UIAlertController(
            title: copy("Go to Line"),
            message: ClashCopy.string(for: .format("%@ lines in all", [number(index.lineCount)]), locale: locale),
            preferredStyle: .alert)
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.placeholder = "1 – \(index.lineCount)"
            field.accessibilityIdentifier = "configuration.source-viewer.go-to-line.field"
        }
        alert.addAction(UIAlertAction(title: copy("Cancel"), style: .cancel))
        let go = UIAlertAction(title: copy("Go"), style: .default) { [weak self, weak alert] _ in
            guard let typed = alert?.textFields?.first?.text, let line = Int(typed.filter(\.isNumber)) else { return }
            self?.show(line: min(max(line, 1), index.lineCount) - 1, match: nil)
        }
        alert.addAction(go)
        alert.preferredAction = go
        present(alert, animated: true)
    }

    func show(line: Int, match: ConfigurationSourceMatch?) {
        guard let index, line >= 0, line < index.lineCount else { return }
        table.scrollToRow(at: IndexPath(row: line, section: 0), at: match == nil ? .top : .middle, animated: false)
        guard !wraps else { return }
        var offset: CGFloat = 0
        if let match, let source {
             
             
             
             
             
            let text = source.line(line, in: index) as NSString
            let range = match.utf16Range(in: text as String)
            if range.location != NSNotFound, NSMaxRange(range) <= text.length {
                let span = runs(ofLine: line, text).span(of: range, in: text)
                 
                 
                 
                let insets = across.adjustedContentInset
                let visible = across.bounds.width - insets.left - insets.right - textStart
                let now = acrossOffset
                if span.upperBound <= visible - 24 {
                    offset = 0
                } else if span.lowerBound < now || span.upperBound > now + visible - 24 {
                    offset = span.lowerBound - visible / 3
                } else {
                    offset = now
                }
            }
        }
         
         
         
        across.layoutIfNeeded()
        let insets = across.adjustedContentInset
        offset = min(max(0, offset), max(0, across.contentSize.width + insets.left + insets.right - across.bounds.width))
        if offset != acrossOffset {
            across.setContentOffset(
                CGPoint(x: offset - across.adjustedContentInset.left, y: across.contentOffset.y), animated: false)
        }
    }

     

    func openFind() {
        guard index != nil else { return }
        findBar.isHidden = false
        model?.finding = true
        findBar.field.becomeFirstResponder()
        view.setNeedsLayout()
    }

    private func closeFind() {
        searchTask?.cancel()
        searchGeneration += 1
        pendingQuery?.cancel()
        searching = false
        findBar.field.text = nil
        findBar.field.resignFirstResponder()
        findBar.isHidden = true
        model?.finding = false
        let touched = Set(matchesByLine.keys)
        matches = []
        matchesByLine = [:]
        current = nil
        reload(lines: touched)
        view.setNeedsLayout()
    }

    @objc private func queryChanged() {
        pendingQuery?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.search(self?.findBar.field.text ?? "") }
        pendingQuery = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        step(1)
        return false
    }

    private func search(_ query: String) {
        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        let touched = Set(matchesByLine.keys)
        matches = []
        matchesByLine = [:]
        current = nil
        reload(lines: touched)
        guard let source, let index, !query.isEmpty else {
            searching = false
            updateCounter()
            return
        }
        searching = true
        updateCounter()


        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try source.search(query, in: index, batchSize: 256) { batch in
                    DispatchQueue.main.async { self?.receive(batch, generation: generation) }
                }
            } catch {}
            DispatchQueue.main.async { self?.finish(generation: generation) }
        }
    }

    private func receive(_ batch: [ConfigurationSourceMatch], generation: Int) {
        guard generation == searchGeneration else { return }
        var touched = Set<Int>()
        for match in batch {
            matchesByLine[match.line, default: []].append(matches.count)
            matches.append(match)
            touched.insert(match.line)
        }
        if current == nil, let first = matches.first {


            current = 0
            show(line: first.line, match: first)
            touched.insert(first.line)
        }
        reload(lines: touched)
        updateCounter()
    }

    private func finish(generation: Int) {
        guard generation == searchGeneration else { return }


        searching = false
        updateCounter()
    }

    private func step(_ direction: Int) {
        guard !matches.isEmpty else { return }
        let previous = current.map { matches[$0].line }
        let next = ((current ?? -1) + direction + matches.count) % matches.count
        current = next
        let match = matches[next]
        show(line: match.line, match: match)
        reload(lines: Set([previous, match.line].compactMap { $0 }))
        updateCounter()
    }

    private func reload(lines: Set<Int>) {
        let visible = Set(table.indexPathsForVisibleRows?.map(\.row) ?? [])
        let rows = lines.intersection(visible).map { IndexPath(row: $0, section: 0) }
        guard !rows.isEmpty else { return }
        UIView.performWithoutAnimation { table.reloadRows(at: rows, with: .none) }
    }

    private func updateCounter() {
        let count: String
        if matches.isEmpty {
            count = searching ? copy("Searching…") : ((findBar.field.text ?? "").isEmpty ? "" : copy("No Results"))
        } else {
            count = number((current ?? 0) + 1) + " / " + number(matches.count) + (searching ? "+" : "")
        }
        findBar.show(count: count, stillSearching: searching && !matches.isEmpty)
    }

     

    private func copy(_ key: String) -> String { ClashCopy.string(key, locale: locale) }

    private func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

     
    private func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(Int64(bytes))
    }
}

 
 
 
final class ConfigurationSourceFindBar: UIView {
    let field = UISearchTextField()
    let previousButton = UIButton(type: .system)
    let nextButton = UIButton(type: .system)
    let done = UIButton(type: .system)
    private let count = UILabel()
    private let note = UILabel()
    private let row = UIStackView()
    private var doneTitle = "Done"
    private lazy var fieldFullWidth = field.widthAnchor.constraint(equalTo: row.widthAnchor)

    override init(frame: CGRect) {
        super.init(frame: frame)
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)
        let rule = UIView()
        rule.backgroundColor = .separator
        rule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rule)

        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.returnKeyType = .next
        field.accessibilityIdentifier = "configuration.source-viewer.find.field"
        count.font = .preferredFont(forTextStyle: .footnote)
        count.adjustsFontForContentSizeCategory = true
        count.textColor = .secondaryLabel
        count.setContentHuggingPriority(.required, for: .horizontal)
        count.setContentCompressionResistancePriority(.required, for: .horizontal)
        count.accessibilityIdentifier = "configuration.source-viewer.find.count"
        previousButton.setImage(UIImage(systemName: ClashSymbol.chevronUp.rawValue), for: .normal)
        nextButton.setImage(UIImage(systemName: ClashSymbol.chevronDown.rawValue), for: .normal)
        previousButton.accessibilityIdentifier = "configuration.source-viewer.find.previous"
        nextButton.accessibilityIdentifier = "configuration.source-viewer.find.next"
        done.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        done.titleLabel?.adjustsFontForContentSizeCategory = true
        done.accessibilityIdentifier = "configuration.source-viewer.find.done"
        for button in [previousButton, nextButton, done] {
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        }
        note.font = .preferredFont(forTextStyle: .caption1)
        note.adjustsFontForContentSizeCategory = true
        note.textColor = .secondaryLabel
        note.numberOfLines = 0
        note.isHidden = true

        let controls = UIStackView(arrangedSubviews: [count, previousButton, nextButton, done])
        controls.alignment = .center
        controls.spacing = 6
        row.addArrangedSubview(field)
        row.addArrangedSubview(controls)
        row.spacing = 6
        arrange()
        let column = UIStackView(arrangedSubviews: [row, note])
        column.axis = .vertical
        column.spacing = 4
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
         
        addInteraction(UILargeContentViewerInteraction())
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            rule.topAnchor.constraint(equalTo: topAnchor),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            column.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            column.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        guard previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else { return }
        arrange()
    }

     
     
     
    private func arrange() {
        let stacked = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        row.axis = stacked ? .vertical : .horizontal
        row.alignment = stacked ? .trailing : .center
        field.setContentCompressionResistancePriority(stacked ? .defaultHigh : .defaultLow, for: .horizontal)
        fieldFullWidth.isActive = stacked
         
         
         
        done.setTitle(stacked ? nil : doneTitle, for: .normal)
        done.setImage(stacked ? UIImage(systemName: ClashSymbol.xmarkCircleFill.rawValue) : nil, for: .normal)
        done.accessibilityLabel = doneTitle
        done.showsLargeContentViewer = stacked
        done.largeContentTitle = doneTitle
    }

    func configure(locale: Locale) {
        field.placeholder = ClashCopy.string("Find in Source", locale: locale)
        previousButton.accessibilityLabel = ClashCopy.string("Previous Match", locale: locale)
        nextButton.accessibilityLabel = ClashCopy.string("Next Match", locale: locale)
        doneTitle = ClashCopy.string("Done", locale: locale)
        arrange()
        note.text = ClashCopy.string("Still searching. What's found so far is ready.", locale: locale)
    }

    func show(count text: String, stillSearching: Bool) {
        count.text = text
        if note.isHidden == stillSearching { note.isHidden = !stillSearching }
    }
}

 
 
 
 
 
 
final class ConfigurationSourceTable: UITableView {
    private var shownRows: [Int] { (indexPathsForVisibleRows ?? []).map(\.row) }

    override func accessibilityElementCount() -> Int { shownRows.count }

    override func accessibilityElement(at index: Int) -> Any? {
        let rows = shownRows
        return rows.indices.contains(index) ? super.accessibilityElement(at: rows[index]) : nil
    }

    override func index(ofAccessibilityElement element: Any) -> Int {
        let row = super.index(ofAccessibilityElement: element)
        return shownRows.firstIndex(of: row) ?? NSNotFound
    }
}

final class ConfigurationSourceLineCell: UITableViewCell {
    static let identifier = "configuration.source-viewer.line"
    private let number = UILabel()
     
     
    private let text = UILabel()
     
    private let unwrapped = ConfigurationSourceLineWindow()
    private var gutter: NSLayoutConstraint?
     
     
    private var lineHeight: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        number.textAlignment = .right
        number.textColor = .tertiaryLabel
        number.translatesAutoresizingMaskIntoConstraints = false
        number.isAccessibilityElement = false
        text.translatesAutoresizingMaskIntoConstraints = false
        unwrapped.translatesAutoresizingMaskIntoConstraints = false
        unwrapped.isHidden = true
        contentView.addSubview(number)
        contentView.addSubview(text)
        contentView.addSubview(unwrapped)
        let gutter = number.widthAnchor.constraint(equalToConstant: 40)
        self.gutter = gutter
        let lineHeight = text.heightAnchor.constraint(greaterThanOrEqualToConstant: 17)
        self.lineHeight = lineHeight
        NSLayoutConstraint.activate([
            gutter,
            lineHeight,
            number.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            number.firstBaselineAnchor.constraint(equalTo: text.firstBaselineAnchor),
            text.leadingAnchor.constraint(equalTo: number.trailingAnchor, constant: 10),
            text.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12),
            text.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 1),
            text.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -1),
             
             
            unwrapped.leadingAnchor.constraint(equalTo: text.leadingAnchor),
            unwrapped.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            unwrapped.topAnchor.constraint(equalTo: text.topAnchor),
            unwrapped.bottomAnchor.constraint(equalTo: text.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

     
     
    func show(number line: String, text attributed: NSAttributedString, textFont: UIFont, gutterFont: UIFont,
              gutterWidth: CGFloat, wraps: Bool, runs: ConfigurationSourceLineRuns? = nil, offset: CGFloat = 0) {
        number.text = line
        number.font = gutterFont
        gutter?.constant = gutterWidth
        text.font = textFont
        lineHeight?.constant = ceil(textFont.lineHeight)
        text.numberOfLines = wraps ? 0 : 1
        text.lineBreakMode = wraps ? .byCharWrapping : .byClipping
        if let runs, !wraps {
            text.attributedText = NSAttributedString(string: " ", attributes: [.font: textFont])
            text.isHidden = true
            unwrapped.isHidden = false
            unwrapped.show(attributed, runs: runs, offset: offset)
        } else {
            text.attributedText = attributed
            text.isHidden = false
            unwrapped.isHidden = true
            unwrapped.show(NSAttributedString(), runs: .none, offset: 0)
        }
        accessibilityLabel = attributed.string
        accessibilityValue = line
    }

     
    func scrollAcross(to offset: CGFloat) {
        guard !unwrapped.isHidden else { return }
        unwrapped.scroll(to: offset)
    }
}

 
 
 
 
 
struct ConfigurationSourceLineRuns: Equatable {
    struct Run: Equatable {
         
        let range: NSRange
        let x: CGFloat
        let width: CGFloat
         
        let plain: Bool
    }

    static let none = ConfigurationSourceLineRuns(runs: [], advance: 0, font: nil)
     
     
     
    static let longestRun = 128

    let runs: [Run]
     
    let advance: CGFloat
    let font: UIFont?

    var width: CGFloat { runs.last.map { $0.x + $0.width } ?? 0 }

     
     
     
     
    static func measure(_ line: NSString, font: UIFont) -> ConfigurationSourceLineRuns {
        let advance = ("0" as NSString).size(withAttributes: [.font: font]).width
        let length = line.length
        var runs: [Run] = []
        runs.reserveCapacity(length / longestRun + 1)
        var units = [unichar](repeating: 0, count: longestRun + 8)
        var start = 0
        var x: CGFloat = 0
        while start < length {
            var end = min(start + longestRun, length)
            if end < length {
                let whole = line.rangeOfComposedCharacterSequence(at: end)
                end = whole.location > start ? whole.location : NSMaxRange(whole)
            }
            let range = NSRange(location: start, length: end - start)
            if units.count < range.length { units = [unichar](repeating: 0, count: range.length) }
            line.getCharacters(&units, range: range)
            var plain = true
            for offset in 0..<range.length where units[offset] < 0x20 || units[offset] > 0x7E {
                plain = false
                break
            }
            let width = plain
                ? CGFloat(range.length) * advance
                : line.substring(with: range).size(withAttributes: [.font: font]).width
            runs.append(Run(range: range, x: x, width: width, plain: plain))
            x += width
            start = end
        }
        return ConfigurationSourceLineRuns(runs: runs, advance: advance, font: font)
    }

     
    func indices(from lower: CGFloat, to upper: CGFloat) -> Range<Int> {
        var low = 0
        var high = runs.count
        while low < high {
            let middle = (low + high) / 2
            if runs[middle].x + runs[middle].width <= lower { low = middle + 1 } else { high = middle }
        }
        var end = low
        high = runs.count
        while end < high {
            let middle = (end + high) / 2
            if runs[middle].x < upper { end = middle + 1 } else { high = middle }
        }
        return low..<end
    }

     
    func span(of range: NSRange, in line: NSString) -> ClosedRange<CGFloat> {
        let start = x(at: range.location, in: line)
        return start...max(start, x(at: NSMaxRange(range), in: line))
    }

    private func x(at location: Int, in line: NSString) -> CGFloat {
        guard let font, !runs.isEmpty else { return 0 }
         
        var low = 0
        var high = runs.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if runs[middle].range.location <= location { low = middle } else { high = middle - 1 }
        }
        let run = runs[low]
        let into = min(max(0, location - run.range.location), run.range.length)
        if into == run.range.length { return run.x + run.width }
        if run.plain { return run.x + CGFloat(into) * advance }
        let before = NSRange(location: run.range.location, length: into)
        return run.x + line.substring(with: before).size(withAttributes: [.font: font]).width
    }
}

 
 
 
 
 
 
 
 
final class ConfigurationSourceLineWindow: UIView {
    private var line = NSAttributedString()
    private var runs = ConfigurationSourceLineRuns.none
    private var shown: [Int: UILabel] = [:]
    private var spare: [UILabel] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ line: NSAttributedString, runs: ConfigurationSourceLineRuns, offset: CGFloat) {
        self.line = line
        self.runs = runs
        for index in Array(shown.keys) { letGo(index) }
        bounds.origin.x = offset
        fill()
    }

    func scroll(to offset: CGFloat) {
        guard bounds.origin.x != offset else { return }
        bounds.origin.x = offset
        fill()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fill()
    }

    private func letGo(_ index: Int) {
        guard let label = shown.removeValue(forKey: index) else { return }
         
        label.attributedText = nil
        if spare.count < 4 {
            label.isHidden = true
            spare.append(label)
        } else {
            label.removeFromSuperview()
        }
    }

    private func fill() {
        guard !runs.runs.isEmpty, bounds.width > 0 else { return }
        let margin = max(bounds.width / 4, 120)
        let wanted = runs.indices(from: bounds.minX - margin, to: bounds.maxX + margin)
        for index in Array(shown.keys) where !wanted.contains(index) { letGo(index) }
        let scale = max(traitCollection.displayScale, 1)
        for index in wanted where shown[index] == nil {
            let run = runs.runs[index]
            let label: UILabel
            if let reused = spare.popLast() {
                label = reused
                label.isHidden = false
            } else {
                label = UILabel()
                label.numberOfLines = 1
                label.lineBreakMode = .byClipping
                label.isAccessibilityElement = false
                addSubview(label)
            }
            label.attributedText = line.attributedSubstring(from: run.range)
             
             
            label.frame = CGRect(x: (run.x * scale).rounded() / scale, y: 0,
                                 width: ceil(run.width) + 1, height: bounds.height)
            shown[index] = label
        }
        for label in shown.values where label.frame.height != bounds.height {
            label.frame.size.height = bounds.height
        }
    }
}

 
enum ConfigurationSourcePalette {
    static func color(_ kind: ConfigurationSourceHighlight.Kind) -> UIColor {
        switch kind {
        case .key: return key
        case .string: return string
        case .literal: return literal
        case .comment: return comment
        case .punctuation: return .secondaryLabel
        }
    }

    private static func pair(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) }
    }

    private static func rgb(_ value: UInt32) -> UIColor {
        UIColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    static let key = pair(light: 0x0B4F79, dark: 0x6BDFFF)
    static let string = pair(light: 0xC41A16, dark: 0xFC6A5D)
    static let literal = pair(light: 0x1C00CF, dark: 0xD0BF69)
    static let comment = pair(light: 0x5D6C79, dark: 0x7F8C98)
    static let match = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor.systemYellow.withAlphaComponent(0.30) : UIColor.systemYellow.withAlphaComponent(0.45) }
    static let currentMatch = UIColor.systemOrange
}
#endif
