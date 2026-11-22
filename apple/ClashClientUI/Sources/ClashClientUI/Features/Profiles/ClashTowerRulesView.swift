import SwiftUI
import ClashClientKit

 
 
 
 
 
enum ClashTowerRulesErrorText {
    static func describe(_ error: Error) -> String {
        let sentence = error.localizedDescription
        guard let library = error as? ConfigurationLibraryError, library == .invalidIdentifier,
              let note = ConfigurationLibraryDiagnostics.lastIdentifierNote else { return sentence }
        return sentence + " [" + note + "]"
    }
}

public struct ClashTowerRulesLibraryView: View {
    public let palette: ClashProductPalette
    public let library: ConfigurationLibrarySnapshot
    public let busy: Bool
    public let error: String?
    public let open: (String) -> Void
    public let refresh: (String) -> Void
    public let delete: (String) -> Void
    public let add: () -> Void
    public let close: () -> Void
    public let showsClose: Bool
     
     
    public let isCenterSection: Bool
    public var collections: [ConfigurationCollectionEntry] = []
    public var openCollection: (ConfigurationCollectionEntry) -> Void = { _ in }
    public let updateAll: (() -> Void)?
     
     
    public let quickAdd: (() -> AnyView)?
     
    public let addMenu: (() -> AnyView)?
     
     
    public let updateProgress: String?
    public let updateStatus: String?
     
     
     
    public var isUpdating = false
     
    public var updatingCollections: Set<ConfigurationCollection.ID> = []
     
    public var updateCollection: ((ConfigurationCollectionEntry) -> Void)?
     
     
    public var updateFailed = false
     
    public var dismissUpdate: (() -> Void)?
     
    public var refreshingSchemes: Set<String> = []
     
    public let rename: ((String, String) -> Void)?
     
     
     
    public var deleteSource: ((String) -> Void)?
     
     
    public var copyLink: ((String) -> Void)?
     
    public var refreshAll: (() async -> Void)?
     
     
     
    public var ruleSetsRow: (() -> AnyView)?
     
     
     
    public var deletionUndoable = false
    public func deletingWithUndo(_ undoable: Bool = true) -> Self { var copy = self; copy.deletionUndoable = undoable; return copy }
    @State private var deleting: ConfigurationRuleScheme?
    @State private var deletingSource: ConfigurationSourceRecord?
    @State private var renaming: ConfigurationRuleScheme?
    @State private var renameText = ""
    @Environment(\.locale) private var locale
    @Environment(\.clashFeedback) private var feedback
     
    @State private var runEntry: Int?
     
    @AppStorage("configuration.rules.expandedSources") private var expandedSourceIDs = ""

    public init(library: ConfigurationLibrarySnapshot, palette: ClashProductPalette, busy: Bool, error: String?,
        open: @escaping (String) -> Void, refresh: @escaping (String) -> Void,
        delete: @escaping (String) -> Void, add: @escaping () -> Void, close: @escaping () -> Void, showsClose: Bool,
        isCenterSection: Bool = false,
        collections: [ConfigurationCollectionEntry] = [], openCollection: @escaping (ConfigurationCollectionEntry) -> Void = { _ in },
        updateAll: (() -> Void)? = nil, updateProgress: String? = nil, updateStatus: String? = nil,
        quickAdd: (() -> AnyView)? = nil, addMenu: (() -> AnyView)? = nil,
        rename: ((String, String) -> Void)? = nil,
        isUpdating: Bool = false, updatingCollections: Set<ConfigurationCollection.ID> = [],
        updateCollection: ((ConfigurationCollectionEntry) -> Void)? = nil,
        updateFailed: Bool = false, dismissUpdate: (() -> Void)? = nil, refreshingSchemes: Set<String> = [],
        deleteSource: ((String) -> Void)? = nil, copyLink: ((String) -> Void)? = nil,
        refreshAll: (() async -> Void)? = nil, ruleSetsRow: (() -> AnyView)? = nil) {
        self.ruleSetsRow = ruleSetsRow
        self.updateFailed = updateFailed; self.dismissUpdate = dismissUpdate; self.refreshingSchemes = refreshingSchemes
        self.deleteSource = deleteSource; self.copyLink = copyLink; self.refreshAll = refreshAll
        self.updateAll = updateAll; self.updateProgress = updateProgress; self.updateStatus = updateStatus
        self.rename = rename
        self.quickAdd = quickAdd
        self.collections = collections; self.openCollection = openCollection
        self.palette = palette
        self.library = library; self.busy = busy; self.error = error
        self.open = open; self.refresh = refresh; self.delete = delete; self.add = add
        self.close = close; self.showsClose = showsClose; self.isCenterSection = isCenterSection
        self.addMenu = addMenu
        self.isUpdating = isUpdating; self.updatingCollections = updatingCollections
        self.updateCollection = updateCollection
    }
    private var schemes: [ConfigurationRuleScheme] {
        library.visibleRuleSchemes
    }
     
    private static let updateAllRow = "configuration.library.rules.update-all.row"
    private func record(_ scheme: ConfigurationRuleScheme) -> ConfigurationSourceRecord? {
         
         
        if ConfigurationBuiltins.isNative(scheme.id) {
            return ConfigurationBuiltins.records.first { $0.id == scheme.sourceID }
        }
        return library.sources.first { $0.id == scheme.sourceID } ?? ConfigurationBuiltins.records.first { $0.id == scheme.sourceID }
    }
    private func displayLabel(_ scheme: ConfigurationRuleScheme) -> String { Self.displayLabel(scheme, locale: locale) }
     
    public static func displayLabel(_ scheme: ConfigurationRuleScheme, locale: Locale) -> String {
        let id = scheme.id
        if id == ConfigurationBuiltins.basicRuleID { return ClashCopy.string("Default Configuration", locale: locale) }
        if id == ConfigurationBuiltins.lazyRuleID { return ClashCopy.string("Lazy Configuration", locale: locale) }
        if scheme.baseSchemeID.map(ConfigurationBuiltins.isNative) == true {
            return ClashCopy.format("%@ (Modified)", locale: locale, scheme.labelAsRead(locale: locale))
        }
        return scheme.label
    }
    private func bundled(_ scheme: ConfigurationRuleScheme) -> Bool { scheme.kind == .builtin }
     
    static func link(_ record: ConfigurationSourceRecord?) -> String? {
        if case .subscription(let link)? = record?.origin { return link }
        return nil
    }
     
     
     
    public static func canRename(_ scheme: ConfigurationRuleScheme) -> Bool {
         
        (scheme.kind == .custom || scheme.kind == .imported) && scheme.isRetainedSnapshot != true && scheme.ownViewBaseID == nil
    }
     
     
    private struct RunWords: Equatable {
        let progress: String?
        let status: String?
        let failed: Bool
        let hasReasons: Bool
    }

     
    private func sayRun(_ scroller: ScrollViewProxy) {
        guard let feedback else { return }
        let operation = "rules.update-all"
        if let progress = updateProgress {
            let running = ClashFeedbackPresentation.loading(title: .verbatim(progress),
                                                            accessibilityIdentifier: "feedback.rules.update")
            if let runEntry, feedback.update(runEntry, to: running) { return }
            runEntry = feedback.show(running, operation: operation)
            return
        }
        guard let status = updateStatus else {
            runEntry = nil
            return
        }
        var detail: (@MainActor () -> Void)?
        if updateAll != nil, updateFailed, error != nil {
            detail = { withAnimation { scroller.scrollTo(Self.updateAllRow, anchor: .top) } }
        }
        let result: ClashFeedbackPresentation = updateFailed
            ? .warning(title: .verbatim(status), action: detail == nil ? nil : .details, isBatchSummary: true,
                       accessibilityIdentifier: "feedback.rules.update")
            : .success(title: .verbatim(status), isBatchSummary: true, accessibilityIdentifier: "feedback.rules.update")
        let read = dismissUpdate
        if let runEntry, feedback.update(runEntry, to: result, perform: detail, onDismiss: read) { return }
         
         
        if feedback.state.current?.presentation == result { return }
        runEntry = feedback.show(result, operation: operation, perform: detail, onDismiss: read)
    }

    public var body: some View {
         
         
         
        let schemes = self.schemes
        return ScrollViewReader { scroller in
            ClashConfigurationLibraryList(palette: palette, accessibilityIdentifier: "configuration.library.rules.content") {
                if updateAll == nil, let error { Text(verbatim: error).foregroundStyle(.orange) }
                ForEach(ClashConfigurationRuleLibrarySection.allCases, id: \.self) { group in
                    let items = schemes.filter { group.contains($0, library: library) }
                    let entries = Self.sectionEntries(group, collections: collections, schemes: schemes, library: library)
                    if !items.isEmpty || !entries.isEmpty {
                        section(group.title, items: items, entries: entries).id("\(group)-\(refusedRound)")
                    }
                }
                if let ruleSetsRow {
                    Section { ruleSetsRow() }
                }
                if let updateAll {
                    Section {
                         
                        ClashConfigurationUpdateButton(title: "Update All", isUpdating: isUpdating, disabled: isUpdating, action: updateAll)
                            .accessibilityIdentifier("configuration.library.rules.update-all")
                            .id(Self.updateAllRow)
                    } footer: {
                         
                         
                         
                         
                        if let error {
                            ClashConfigurationUpdateStatus(progress: nil, status: nil, error: error)
                        }
                    }
                }
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                if let quickAdd { quickAdd() } else {
                    ClashConfigurationLibraryAddCard(kind: .rules, palette: palette, nativeList: true,
                        disabled: busy, action: add)
                        .accessibilityIdentifier("configuration.library.rules.add-card")
                }
                Section {} footer: {
                    Text(clash: .copy("This is a library. A configuration uses a rule scheme from here once that configuration is set to use it."))
                        .accessibilityIdentifier("configuration.library.rules.what-this-is")
                }
            }
             
             
            .modifier(ClashLibraryPullToUpdate(action: updateAll == nil ? nil : (refreshAll ?? updateAll.map { run in { run() } })))
             
             
             
            .allowsHitTesting(!busy)
             
             
             
             
             
             
             
             
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if feedback == nil, updateProgress != nil || updateStatus != nil {
                    ClashLibraryUpdateBar(progress: updateProgress, status: updateStatus, failed: updateFailed,
                        details: updateAll != nil && updateFailed && error != nil
                            ? { withAnimation { scroller.scrollTo(Self.updateAllRow, anchor: .top) } } : nil,
                        dismiss: dismissUpdate)
                }
            }
             
             
             
             
             
            .task(id: RunWords(progress: updateProgress, status: updateStatus, failed: updateFailed,
                               hasReasons: error != nil)) {
                 
                guard !Task.isCancelled else { return }
                sayRun(scroller)
            }
        }
        .overlay {
            if busy && schemes.isEmpty { ProgressView().allowsHitTesting(false) }
        }
        .modifier(ClashLibraryTabTitle(isCenterSection: isCenterSection, standalone: pageTitle ?? .copy("Manage Rule Schemes")))
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) { if showsClose { ClashSheetCloseButton(dismiss: close) } }
            ToolbarItem(placement: .primaryAction) {
                 
                if let addMenu { addMenu() }
                else {
                    ControlGroup {
                        Button(action: add) {
                            Image(systemName: ClashSymbol.plusCircle.rawValue).clashToolbarGlyph()
                        }
                        .disabled(busy)
                        .accessibilityLabel(ClashCopy.key(ClashConfigurationAddition.rules.entryTitle))
                        .accessibilityIdentifier("configuration.library.rules.add")
                    }.clashReaderControlGroupStyle()
                }
            }
        }
        .clashRegistersDeparture(isDirty: false, isBusy: busy, save: { $0(false) }, discard: {})
        .clashDeleteConfirmation(presenting: $deleting, name: displayLabel,
            actionTitle: .copy("Delete Rule Scheme"),
            message: { _ in .copy("Saved profiles keep their current rules and stop following this scheme.") },
            identifier: "configuration.rules.library.delete.confirm") { deleting in delete(deleting.id) }
         
         
        .clashDeleteConfirmation(presenting: $deletingSource, name: \.label,
            actionTitle: .copy("Delete Source"),
            message: { source in source.suppliesNodes
                ? .copy("Configurations that use this source lose its nodes.")
                : .copy("Saved profiles keep their current content and stop following this source.") },
            identifier: "configuration.rules.library.source.delete.confirm") { source in deleteSource?(source.id) }
         
         
         
        .clashTextFieldAlert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
                             presenting: renaming, text: $renameText,
                             field: ClashTextFieldAlertField(placeholder: "Name",
                                                             identifier: "configuration.rules.library.rename.name")) { renaming, typed in
            if let name = renaming.newName(typed: typed, locale: locale) { rename?(renaming.id, name) }
        }
    }
     
     
     
    public var pageTitle: ClashDisplayText?
     
     
    public var usage: ((String) -> ClashDisplayText?)?
    public func titled(_ title: ClashDisplayText?, usage: ((String) -> ClashDisplayText?)?) -> Self {
        var copy = self; copy.pageTitle = title; copy.usage = usage; return copy
    }
     
     
     
     
    public var refusedRound = 0
    public func refused(_ round: Int) -> Self {
        var copy = self; copy.refusedRound = round; return copy
    }

     
     
     
     
     
     
    static func sectionEntries(_ group: ClashConfigurationRuleLibrarySection, collections: [ConfigurationCollectionEntry],
                               schemes: [ConfigurationRuleScheme], library: ConfigurationLibrarySnapshot) -> [ConfigurationCollectionEntry] {
        collections.filter { entry in
            guard entry.id.kind == .rules, entry.source.isListedInLibrary else { return false }
            if let owner = schemes.first(where: { $0.sourceID == entry.source.id && $0.collectionKey == nil }) {
                return group.contains(owner, library: library)
            }
            return !entry.source.suppliesNodes && group.contains(entry.source)
        }
    }

     
     
     
     
     
     
     
     
    static func outline(items: [ConfigurationRuleScheme], entries: [ConfigurationCollectionEntry],
                        library: ConfigurationLibrarySnapshot) -> (roots: [ConfigurationRuleScheme], collectionSources: [ConfigurationSourceRecord]) {
         
        let projected = { (scheme: ConfigurationRuleScheme) in
            entries.contains { $0.source.id == scheme.sourceID && $0.collection.name == scheme.collectionKey }
        }
        var roots = items.filter { !projected($0) }
        var rootSources = Set(roots.map(\.sourceID))
        for root in roots {
            if let base = root.baseSchemeID, !ConfigurationBuiltins.isNative(base),
               let source = library.rules.first(where: { $0.id == base })?.sourceID {
                rootSources.insert(source)
            }
        }
         
         
         
         
         
        let collectionSources = library.availableSources.filter { source in
            !source.suppliesNodes && !rootSources.contains(source.id) && entries.contains { $0.source.id == source.id }
        }
         
         
        let parents = rootSources.union(collectionSources.map(\.id))
        roots = items.filter { !projected($0) || !parents.contains($0.sourceID) }
        return (roots, collectionSources)
    }

    @ViewBuilder
    private func section(_ title: String, items: [ConfigurationRuleScheme], entries: [ConfigurationCollectionEntry]) -> some View {
        let (roots, collectionSources) = Self.outline(items: items, entries: entries, library: library)
        ClashConfigurationLibraryCard(title: .copy(title), count: roots.count + collectionSources.count, palette: palette, nativeList: true, systemRowInsets: true) {
            ForEach(roots) { scheme in
                 
                 
                let children = scheme.collectionKey == nil ? entries.filter { $0.source.id == scheme.sourceID } : []
                 
                 
                 
                if children.isEmpty {
                    schemeRow(scheme, showsInfo: true)
                } else {
                    DisclosureGroup(isExpanded: expansion(scheme.id)) {
                        collectionRows(children)
                    } label: {
                        schemeRow(scheme, showsInfo: false)
                            .clashOutlineToggle(isExpanded: expansion(scheme.id))
                    }
                }
            }
             
            ForEach(collectionSources) { source in
                let children = entries.filter { $0.source.id == source.id }
                DisclosureGroup(isExpanded: expansion(source.id)) {
                    collectionRows(children)
                } label: {
                    sourceRow(source, count: children.count)
                }
                .accessibilityIdentifier("configuration.rules.collections.\(source.id)")
            }
        }
    }

    private func schemeRow(_ scheme: ConfigurationRuleScheme, showsInfo: Bool) -> some View {
         
         
        let refreshing = refreshingSchemes.contains(scheme.id)
        return Button { open(scheme.id) } label: {
            HStack(spacing: 8) {
                ClashConfigurationLibraryRow(title: displayLabel(scheme),
                    count: ClashConfigurationSourceCopy.ruleSummary(record(scheme), locale: locale), showsInfo: showsInfo,
                    inUse: usage?(scheme.id))
                if refreshing { ProgressView().controlSize(.small) }
            }
        }.buttonStyle(.plain)
            .contextMenu {
                 
                 
                 
                 
                 
                 
                if case .subscription = record(scheme)?.origin {
                    Button { refresh(scheme.id) } label: {
                        Label { Text("Update") } icon: { Image(systemName: ClashSymbol.arrowClockwise.rawValue) }
                    }
                    .disabled(refreshing)
                    .accessibilityIdentifier("configuration.rules.library.update")
                }
                if let link = Self.link(record(scheme)), let copyLink {
                    Button { copyLink(link) } label: {
                        Label { Text("Copy Link") } icon: { Image(systemName: ClashSymbol.link.rawValue) }
                    }
                    .accessibilityIdentifier("configuration.rules.library.copy-link")
                }
                if rename != nil, Self.canRename(scheme) {
                    Button { renameText = scheme.labelAsRead(locale: locale); renaming = scheme } label: {
                        Label("Rename…", systemImage: ClashSymbol.pencil.rawValue)
                    }
                    .accessibilityIdentifier("configuration.rules.library.rename")
                }
                Button { open(scheme.id) } label: {
                    Label { Text("View Details") } icon: { Image(systemName: ClashSymbol.infoCircle.rawValue) }
                }
                if !bundled(scheme) {
                    Button(role: .destructive) { if deletionUndoable { delete(scheme.id) } else { deleting = scheme } } label: {
                        Label { Text("Delete") } icon: { Image(systemName: ClashSymbol.trash.rawValue) }
                    }
                }
            }
            .clashSwipeToDelete(identifier: "configuration.rules.library.delete",
                               bundled(scheme) ? nil : { if deletionUndoable { delete(scheme.id) } else { deleting = scheme } })
    }

     
     
     
    private func sourceRow(_ source: ConfigurationSourceRecord, count: Int) -> some View {
        let deletable = deleteSource != nil && Self.canDeleteSource(source)
        return ClashConfigurationLibraryRow(title: source.displayLabel(locale: locale),
            count: .format(count == 1 ? "%@ collection" : "%@ collections", [String(count)]),
            showsInfo: false)
            .contextMenu {
                 
                 
                if let link = Self.link(source), let copyLink {
                    Button { copyLink(link) } label: {
                        Label { Text("Copy Link") } icon: { Image(systemName: ClashSymbol.link.rawValue) }
                    }
                    .accessibilityIdentifier("configuration.rules.library.source.copy-link")
                }
                if deletable {
                    Button(role: .destructive) { if deletionUndoable { deleteSource?(source.id) } else { deletingSource = source } } label: {
                        Label { Text("Delete") } icon: { Image(systemName: ClashSymbol.trash.rawValue) }
                    }
                }
            }
            .clashSwipeToDelete(identifier: "configuration.rules.library.source.delete",
                               deletable ? { if deletionUndoable { deleteSource?(source.id) } else { deletingSource = source } } : nil)
    }

     
     
     
     
    public static func canDeleteSource(_ source: ConfigurationSourceRecord) -> Bool {
        if case .bundled = source.origin { return false }
        return source.isRetainedSnapshot != true && !source.suppliesNodes
    }

    private func collectionRows(_ entries: [ConfigurationCollectionEntry]) -> some View {
        ForEach(entries) { entry in
            let updating = updatingCollections.contains(entry.id)
            Button { openCollection(entry) } label: {
                HStack(spacing: 8) {
                    ClashConfigurationLibraryRow(title: entry.collection.name,
                        count: ClashConfigurationCollectionCopy.summary(entry))
                    if updating { ProgressView().controlSize(.small) }
                }
            }.buttonStyle(.plain)
                .accessibilityIdentifier("configuration.collection.\(entry.source.id).\(entry.id.kind.rawValue).\(entry.collection.name)")
                .modifier(ClashRuleSetRowUpdate(entry: entry, enabled: !isUpdating, update: updateCollection))
        }
    }

     
    private func expansion(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expandedSourceIDs.split(separator: "\n").contains { $0 == id } },
            set: { open in
                 
                let live = Set(library.rules.map(\.id) + library.sources.map(\.id)
                    + ConfigurationBuiltins.schemes.map(\.id))
                var ids = expandedSourceIDs.split(separator: "\n").map(String.init)
                    .filter { $0 != id && live.contains($0) }
                if open { ids.append(id) }
                expandedSourceIDs = ids.joined(separator: "\n")
            }
        )
    }

}

 
 
 
 
public struct ClashTowerRuleEditing: Equatable, Sendable {
    public let raw: String
    public let isEnabled: Bool
    public let note: String
    public init(raw: String, isEnabled: Bool, note: String) { self.raw = raw; self.isEnabled = isEnabled; self.note = note }
}

 
 
 
 
 
 
 
 
 
 
 
public struct ClashTowerGroupPageRequest {
    public let group: ConfigurationRuleDraft.Group
    public let index: Int
    public let all: [ConfigurationRuleDraft.Group]
    public let nodeSections: [ConfigurationRuleTargetCandidates.Section]
    public let save: (OrderedJSON) async throws -> Void
     
     
     
    public var mode: ClashTowerGroupPageMode = .editing
     
     
    public var deletion: ClashTowerGroupPageDeletion? = nil
     
     
    public var close: (() -> Void)? = nil
     
     
     
     
    public var targetSearch: ClashRuleTargetSearchHook? = nil
    public init(group: ConfigurationRuleDraft.Group, index: Int, all: [ConfigurationRuleDraft.Group],
                nodeSections: [ConfigurationRuleTargetCandidates.Section], save: @escaping (OrderedJSON) async throws -> Void) {
        self.group = group; self.index = index; self.all = all; self.nodeSections = nodeSections; self.save = save
    }
}

 
 
public enum ClashTowerGroupPageMode {
     
    case editing
     
     
     
    case adding(cancel: () -> Void)
     
     
    case reading

    public var isAdding: Bool { if case .adding = self { return true }; return false }
    public var isReading: Bool { if case .reading = self { return true }; return false }
}

 
 
 
public struct ClashTowerGroupPageDeletion {
     
    public let users: ConfigurationRuleGroupUsers
    public let delete: () -> Void
     
     
    public var dismissesPage = true
    public init(users: ConfigurationRuleGroupUsers, delete: @escaping () -> Void) {
        self.users = users; self.delete = delete
    }
}

 
 
 
 
 
public struct ClashTowerGroupDeletionReport {
    public let deletion: ConfigurationRuleGroupDeletion
    public let restore: @MainActor () async throws -> Void
    public init(deletion: ConfigurationRuleGroupDeletion, restore: @escaping @MainActor () async throws -> Void) {
        self.deletion = deletion; self.restore = restore
    }
}

 
 
 
 
 
public struct ClashTowerGroupUndoUnavailable: ClashAuthoredError {
    public init() {}
    public var displayText: ClashDisplayText {
        .copy("The rule scheme’s page is closed and the deletion is saved. To change it back, open the scheme in the rule library.")
    }
}

 
 
 
 
public enum ClashTowerGroupDeletionCopy {
     
     
     
    public static func refusal(_ users: ConfigurationRuleGroupUsers, group: String, locale: Locale) -> String? {
        if !users.groups.isEmpty {
             
            guard users.groups.count > shownGroups else {
                return ClashCopy.format("Can’t delete: it’s in %@. Remove it from those groups first.", locale: locale,
                                        quoted(users.groups, locale: locale, closing: true))
            }
            return ClashCopy.format("Can’t delete: it’s in %@ and more, %@ policy groups in all. Remove it from those groups first.",
                                    locale: locale, quoted(Array(users.groups.prefix(shownGroups)), locale: locale, closing: false),
                                    ClashCopy.count(users.groups.count, locale: locale))
        }
        if users.finalRule {
            return ClashCopy.string("Can’t delete: the final rule points to it. Point the final rule elsewhere first.", locale: locale)
        }
        if users.elsewhere { return ClashCopy.format("Change references to this group before deleting it: %@", locale: locale, group) }
        return nil
    }

     
    static let shownGroups = 3

     
    public static let consequence = "Rules that point to it are deleted with it."

     
     
    public static func deleted(_ deletion: ConfigurationRuleGroupDeletion) -> ClashDisplayText {
        switch deletion.rules.count {
        case 0: return ClashFeedbackCopy.deleted(deletion.name)
        case 1: return .format("Deleted “%@” and the rule that used it", [deletion.name])
        default: return .format("Deleted “%@” and the %@ rules that used it", [deletion.name, String(deletion.rules.count)])
        }
    }

     
     
     
     
    static func quoted(_ names: [String], locale: Locale, closing: Bool) -> String {
        guard !locale.identifier.hasPrefix("zh") else { return names.map { "「" + $0 + "」" }.joined() }
        let quoted = names.map { "“" + $0 + "”" }
        return closing ? quoted.formatted(.list(type: .and).locale(locale)) : quoted.joined(separator: ", ")
    }
}

 
 
 
 
 
 
 
 
public enum ClashTowerRowRefusal {
     
     
     
     
    @MainActor @discardableResult
    public static func say(_ sentence: String, in feedback: ClashFeedbackCenter?, operation: String, identifier: String) -> Bool {
        guard let feedback else { return false }
        feedback.show(.error(title: .verbatim(sentence), accessibilityIdentifier: identifier), operation: operation)
        return true
    }
}

 
 
 
struct ClashTowerNodeSectionsLoader<Content: View>: View {
    let load: (() async -> [ConfigurationRuleTargetCandidates.Section])?
    let content: ([ConfigurationRuleTargetCandidates.Section]) -> Content
    @State private var sections: [ConfigurationRuleTargetCandidates.Section]
    @State private var loaded: Bool

    init(sections: [ConfigurationRuleTargetCandidates.Section],
         load: (() async -> [ConfigurationRuleTargetCandidates.Section])?,
         @ViewBuilder content: @escaping ([ConfigurationRuleTargetCandidates.Section]) -> Content) {
        self.load = load
        self.content = content
        _sections = State(initialValue: sections)
        _loaded = State(initialValue: load == nil || !sections.isEmpty)
    }

    var body: some View {
        Group {
            if loaded {
                content(sections)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard !loaded, let load else { return }
            sections = await load()
            loaded = true
        }
    }
}

public struct ClashTowerRuleEditorRequest {
    public let editing: ClashTowerRuleEditing?
    public let draft: ConfigurationRuleDraft
    public let options: ClashRulePolicyOptions
    public let showsTarget: Bool
    public let createGroup: ((@escaping (String?) -> Void) -> AnyView)?
    public init(editing: ClashTowerRuleEditing?, draft: ConfigurationRuleDraft, options: ClashRulePolicyOptions,
        showsTarget: Bool, createGroup: ((@escaping (String?) -> Void) -> AnyView)?) {
        self.editing = editing; self.draft = draft; self.options = options; self.showsTarget = showsTarget; self.createGroup = createGroup
    }
}

 
 
 
 
 
public enum ClashTowerRuleFocus: String, Sendable {
    case all, rules, groups
}

 
 
 
 
public enum ClashTowerSingleObject: Equatable, Sendable {
     
    case group(String)
     
     
     
    case newGroup
}

 
 
 
public enum ClashTowerListOpening: Equatable, Sendable {
    case list, reordering, adding
}

 
 
 
@MainActor
final class ClashTowerGroupUndoChannel: ObservableObject {
    var restore: (@MainActor (ConfigurationRuleGroupDeletion) async throws -> Void)?
}

public struct ClashTowerRuleCustomizationView: View {
    @State private var draft: ConfigurationRuleDraft
    @State private var baseline: ConfigurationRuleDraft
    @State private var hasUnsavedChanges = false
    @State private var installedRuleSets: Set<String>
    @State private var baselineRuleSets: Set<String>
    @State private var localSets: [ConfigurationLocalRuleSet]
    @State private var search = ""
    @State private var category: ConfigurationRuleCatalogCategory?
    @State private var reordering = false
     
     
    @State private var loadingRuleSets: Set<String> = []
    @State private var busy = false
    @State private var error: String?
     
    @Environment(\.clashFeedback) private var feedback
     
     
     
     
     
     
    @State private var refusedRound = 0
     
     
    @State private var notice: ClashDisplayText?
    @State private var modal: Modal?
    @State private var confirmsReset = false
     
     
    @State private var renaming = false
    @State private var renameText = ""
    @Environment(\.locale) private var locale
    @State private var deletingLocal: ConfigurationLocalRuleSet?
    @State private var confirmsLeave = false
     
     
    private let groupDeleted: ((ClashTowerGroupDeletionReport) -> Void)?
     
     
    private let restoreGroupDeletion: (@MainActor (ConfigurationRuleGroupDeletion, String) async throws -> Void)?
     
    @StateObject private var groupUndo = ClashTowerGroupUndoChannel()
     
     
    @Environment(\.clashRuleTargetSearch) private var memberSearch
    private let pushed: Bool
    private let focus: ClashTowerRuleFocus
     
     
     
     
    private let savesEachChange: Bool
     
     
     
     
     
     
    private let readOnly: Bool
     
     
    private let takenSchemeNames: Set<String>
     
     
    private let groupTypes: [String]
     
     
    private let groupPage: ((ClashTowerGroupPageRequest) -> AnyView)?
     
     
    private let single: ClashTowerSingleObject?
     
     
    @State private var singleGroupID: UUID?
     
     
    private let opening: ClashTowerListOpening
    @State private var opened = false
    #if os(iOS)
     
     
    @Environment(\.editMode) private var listEditMode
    #endif
     
    @State private var nodesLoaded = false
     
    @State private var changeCount = 0
    @State private var autosaving = false
    @State private var autosaveAgain = false
    @AppStorage(ClashTowerRuleCustomizationView.groupIconsPreferenceKey) private var emojis = true
     
     
     
    public static let groupIconsPreferenceKey = "clash.configuration.ruleGroupEmoji"
     
     
     
     
    private let offersGroupIcons: Bool
    private let save: (ConfigurationRuleDraft) async throws -> ConfigurationRuleDraft
    private let download: (String) async throws -> ConfigurationRuleSetContent
    private let saveLocal: (ConfigurationLocalRuleSet) async throws -> (ConfigurationRuleDraft, [ConfigurationLocalRuleSet])
    private let deleteLocal: (String) async throws -> (ConfigurationRuleDraft, [ConfigurationLocalRuleSet])
    private let copy: (ConfigurationRuleDraft, String) async throws -> Void
     
     
    private let rename: ((String, String) async throws -> Void)?
    private let resetDocument: String
    private let palette: ClashProductPalette
    private let close: () -> Void
    private let manualEditor: (ConfigurationRuleDraft, @escaping (ConfigurationRuleDraft) async throws -> Void) -> AnyView
     
     
     
     
     
     
    private let ruleEditor: (ClashTowerRuleEditorRequest, @escaping (String, Bool, String) -> Void) -> AnyView
     
     
    private let nodeCandidates: (() async -> [ConfigurationRuleTargetCandidates.Section])?
    @State private var nodeSections: [ConfigurationRuleTargetCandidates.Section] = []
    private enum Modal: String, Identifiable { case identity, group, local, copy, manual, rule; var id: String { rawValue } }
    @State private var groupID: UUID?
    @State private var localID: String?
     
    @State private var ruleID: UUID?
    @State private var ordered = ClashOrderedWork()
    @Environment(\.clashInsideProductModalPresentation) private var insideProductModal
    public init(draft: ConfigurationRuleDraft, localSets: [ConfigurationLocalRuleSet], resetDocument: String, palette: ClashProductPalette, pushed: Bool = false, ruleSetKeys: Set<String> = [],
        save: @escaping (ConfigurationRuleDraft) async throws -> ConfigurationRuleDraft, download: @escaping (String) async throws -> ConfigurationRuleSetContent,
        saveLocal: @escaping (ConfigurationLocalRuleSet) async throws -> (ConfigurationRuleDraft, [ConfigurationLocalRuleSet]), deleteLocal: @escaping (String) async throws -> (ConfigurationRuleDraft, [ConfigurationLocalRuleSet]),
        copy: @escaping (ConfigurationRuleDraft, String) async throws -> Void, close: @escaping () -> Void,
        manualEditor: @escaping (ConfigurationRuleDraft, @escaping (ConfigurationRuleDraft) async throws -> Void) -> AnyView,
        ruleEditor: @escaping (ClashTowerRuleEditorRequest, @escaping (String, Bool, String) -> Void) -> AnyView,
        nodeCandidates: (() async -> [ConfigurationRuleTargetCandidates.Section])? = nil,
        focus: ClashTowerRuleFocus = .all, savesEachChange: Bool = false,
        groupTypes: [String] = [], groupPage: ((ClashTowerGroupPageRequest) -> AnyView)? = nil,
        single: ClashTowerSingleObject? = nil, opening: ClashTowerListOpening = .list,
        rename: ((String, String) async throws -> Void)? = nil,
        takenSchemeNames: Set<String> = [], readOnly: Bool = false, offersGroupIcons: Bool = true,
        groupDeleted: ((ClashTowerGroupDeletionReport) -> Void)? = nil,
        restoreGroupDeletion: (@MainActor (ConfigurationRuleGroupDeletion, String) async throws -> Void)? = nil) {
        self.offersGroupIcons = offersGroupIcons
        self.groupDeleted = groupDeleted
        self.restoreGroupDeletion = restoreGroupDeletion
        self.rename = rename
        self.takenSchemeNames = takenSchemeNames
        self.readOnly = readOnly
        self.nodeCandidates = nodeCandidates
        self.groupTypes = groupTypes
        self.groupPage = groupPage
        self.single = single
        self.opening = opening
        self.ruleEditor = ruleEditor
        self.focus = focus
        self.savesEachChange = savesEachChange
        _draft = State(initialValue: draft); _baseline = State(initialValue: draft); _installedRuleSets = State(initialValue: ruleSetKeys); _baselineRuleSets = State(initialValue: ruleSetKeys); _localSets = State(initialValue: localSets)
        self.palette = palette
        self.pushed = pushed
        self.resetDocument = resetDocument; self.save = save; self.download = download; self.saveLocal = saveLocal
        self.deleteLocal = deleteLocal; self.copy = copy; self.close = close; self.manualEditor = manualEditor
    }
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @State private var modalOptions: ClashRulePolicyOptions?
    private var sheetOptions: ClashRulePolicyOptions { modalOptions ?? policyOptions }
    private func open(_ kind: Modal) {
        modalOptions = policyOptions
        modal = kind
    }
    private func refreshModalOptions() {
        if modalOptions != nil { modalOptions = policyOptions }
    }
    private var policyOptions: ClashRulePolicyOptions {
        let document = draft.currentDocument()
        var seen = Set<String>()
        var nodes: [ClashRulePolicySnapshot] = []
        if case .array(let entries) = document.topLevelValue("proxies") {
            for entry in entries {
                guard case .string(let name) = entry.topLevelValue("name"), !name.isEmpty, seen.insert(name).inserted else { continue }
                var type = ""
                if case .string(let value) = entry.topLevelValue("type") { type = value }
                nodes.append(ClashRulePolicySnapshot(name: name, type: type))
            }
        }
        for section in nodeSections {
             
            guard section.kind != .providers else { continue }
            for name in section.names where seen.insert(name).inserted {
                nodes.append(ClashRulePolicySnapshot(name: name, type: section.sourceLabel ?? ""))
            }
        }
        var ruleSets: [String] = []
        if case .object(let fields) = document.topLevelValue("rule-providers") { ruleSets = fields.map(\.key).sorted() }
        var subRules: [String]?
        if case .object(let fields) = document.topLevelValue("sub-rules") { subRules = fields.map(\.key).sorted() }
        return ClashRulePolicyOptions(
            groups: draft.groups.map { ClashRulePolicySnapshot(name: $0.name, type: $0.type, isHidden: $0.isHidden) },
            proxies: nodes, ruleSets: ruleSets, subRuleNames: subRules, ruleSetsAreKnown: true)
    }
     
     
     
     
     
    private func groupCreator(_ done: @escaping (String?) -> Void) -> AnyView {
         
        guard let groupPage else { return AnyView(EmptyView()) }
        return groupPage(newGroupRequest(sections: nodeSections, save: { value in
            try await apply { snapshot in var changed = snapshot; try changed.setGroup(value, groupID: nil); return changed }
            done(Self.groupName(value))
        }, cancel: { done(nil) }))
    }

     
    private static func groupName(_ document: OrderedJSON) -> String? {
        if case .string(let value)? = document.topLevelValue("name"), !value.isEmpty { return value }
        return nil
    }

     
     
    public static var blankGroup: ConfigurationRuleDraft.Group {
        .init(document: .object([("name", .string("")), ("type", .string("select")), ("proxies", .array([]))]))
    }

     
     
    private func pageRequest(for group: ConfigurationRuleDraft.Group, index: Int,
                             sections: [ConfigurationRuleTargetCandidates.Section]) -> ClashTowerGroupPageRequest {
        var request = ClashTowerGroupPageRequest(group: group, index: index, all: draft.groups, nodeSections: sections,
                                                 save: { value in try await saveGroup(value, id: group.id) })
        request.targetSearch = memberSearch
        if readOnly {
            request.mode = .reading
        } else {
            var deletion = ClashTowerGroupPageDeletion(users: draft.groupUsers(group.id)) { deleteGroup(group.id) }
             
            deletion.dismissesPage = single == nil
            request.deletion = deletion
        }
        return request
    }

     
     
    private func newGroupRequest(sections: [ConfigurationRuleTargetCandidates.Section],
                                 save: @escaping (OrderedJSON) async throws -> Void,
                                 cancel: @escaping () -> Void) -> ClashTowerGroupPageRequest {
        var request = ClashTowerGroupPageRequest(group: Self.blankGroup, index: draft.groups.count, all: draft.groups,
                                                 nodeSections: sections, save: save)
        request.mode = .adding(cancel: cancel)
        request.targetSearch = memberSearch
        return request
    }

     
     
     
     
     
     
     
    private func deleteGroup(_ id: UUID) {
        guard !readOnly, let group = draft.groups.first(where: { $0.id == id }) else { return }
        let users = draft.groupUsers(id)
        if let refused = ClashTowerGroupDeletionCopy.refusal(users, group: group.name, locale: locale) {
            sayRefusal(refused)
            return
        }
        var changed = draft
        let deletion: ConfigurationRuleGroupDeletion?
        do { deletion = try changed.deleteRoutingGroupRestorably(id) } catch {
             
             
             
            sayRefusal(ClashConfigurationRuleGroupCopy.message(error, locale: locale))
            return
        }
        guard let deletion else { return }
        if modal != nil { modal = nil }
        if single != nil {
             
             
            perform {
                let saved = try await save(changed)
                groupUndo.restore = nil
                close()
                report(deletion, schemeID: saved.schemeID)
            }
            return
        }
         
         
         
         
         
        Task { @MainActor in
            do { try await apply { snapshot in var value = snapshot; try value.deleteRoutingGroup(id); return value } } catch {
                sayRefusal(ClashTowerGroupDeletionCopy.refusal(draft.groupUsers(id), group: group.name, locale: locale)
                           ?? ClashConfigurationRuleGroupCopy.message(error, locale: locale))
            }
        }
        report(deletion, schemeID: draft.schemeID)
    }

     
     
     
    private func report(_ deletion: ConfigurationRuleGroupDeletion, schemeID: String) {
        guard let groupDeleted else { return }
        let channel = groupUndo
        let fallback = savesEachChange ? restoreGroupDeletion : nil
        groupDeleted(ClashTowerGroupDeletionReport(deletion: deletion) { [weak channel] in
            if let restore = channel?.restore {
                try await restore(deletion)
            } else if let fallback {
                try await fallback(deletion, schemeID)
            } else {
                throw ClashTowerGroupUndoUnavailable()
            }
        })
    }

     
     
    private func restoreIntoList(_ deletion: ConfigurationRuleGroupDeletion) async throws {
        try await apply { snapshot in var value = snapshot; try value.restoreGroupDeletion(deletion); return value }
    }
     
     
     
    @ViewBuilder
    private var trailingButtons: some View {
        if focus != .all {
            if autosaving {
                ProgressView().accessibilityIdentifier("configuration.rules.focus.saving")
            }
             
            if !readOnly {
                Button { addToFocus() } label: { Image(systemName: ClashSymbol.plus.rawValue) }
                    .accessibilityLabel(Text(ClashCopy.key(addTitle)))
                    .accessibilityIdentifier("configuration.rules.focus.add")
                    .disabled(busy)
            }
        }
        if !readOnly {
            if focus == .all {
                Button {
                    var transaction = Transaction(); transaction.disablesAnimations = true
                    withTransaction(transaction) { reordering.toggle() }
                } label: { ClashActionProgressLabel(.copy(reordering ? "Done" : "Edit"), isBusy: busy && pushed) }.foregroundStyle(.tint).disabled(busy)
            } else {
                 
                 
                 
                #if os(iOS)
                ClashTowerReorderButton(identifier: "configuration.rules.focus.reorder")
                #endif
            }
        }
         
         
         
         
        if !pushed, !reordering, !reorderingAList {
             
             
            Button { if hasUnsavedChanges { persist(draft, then: close) } else { close() } } label: { ClashActionProgressLabel(.copy("Done"), isBusy: busy) }.foregroundStyle(.tint).disabled(busy || !loadingRuleSets.isEmpty)
        }
    }
    private func shows(_ part: ClashTowerRuleFocus) -> Bool { focus == .all || focus == part }
     
    private var reorderingAList: Bool {
        #if os(iOS)
        return focus != .all && listEditMode?.wrappedValue.isEditing == true
        #else
        return false
        #endif
    }
     
     
    @ViewBuilder
    private func groupRow<Label: View>(_ group: ConfigurationRuleDraft.Group, @ViewBuilder label: () -> Label) -> some View {
        if let groupPage, let index = draft.groups.firstIndex(where: { $0.id == group.id }) {
            NavigationLink {
                 
                 
                 
                 
                ClashTowerNodeSectionsLoader(sections: nodeSections, load: nodesLoaded ? nil : nodeCandidates) { sections in
                    groupPage(pageRequest(for: group, index: index, sections: sections))
                }
                    .clashPushedDetailPage()
                    .clashNativePushBoundary()
            } label: { label() }
        } else {
             
            label()
        }
    }
     
     
    private func groupLabel(_ group: ConfigurationRuleDraft.Group) -> some View {
        HStack(spacing: 10) {
            if emojis {
                ClashTowerGroupIconView(icon: ClashTowerGroupIcon.read(group.document), size: ClashTheme.Layout.proxyGroupIconSize) {
                    if let symbol = emoji(group.name) { Text(verbatim: symbol).font(.title3) }
                    else { Image(systemName: "rectangle.3.group").font(.body).foregroundStyle(.secondary) }
                }.frame(width: 28, height: 28)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityIdentifier("configuration.rules.group.row.icon")
            }
            Text(verbatim: displayName(group.name)).foregroundStyle(Color.primary)
                .lineLimit(1).truncationMode(.tail).layoutPriority(1)
            Spacer(minLength: 12)
            Text(clash: summary(group)).font(.subheadline).foregroundStyle(Color.secondary)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 140, alignment: .trailing)
            if groupPage == nil {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }.frame(minHeight: 36).contentShape(Rectangle())
    }
     
     
    private var holdsUnsaved: Bool { savesEachChange ? hasUnsavedChanges && !autosaving : hasUnsavedChanges }
    private var pageTitle: String {
        switch focus {
        case .all: "Rule Customization"
        case .rules: "Rules"
        case .groups: "Policy Groups"
        }
    }
    private var addTitle: String {
        switch focus {
        case .rules: "Add Rule"
        case .groups: "Add Policy Group"
        case .all: "Add"
        }
    }
     
    private func addToFocus() {
        switch focus {
        case .rules: ruleID = nil; open(.rule)
        case .groups: groupID = nil; modal = .group
        case .all: break
        }
    }
    private var visibleGroups: [ConfigurationRuleDraft.Group] { draft.groups.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.type.localizedCaseInsensitiveContains(search) } }
    private var entries: [ConfigurationRuleCatalogEntry] { ConfigurationRuleCatalog.builtIn.entries.filter { (category == nil || $0.category == category) && $0.matches(search) } }
    public var body: some View {
        root
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: pushed ? .primaryAction : .cancellationAction) {
                 
                if single == nil {
                    Menu {
                        if offersGroupIcons {
                            Toggle("Show Group Icons", isOn: $emojis).accessibilityIdentifier("configuration.rules.emojis")
                        }
                        if rename != nil, !readOnly {
                            Button { renameText = draft.labelAsRead(locale: locale); renaming = true } label: { Label("Rename…", systemImage: ClashSymbol.pencil.rawValue) }
                                .accessibilityIdentifier("configuration.rules.rename")
                        }
                         
                         
                        if !readOnly {
                            Button("Edit Rules Source") { modal = .manual }
                        }
                        Button("Save as New Scheme") { modal = .copy }
                        if !readOnly {
                            Divider()
                            Button("Restore Initial Rules", role: .destructive) { confirmsReset = true }
                        }
                    } label: { Label("More", systemImage: "ellipsis").foregroundStyle(.tint) }.disabled(busy)
                }
            }
            ToolbarItemGroup(placement: .confirmationAction) {
                if single == nil {
                    trailingButtons
                } else if autosaving {
                    ProgressView().accessibilityIdentifier("configuration.rules.focus.saving")
                }
            }
        }
        .clashBackButtonHidden(pushed && (holdsUnsaved || busy || (savesEachChange && !loadingRuleSets.isEmpty)))
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) {
                if pushed && (holdsUnsaved || busy) {
                    Button("Back") { confirmsLeave = true }
                        .accessibilityLabel("Back").disabled(busy)
                }
            }
        }
        .clashUnsavedChangesAlert(isPresented: $confirmsLeave,
            message: .copy("This profile has changes that have not been saved."), isBusy: busy,
            save: { persist(draft, then: close) },
            discard: { draft = baseline; installedRuleSets = baselineRuleSets; hasUnsavedChanges = false; close() })
        .clashRegistersDeparture(isDirty: savesEachChange ? hasUnsavedChanges && !autosaving : hasUnsavedChanges, isBusy: busy, save: { completion in persist(draft, completion: completion) }, discard: { draft = baseline; installedRuleSets = baselineRuleSets; hasUnsavedChanges = false })
         
         
        .interactiveDismissDisabled(holdsUnsaved || busy || !loadingRuleSets.isEmpty)
         
        .onChange(of: changeCount) { _ in if single == nil { saveLatest() } }
         
         
         
         
        .onChange(of: changeCount) { _ in feedback?.dismiss(operation: "configuration.rules.refusal") }
        .clashOnScreen { onScreen in if !onScreen { feedback?.dismiss(operation: "configuration.rules.refusal") } }
        .onAppear {
             
            if single == nil { groupUndo.restore = { deletion in try await restoreIntoList(deletion) } }
             
             
            guard focus != .all, !opened, !readOnly else { return }
            opened = true
            switch opening {
            case .adding: addToFocus()
            case .reordering:
                #if os(iOS)
                listEditMode?.wrappedValue = .active
                #endif
            case .list: break
            }
        }
        .task {
            if let nodeCandidates, nodeSections.isEmpty { nodeSections = await nodeCandidates() }
            nodesLoaded = true
        }
        .onChange(of: nodeSections.count) { _ in refreshModalOptions() }
        .onChange(of: draft.groups.map(\.name)) { _ in refreshModalOptions() }
        .onChange(of: modal) { if $0 == nil { modalOptions = nil } }
        .clashProductModal(item: $modal, role: .form) { kind in
            ClashSingleColumnNavigationContainer {
                modalContent(kind)
            }.environment(\.clashProductModalDismiss, { modal = nil })
        }
        .alert("Restore Initial Rules?", isPresented: $confirmsReset) {
            Button("Restore Initial Rules", role: .destructive) {
                let source = resetDocument
                mutate { snapshot in var value = snapshot; try value.replaceContents(OrderedJSON.parse(source)); return value }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Removes the rules, renames and reordering added after the scheme was created. My Rule Sets stay.") }
         
        .clashTextFieldAlert("Rename", isPresented: $renaming, text: $renameText,
                             field: ClashTextFieldAlertField(placeholder: "Name",
                                                             identifier: "configuration.rules.rename.name")) { typed in
            guard let rename, let name = draft.newName(typed: typed, locale: locale) else { return }
            let id = draft.schemeID
            perform {
                try await rename(id, name)
                Self.takeRename(name, draft: &draft, baseline: &baseline)
            }
        }
        .clashDeleteConfirmation(presenting: $deletingLocal, name: \.name,
            actionTitle: .copy("Delete Rule Set"),
            message: { _ in .copy("This local rule set will be deleted. Rule schemes in the library will also remove rules added from it.") },
            identifier: "configuration.rules.local.delete.confirm", cancel: { redrawRows() }) { item in
                perform(fromRow: true) {
                    let updated = try await deleteLocal(item.id)
                     
                     
                    localSets = updated.1
                    try await receiveHostWrite(updated.0) { scheme in scheme.removeRuleSet("local-" + item.id) }
                }
            }

    }
     
    @ViewBuilder
    private var root: some View {
        if let single, let page = singlePage(single) {
             
            page.safeAreaInset(edge: .bottom, spacing: 0) {
                if let error {
                    Text(verbatim: error).font(.footnote).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading).padding()
                } else if let notice {
                    Text(clash: notice).font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding()
                }
            }
        } else {
            listPage
        }
    }

     
     
     
    private func singlePage(_ object: ClashTowerSingleObject) -> AnyView? {
        switch object {
        case .group(let name):
            guard let groupPage,
                  let index = singleGroupID.flatMap({ id in draft.groups.firstIndex { $0.id == id } })
                    ?? draft.groups.firstIndex(where: { $0.name == name }) else { return nil }
             
             
            guard nodeCandidates == nil || nodesLoaded else {
                return AnyView(ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity))
            }
            let group = draft.groups[index]
            return AnyView(groupPage(pageRequest(for: group, index: index, sections: nodeSections))
                .id(group.id)
                .onAppear { if singleGroupID == nil { singleGroupID = group.id } })
        case .newGroup:
            guard let groupPage else { return nil }
            guard nodeCandidates == nil || nodesLoaded else {
                return AnyView(ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity))
            }
             
             
            return AnyView(groupPage(newGroupRequest(sections: nodeSections, save: { value in
                var changed = draft
                try changed.setGroup(value, groupID: nil)
                _ = try await save(changed)
                close()
            }, cancel: { close() })))
        }
    }

     
    private var listPage: some View {
        List {
            if let error { Text(verbatim: error).foregroundStyle(.orange) }
            if let notice {
                Text(clash: notice).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("configuration.rules.saved-as-own")
            }
             
             
             
             
            if shows(.rules) {
            if readOnly {
                 
                 
                ClashTowerInlineRules(rows: draft.rows, version: draft.version, query: search, palette: palette,
                                      ruleSetNames: ruleSetNames)
            } else {
            ClashTowerInlineRules(rows: draft.rows, version: draft.version,
                 
                 
                 
                query: search, palette: palette, remove: reorderingAList ? nil : { id in
                    draft.remove([id]); installedRuleSets = draft.referencedRuleSets; hasUnsavedChanges = true
                    changeCount += 1
                },
                move: { offsets, destination in
                    var transaction = Transaction(); transaction.disablesAnimations = true
                    withTransaction(transaction) { draft.moveRows(fromOffsets: offsets, toOffset: destination) }
                    hasUnsavedChanges = true
                    changeCount += 1
                },
                 
                ruleSetNames: ruleSetNames, addRule: focus == .all ? { ruleID = nil; open(.rule) } : nil,
                edit: { ruleID = $0; open(.rule) })
            }
            }
            if shows(.groups) {
            Section {
                if !readOnly {
                ForEach(visibleGroups) { group in
                    groupRow(group) { groupLabel(group) }
                        .accessibilityIdentifier("configuration.rules.group.row")
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .moveDisabled(!search.isEmpty)
                        .contextMenu {
                            Button { groupID = group.id; modal = .identity } label: {
                                Label { Text("Edit Name and Icon") } icon: { Image(systemName: ClashSymbol.pencil.rawValue) }
                            }
                            Button(role: .destructive) { deleteGroup(group.id) } label: {
                                Label { Text("Delete") } icon: { Image(systemName: ClashSymbol.trash.rawValue) }
                            }
                        }
                         
                         
                         
                        .clashSwipeToDelete(reorderingAList ? nil : { deleteGroup(group.id) })
                        .accessibilityAction(named: Text("Edit Name and Icon")) { groupID = group.id; modal = .identity }
                }.onDelete(perform: reorderingAList ? nil : { offsets in
                    guard let index = offsets.first, visibleGroups.indices.contains(index) else { return }
                    deleteGroup(visibleGroups[index].id)
                }).onMove { offsets, destination in
                    var ids = draft.groups.map(\.id); ids.move(fromOffsets: offsets, toOffset: destination)
                    var changed = draft
                    changed.reorderGroups(ids)
                    draft = changed; hasUnsavedChanges = true
                    changeCount += 1
                }
                 
                 
                 
                if search.isEmpty, focus == .all {
                    ClashAddRow(Text(clash: .copy("Add Policy Group"))) { groupID = nil; modal = .group }
                        .accessibilityIdentifier("configuration.rules.group.add")
                }
                } else {
                     
                     
                    ForEach(visibleGroups) { group in
                        groupRow(group) { groupLabel(group) }
                            .accessibilityIdentifier("configuration.rules.group.row")
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                }
            } header: { HStack { Text("Policy Groups"); Spacer(); Text(clash: .format("%@ groups", [String(visibleGroups.count)])) } }
            .id("groups-\(refusedRound)")
            }
             
             
            if !readOnly {
             
             
             
            if focus == .all { localRuleSetsSection }
            if focus == .all && reordering {
                Section {
                    ForEach(entries) { entry in
                        Button { toggleCatalog(entry) } label: {
                            HStack(spacing: 12) {
                                Text(entry.emoji).font(.title3).frame(width: 36, height: 36).background(.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 3) { Text(verbatim: entry.name).font(.body).foregroundStyle(.primary); Text(verbatim: entry.provider.displayName + " · " + route(entry.defaultRoute)).font(.caption).foregroundStyle(.secondary) }
                                Spacer(minLength: 8)
                                mark(installedRuleSets.contains("catalog-" + entry.id),
                                     loading: loadingRuleSets.contains("catalog-" + entry.id))
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .accessibilityIdentifier("configuration.rules.catalog.toggle.\(entry.id)")
                    }
                    if entries.isEmpty { Text("No results").foregroundStyle(.secondary) }
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Online Rule Library")
                        Text("\(entries.count)").monospacedDigit()
                        Spacer()
                        Picker("Category", selection: $category) {
                            Text("All").tag(Optional<ConfigurationRuleCatalogCategory>.none)
                            ForEach(ConfigurationRuleCatalogCategory.allCases, id: \.self) { item in
                                Text(verbatim: item.displayName).tag(Optional(item))
                            }
                        }
                        .pickerStyle(.menu).labelsHidden().textCase(nil).accessibilityIdentifier("configuration.rules.category")
                    }
                }
            }
            }
            if insideProductModal {
                 
                 
                Section("More") {
                    Toggle("Show Group Icons", isOn: $emojis).accessibilityIdentifier("configuration.rules.emojis")
                    if !readOnly {
                        Button("Edit Rules Source") { modal = .manual }
                    }
                    Button("Save as New Scheme") { modal = .copy }
                    if !readOnly {
                        Button("Restore Initial Rules", role: .destructive) { confirmsReset = true }
                    }
                }.disabled(busy)
            }
        }
         
         
        .modifier(ClashTowerReorderMode(active: reordering, applies: focus == .all))
        .modifier(ClashTowerSelectionFeedback(trigger: installedRuleSets))
        .modifier(ClashTowerSearchPlacement(text: $search, palette: palette))
        .clashPageTitle(.copy(pageTitle))
         
         
         
        .clashProductModalRoot(
            title: .copy(pageTitle),
            actionTitle: reordering ? "Done" : "Edit",
            actionDisabled: busy || readOnly,
            action: {
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { reordering.toggle() }
            }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if insideProductModal, !pushed {
                ClashModalActionBar(primaryTitle: "Done", primaryDisabled: busy || !loadingRuleSets.isEmpty, isBusy: busy,
                    onPrimary: { if hasUnsavedChanges { persist(draft, then: close) } else { close() } })
            }
        }
    }

    private var localRuleSetsSection: some View {
            Section {
                Button { localID = nil; open(.local) } label: {
                    Label { VStack(alignment: .leading, spacing: 3) { Text("New Rule Set").font(.body).foregroundStyle(.primary); Text("Add manually or use a rule set link").font(.caption).foregroundStyle(Color.secondary) } } icon: { Image(systemName: "text.badge.plus").foregroundStyle(.primary) }
                }.buttonStyle(.plain)
                ForEach(localSets.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { item in
                    HStack(spacing: 12) {
                        Button { localID = item.id; open(.local) } label: {
                            HStack { Text("🧩").font(.title3); VStack(alignment: .leading, spacing: 3) { Text(verbatim: item.name).foregroundStyle(.primary); Text(clash: .format("Local · %@ rules", [String(item.ruleCount)])).font(.caption).foregroundStyle(.secondary) }; Spacer() }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Button { toggleLocal(item) } label: {
                            mark(installedRuleSets.contains("local-" + item.id), loading: false)
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("configuration.rules.local.toggle")
                    }.contextMenu {
                        Button { localID = item.id; open(.local) } label: {
                            Label { Text("Edit Rule Content") } icon: { Image(systemName: ClashSymbol.pencil.rawValue) }
                        }
                         
                         
                        Button(role: .destructive) { deletingLocal = item } label: {
                            Label { Text("Delete") } icon: { Image(systemName: ClashSymbol.trash.rawValue) }
                        }
                    }
                    .clashSwipeToDelete(identifier: "configuration.rules.local.delete") { deletingLocal = item }
                }
            } header: { HStack { Text("My Rule Sets"); Spacer(); Text(clash: .format("%@ items", [String(localSets.count)])) } }
            .id("rule-sets-\(refusedRound)")

    }
    @ViewBuilder
    private func mark(_ selected: Bool, loading: Bool) -> some View {
        if loading {
            ProgressView()
                .controlSize(.small)
                .frame(width: ClashTheme.Control.minimumHitTarget, height: ClashTheme.Control.minimumHitTarget)
                .accessibilityLabel(Text(ClashCopy.key("Loading")))
        } else {
            Image(systemName: selected ? "minus.circle" : "plus.circle")
                .font(.title3)
                .foregroundStyle(selected ? Color.red : .accentColor)
                .frame(width: ClashTheme.Control.minimumHitTarget, height: ClashTheme.Control.minimumHitTarget)
                .contentShape(Rectangle())
                .accessibilityLabel(Text(ClashCopy.key(selected ? "Remove from Current Rules" : "Add to Current Rules")))
        }
    }
    private func emoji(_ name: String) -> String? {
        guard let first = name.trimmingCharacters(in: .whitespaces).first,
              first.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }) else { return nil }
        return String(first)
    }
     
    private var ruleSetNames: [String: String] {
        var names: [String: String] = [:]
        for set in localSets { names["local-" + set.id] = set.name }
        for entry in ConfigurationRuleCatalog.builtIn.entries { names["catalog-" + entry.id] = entry.displayName }
        return names
    }
    private func displayName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return emoji(trimmed) == nil ? trimmed : String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
     
     
    private func summary(_ group: ConfigurationRuleDraft.Group) -> ClashDisplayText { if case .array(let values) = group.document.topLevelValue("proxies"), case .string(let value) = values.first { return .verbatim(value) }; return .copy(group.type == "url-test" ? "Chosen automatically" : "Matching Nodes") }
    private func route(_ value: ConfigurationRuleCatalogDefaultRoute) -> String { ClashCopy.string(value == .direct ? "Direct" : value == .reject ? "Block" : "Proxy", locale: locale) }
     
     
     
     
     
    private func toggleCatalog(_ entry: ConfigurationRuleCatalogEntry) {
        let key = "catalog-" + entry.id
        guard !loadingRuleSets.contains(key) else { return }
        if installedRuleSets.contains(key) {
            change(fromRow: true) { value in var value = value; value.removeRuleSet(key); return value }
            return
        }
        loadingRuleSets.insert(key)
        Task { @MainActor in
            defer { loadingRuleSets.remove(key) }
            do {
                let content = try await download(entry.sourceURLString)
                try await apply { value in
                    var value = value
                    try value.addRuleSet(key: key, name: entry.displayName, rules: content.rules,
                                         defaultRoute: entry.defaultRoute.rawValue, link: content.link, behavior: content.behavior)
                    return value
                }
            } catch { sayFailure(error, fromRow: true) }
        }
    }
    private func toggleLocal(_ item: ConfigurationLocalRuleSet) {
        let key = "local-" + item.id
        let removing = installedRuleSets.contains(key)
        change(fromRow: true) { snapshot in
            var value = snapshot
            if removing { value.removeRuleSet(key) } else { try value.addRuleSet(key: key, name: item.name, rules: item.rules, defaultRoute: "proxy", link: item.link, behavior: item.behavior) }
            return value
        }
    }
     
     
     
    private func apply(_ transform: @escaping @Sendable (ConfigurationRuleDraft) throws -> ConfigurationRuleDraft) async throws {
         
         
         
        try await ordered.run {
            let snapshot = draft
            let value = try await Task.detached { try transform(snapshot) }.value
            let keys = await Task.detached { value.referencedRuleSets }.value
            withAnimation { draft = value; installedRuleSets = keys; hasUnsavedChanges = true; changeCount += 1 }
        }
    }
     
     
    private func change(fromRow: Bool = false,
                        _ transform: @escaping @Sendable (ConfigurationRuleDraft) throws -> ConfigurationRuleDraft) {
        Task { @MainActor in
            do { try await apply(transform) } catch { sayFailure(error, fromRow: fromRow) }
        }
    }
     
     
     
    private func sayFailure(_ error: Error, fromRow: Bool) {
        let text = ClashTowerRulesErrorText.describe(error)
        if fromRow { sayRefusal(text, redraws: false) } else { self.error = text }
    }
     
     
     
     
    private func sayRefusal(_ sentence: String, redraws: Bool = true) {
        let said = ClashTowerRowRefusal.say(sentence, in: feedback, operation: "configuration.rules.refusal",
                                            identifier: "feedback.rules.refusal")
        if !said { error = sentence }
        if redraws { redrawRows() }
    }
     
     
     
    private func redrawRows() {
        var redraw = Transaction(); redraw.disablesAnimations = true
        withTransaction(redraw) { refusedRound += 1 }
    }
    private func receiveSaved(_ value: ConfigurationRuleDraft) async {
        let keys = await Task.detached { value.referencedRuleSets }.value
         
         
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            draft = value; baseline = value; installedRuleSets = keys; baselineRuleSets = keys; hasUnsavedChanges = false
        }
    }
    private func receivePending(_ value: ConfigurationRuleDraft) async {
        let keys = await Task.detached { value.referencedRuleSets }.value
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            draft = value; installedRuleSets = keys; hasUnsavedChanges = true
        }
    }
     
     
     
     
     
    private func receiveHostWrite(_ stored: ConfigurationRuleDraft, applying change: @escaping @Sendable (inout ConfigurationRuleDraft) throws -> Void) async throws {
        try await ordered.run {
            guard hasUnsavedChanges else { await receiveSaved(stored); return }
            let snapshot = draft
             
             
             
            let rebased = try await Task.detached { var value = snapshot; try change(&value); return value.rebased(onto: stored) }.value
            let value = rebased.draft
            let keys = await Task.detached { value.referencedRuleSets }.value
            let storedKeys = await Task.detached { stored.referencedRuleSets }.value
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) {
                draft = value; installedRuleSets = keys; baseline = stored; baselineRuleSets = storedKeys; hasUnsavedChanges = true
                changeCount += 1
                if !rebased.droppedRuleSets.isEmpty {
                     
                     
                    let names = rebased.droppedRuleSets.map { key in localSets.first { "local-" + $0.id == key }?.name ?? key }
                    error = ClashCopy.format("Rules on removed rule sets were left out: %@", locale: locale, names.joined(separator: ", "))
                }
            }
        }
    }
    private func mutate(_ transform: @escaping @Sendable (ConfigurationRuleDraft) throws -> ConfigurationRuleDraft) {
        change(transform)
    }
     
     
    @ViewBuilder
    private func modalContent(_ kind: Modal) -> some View {
        switch kind {
        case .identity, .group:
            groupPageInModal(adding: kind == .group && groupID == nil)
        case .local:
            ClashTowerLocalRuleEditor(
                value: localSets.first { $0.id == localID },
                policy: localID.flatMap { draft.ruleSetPolicy("local-" + $0) }
                    ?? draft.groups.first { !$0.isHidden }?.name ?? "DIRECT",
                options: sheetOptions,
                palette: palette,
                buildRule: { line, accept in
                    ruleEditor(.init(editing: line.map { ClashTowerRuleEditing(raw: $0, isEnabled: true, note: "") }, draft: draft,
                                     options: sheetOptions, showsTarget: false, createGroup: nil)) { raw, _, _ in accept(raw) }
                },
                createGroup: groupCreator,
                save: { name, input, policy in
                    let read = try await download(input)
                    let rules = read.rules
                    let id = localID ?? UUID().uuidString.lowercased()
                     
                    let value = ConfigurationLocalRuleSet(id: id, name: name, input: input, rules: rules, link: read.link,
                                                          behavior: read.behavior)
                     
                     
                     
                    let updated = try await saveLocal(value)
                    try await receiveHostWrite(updated.0) { scheme in try scheme.updateLocalRuleSet(value) }
                     
                     
                    try await apply { snapshot in
                        var changed = snapshot
                        try changed.attachRuleSet(key: "local-" + id, name: name, rules: rules, policy: policy, link: read.link, behavior: read.behavior)
                        return changed
                    }
                    localSets = updated.1; modal = nil
                }, close: { modal = nil })
        case .copy:
             
             
            ClashTowerNameEditor(title: "Save as New Scheme", name: Self.newSchemeName(draft, locale: locale, taken: takenSchemeNames), save: { name in try await copy(draft, name); modal = nil; hasUnsavedChanges = false; close() }, close: { modal = nil })
        case .manual:
            manualEditor(draft, saveManual)
        case .rule:
            if let id = ruleID, let row = draft.rows.first(where: { $0.id == id }) {
                 
                 
                 
                 
                ruleEditor(.init(editing: .init(raw: row.raw, isEnabled: draft.isEnabled(row.raw), note: draft.note(for: row.raw)),
                    draft: draft, options: sheetOptions, showsTarget: true, createGroup: groupCreator)) { raw, enabled, note in
                    mutate { snapshot in
                        var changed = snapshot
                        changed.setRule(raw, enabled: enabled, note: note, rowID: id)
                        return changed
                    }
                }
            } else {
                 
                 
                ruleEditor(.init(editing: nil, draft: draft, options: sheetOptions, showsTarget: true, createGroup: groupCreator)) { raw, enabled, note in
                    mutate { snapshot in
                        var changed = snapshot
                        changed.insertRuleFirst(raw)
                        if let first = changed.rows.first { changed.setRule(raw, enabled: enabled, note: note, rowID: first.id) }
                        return changed
                    }
                }
            }
        }
    }
     
     
     
    @ViewBuilder
    private func groupPageInModal(adding: Bool) -> some View {
        if let groupPage {
            if adding {
                groupPage(newGroupRequest(sections: nodeSections, save: { value in try await saveGroup(value, id: nil) },
                                          cancel: { modal = nil }))
            } else if let id = groupID, let index = draft.groups.firstIndex(where: { $0.id == id }) {
                groupPage({
                    var request = pageRequest(for: draft.groups[index], index: index, sections: nodeSections)
                    request.close = { modal = nil }
                     
                    request.deletion?.dismissesPage = false
                    return request
                }())
            }
        }
    }
     
     
    private func saveManual(_ value: ConfigurationRuleDraft) async throws {
        if savesEachChange { try await apply { _ in value }; return }
        let result = try await save(value); await receiveSaved(result)
    }
     
     
     
    private func saveGroup(_ value: OrderedJSON, id: UUID?) async throws {
        if savesEachChange {
            try await apply { current in var changed = current; try changed.setGroup(value, groupID: id); return changed }
            if id == nil { modal = nil }
             
             
             
             
            if single != nil { saveLatest() }
            return
        }
        let snapshot = draft
        let changed = try await Task.detached { var valueDraft = snapshot; try valueDraft.setGroup(value, groupID: id); return valueDraft }.value
        let saved = try await save(changed); await receiveSaved(saved); modal = nil
    }
     
     
     
     
    private func saveLatest() {
        guard savesEachChange, hasUnsavedChanges else { return }
        guard !autosaving else { autosaveAgain = true; return }
        autosaving = true
        Task { @MainActor in
            repeat {
                autosaveAgain = false
                let started = changeCount
                let value = draft
                do {
                    let saved = try await save(value)
                    if saved.schemeID != value.schemeID { notice = .copy("Saved as your own scheme, used by this configuration only.") }
                    try await ordered.run {
                        if changeCount == started {
                            await receiveSaved(saved)
                        } else {
                             
                             
                             
                             
                            let continued = draft.continuing(after: saved)
                            let storedKeys = await Task.detached { saved.referencedRuleSets }.value
                            var transaction = Transaction(); transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                draft = continued
                                baseline = saved; baselineRuleSets = storedKeys; hasUnsavedChanges = true
                            }
                            autosaveAgain = true
                        }
                    }
                    error = nil
                } catch {
                    self.error = ClashTowerRulesErrorText.describe(error)
                    autosaveAgain = false
                }
            } while autosaveAgain
            autosaving = false
        }
    }
    private func persist(_ value: ConfigurationRuleDraft, then: @escaping () -> Void = {}, completion: @escaping (Bool) -> Void = { _ in }) {
        guard !busy else { completion(false); return }; busy = true; error = nil
        Task { @MainActor in
            defer { busy = false }
            do { let saved = try await save(value); await receiveSaved(saved); completion(true); then() }
            catch { await receivePending(value); self.error = ClashTowerRulesErrorText.describe(error); completion(false) }
        }
    }
     
     
     
    public static func canRenameFromEditor(_ scheme: ConfigurationRuleScheme, openedFromConfiguration: Bool,
                                           focus: ClashTowerRuleFocus) -> Bool {
        !openedFromConfiguration && focus == .all && ClashTowerRulesLibraryView.canRename(scheme)
    }
     
     
     
    static func takeRename(_ name: String, draft: inout ConfigurationRuleDraft, baseline: inout ConfigurationRuleDraft) {
        draft.label = name
        baseline.label = name
    }
     
     
     
     
     
     
     
     
     
     
    public static func newSchemeName(_ draft: ConfigurationRuleDraft, locale: Locale, taken: Set<String> = []) -> String {
        nextFreeName(draft.labelAsRead(locale: locale) + ClashCopy.string(" Copy", locale: locale), taken: taken)
    }
     
     
     
     
     
     
    public static func nextFreeName(_ root: String, taken: Set<String>) -> String {
        let existing = Set(taken.map(\.localizedLowercase))
        guard existing.contains(root.localizedLowercase) else { return root }
        var index = 2
        while existing.contains("\(root) \(index)".localizedLowercase) { index += 1 }
        return "\(root) \(index)"
    }
     
     
     
     
     
    public static func takenSchemeNames(in library: ConfigurationLibrarySnapshot, locale: Locale) -> Set<String> {
        var names = Set(ConfigurationBuiltins.schemes.map { ClashTowerRulesLibraryView.displayLabel($0, locale: locale) })
        for scheme in library.availableRules {
            names.insert(scheme.label)
            names.insert(ClashTowerRulesLibraryView.displayLabel(scheme, locale: locale))
        }
        return names
    }
     
     
    private func perform(fromRow: Bool = false, _ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { if fromRow { redrawRows() }; return }; busy = true; error = nil
        Task { @MainActor in defer { busy = false }; do { try await operation() } catch { sayFailure(error, fromRow: fromRow); if fromRow { redrawRows() } } }
    }
}

 
 
 
 
 
public extension ConfigurationRuleScheme {
    func labelAsRead(locale: Locale) -> String {
        builtinNamedAfter == nil ? label : ClashCopy.string(label, locale: locale)
    }
     
     
     
    func newName(typed: String, locale: Locale) -> String? {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name == label || name == labelAsRead(locale: locale) ? nil : name
    }
}

public extension ConfigurationRuleDraft {
     
    func labelAsRead(locale: Locale) -> String {
        label == builtinsName ? ClashCopy.string(label, locale: locale) : label
    }
    func newName(typed: String, locale: Locale) -> String? {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name == label || name == labelAsRead(locale: locale) ? nil : name
    }
}

private struct ClashTowerNameEditor: View {
    let title: String
    let initialName: String
    @State private var name: String
    let save: (String) async throws -> Void
    let close: () -> Void
    @State private var busy = false
    @State private var error: String?
    @Environment(\.clashInsideProductModalPresentation) private var insideProductModal
    init(title: String, name: String, save: @escaping (String) async throws -> Void, close: @escaping () -> Void) {
        self.title = title; initialName = name; _name = State(initialValue: name); self.save = save; self.close = close
    }
    private func commit(_ completion: @escaping (Bool) -> Void = { _ in }) {
        guard !busy, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { completion(false); return }
        busy = true; error = nil
        Task { @MainActor in defer { busy = false }; do { try await save(name); completion(true) } catch { self.error = ClashTowerRulesErrorText.describe(error); completion(false) } }
    }
    var body: some View {
        Form { Section("Scheme Name") { TextField("Name", text: $name).accessibilityIdentifier("configuration.rules.copy.name") }; if let error { Text(verbatim: error).foregroundStyle(.orange) } }
            .clashPageTitle(.copy(title)).disabled(busy)
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: close) }
                ToolbarItem(placement: .confirmationAction) { Button { commit() } label: { ClashActionProgressLabel(.copy("Save"), isBusy: busy) }.disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .clashRegistersDeparture(isDirty: name != initialName, isBusy: busy,
                whySaveIsBlocked: { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .copy("Enter a name.") : nil },
                save: { commit($0) }, discard: { name = initialName })
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if insideProductModal {
                    ClashModalActionBar(primaryTitle: "Save", primaryDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, isBusy: busy, onPrimary: { commit() })
                }
            }
    }
}

 
 
 
 
 
 
public struct ClashTowerLocalRuleEditor: View {
     
    enum Kind: String, CaseIterable, Identifiable { case link, manual; var id: String { rawValue } }
    let value: ConfigurationLocalRuleSet?
    let options: ClashRulePolicyOptions
    let palette: ClashProductPalette
     
     
    let buildRule: (String?, @escaping (String) -> Void) -> AnyView
     
     
     
    let createGroup: ((@escaping (String?) -> Void) -> AnyView)?
    let save: (String, String, String) async throws -> Void
    let close: () -> Void
     
    let confirmTitle: String
     
    let attaches: Bool
    @State private var name: String
    @State private var kind: Kind
     
    @State private var input: String
     
    @State private var lines: [String]
    @State private var policy: String
    @State private var pickingPolicy = false
    @State private var addingRule = false
     
     
    private struct LineRoute: Equatable { let index: Int }
    @State private var openLine: LineRoute?
    @State private var busy = false
    @State private var error: String?
    @Environment(\.clashInsideProductModalPresentation) private var insideProductModal
    private let initialPolicy: String
    public init(value: ConfigurationLocalRuleSet?, policy: String, options: ClashRulePolicyOptions, palette: ClashProductPalette,
                buildRule: @escaping (String?, @escaping (String) -> Void) -> AnyView,
                createGroup: ((@escaping (String?) -> Void) -> AnyView)? = nil,
                confirmTitle: String = "Save", attaches: Bool = true, prefill: (name: String, link: String)? = nil,
                save: @escaping (String, String, String) async throws -> Void, close: @escaping () -> Void) {
        self.value = value; self.options = options; self.palette = palette; self.buildRule = buildRule; self.createGroup = createGroup; self.save = save; self.close = close
        self.confirmTitle = confirmTitle; self.attaches = attaches
        self.initialPolicy = policy
        let stored = value?.input ?? ""
        let link = Self.looksLikeLink(stored)
        _name = State(initialValue: prefill?.name ?? value?.name ?? ""); _policy = State(initialValue: policy)
        _kind = State(initialValue: prefill != nil || link ? .link : .manual)
        _input = State(initialValue: prefill?.link ?? (link ? stored : ""))
        _lines = State(initialValue: link ? [] : Self.lines(of: stored))
    }
    static func looksLikeLink(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.contains("\n") && (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"))
    }
     
     
    static func lines(of input: String) -> [String] {
        input.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("//") }
    }
    private var contents: String { kind == .link ? input : lines.joined(separator: "\n") }
    private var ready: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (!attaches || !policy.isEmpty)
            && (kind == .link ? Self.looksLikeLink(input) : !lines.isEmpty)
    }
    private func commit(_ completion: @escaping (Bool) -> Void = { _ in }) {
        guard !busy, ready else { completion(false); return }
        busy = true; error = nil
        Task { @MainActor in defer { busy = false }; do { try await save(name, contents, policy); completion(true) } catch { self.error = ClashTowerRulesErrorText.describe(error); completion(false) } }
    }
    public var body: some View {
        Form {
            Section { TextField("Name", text: $name, prompt: Text(clash: .copy("e.g. 🎬 Netflix"))).accessibilityIdentifier("configuration.rules.set.name") }
            Section {
                Picker("Rules From", selection: $kind) {
                    Text("Link").tag(Kind.link)
                    Text("Manual").tag(Kind.manual)
                }.pickerStyle(.segmented).accessibilityIdentifier("configuration.rules.set.kind")
                if kind == .link {
                    TextField("Link", text: $input, prompt: Text(verbatim: "https://"))
                        .clashRuleSetLinkInput()
                        .accessibilityIdentifier("configuration.rules.set.contents")
                } else {
                    if lines.isEmpty {
                         
                         
                        Text("No rules yet. Tap Add Rule and build them one at a time. The policy chosen below applies to all of them.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("configuration.rules.set.empty")
                    }
                     
                     
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Button { openLine = LineRoute(index: index) } label: {
                            ConfigurationRuleRow(line, hasTarget: false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("configuration.rules.set.rule.row")
                    }
                    .onDelete { offsets in lines.remove(atOffsets: offsets) }
                    ClashAddRow(Text(clash: .copy("Add Rule"))) { addingRule = true }
                        .accessibilityIdentifier("configuration.rules.set.rule.add")
                }
            } header: { Text("Rules") } footer: {
                Text(kind == .link
                    ? "A text, YAML or MRS rule set the app downloads and keeps updated."
                    : "Add the rules this set matches. The policy is chosen below, not written on each rule.")
            }
            if attaches {
            Section {
                Button { pickingPolicy = true } label: {
                    HStack {
                        Text("Policy").foregroundStyle(.primary)
                        Spacer()
                        Text(verbatim: policy).foregroundStyle(.secondary).lineLimit(1)
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("configuration.rules.set.policy")
            } footer: { Text("Traffic matching these rules goes to this policy. Saving adds the rule set to the current rules.") }
            }
            if let error { Text(verbatim: error).foregroundStyle(.orange) }
        }.disabled(busy).clashPageTitle(.copy(value == nil ? "New Rule Set" : "Edit Rule Set"))
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close).disabled(busy).accessibilityIdentifier("configuration.rules.set.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { commit() } label: { ClashActionProgressLabel(.copy(confirmTitle), isBusy: busy) }
                        .disabled(busy || !ready)
                        .accessibilityIdentifier("configuration.rules.set.confirm")
                }
            }
             
             
            .clashRegistersDeparture(
                isDirty: name != (value?.name ?? "") || policy != initialPolicy
                    || kind != (Self.looksLikeLink(value?.input ?? "") ? .link : .manual)
                    || input != (Self.looksLikeLink(value?.input ?? "") ? (value?.input ?? "") : "")
                    || lines != (Self.looksLikeLink(value?.input ?? "") ? [] : Self.lines(of: value?.input ?? "")),
                isBusy: busy, whySaveIsBlocked: { ready ? nil : ClashDepartureSaveAnswer.incomplete }, save: { commit($0) },
                discard: {
                    name = value?.name ?? ""; policy = initialPolicy
                    let stored = value?.input ?? ""; let link = Self.looksLikeLink(stored)
                    kind = link ? .link : .manual; input = link ? stored : ""; lines = link ? [] : Self.lines(of: stored)
                }
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if insideProductModal {
                    ClashModalActionBar(primaryTitle: confirmTitle, primaryDisabled: !ready, isBusy: busy, onPrimary: { commit() })
                }
            }
            .background {
                ClashRoutedViewDestination(isPresented: $pickingPolicy) {
                    ClashRulePolicyPickerView(
                        title: "Select Policy",
                        builtIns: ClashRulePolicyBuiltIns.ruleSet,
                        axPrefix: "configuration.rules.set.policy",
                        offersGlobal: false,
                        options: options,
                        current: policy,
                        createGroup: createGroup,
                        icon: { symbol in Image(systemName: symbol.drawableName) }
                    ) { policy = $0; pickingPolicy = false }
                    .clashPushedDetailPage()
                }
                ClashRoutedViewDestination(isPresented: $addingRule) {
                    buildRule(nil) { raw in lines.append(raw); addingRule = false }
                        .clashPushedDetailPage()
                }
                ClashRoutedViewDestination(isPresented: Binding(get: { openLine != nil },
                                                               set: { if !$0 { openLine = nil } })) {
                    if let index = openLine?.index, lines.indices.contains(index) {
                        buildRule(lines[index]) { raw in
                            if lines.indices.contains(index) { lines[index] = raw }
                            openLine = nil
                        }
                        .clashPushedDetailPage()
                    }
                }
            }
    }
}

 
enum ClashTowerRulesUXTestSeams {
    static func looksLikeLink(_ input: String) -> Bool { ClashTowerLocalRuleEditor.looksLikeLink(input) }
    static var blankGroup: ConfigurationRuleDraft.Group { ClashTowerRuleCustomizationView.blankGroup }
}

private extension View {
     
    @ViewBuilder
    func clashRuleSetLinkInput() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }
}

 
 
 
 
public enum ClashTowerGroupIcon {
    public static func read(_ document: OrderedJSON) -> String {
        if case .string(let value) = document.topLevelValue("icon") { return value }
        return ""
    }

    public static func apply(_ icon: String, to document: OrderedJSON) -> OrderedJSON {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? document.removingTopLevel("icon") : document.settingTopLevel("icon", to: .string(trimmed))
    }
}

 
 
 
 
 
public enum ClashTowerGroupIconEcho: Equatable {
    case emoji(String)
    case symbol(ClashSymbol)
    case image(host: String)
    case nothingDraws

    public static func of(_ icon: String) -> ClashTowerGroupIconEcho? {
        switch ClashProxyGroupIconKind.of(icon) {
        case .none: return nil
        case .emoji(let value)?: return .emoji(value)
        case .symbol(let symbol)?: return .symbol(symbol)
        case .remote(let host)?: return .image(host: host)
        case .unrecognized?: return .nothingDraws
        }
    }

     
     
    public var label: String {
        switch self {
        case .emoji, .symbol: return "Shows as"
        case .image: return "Image on"
        case .nothingDraws: return "Saved with the group, but nothing draws it."
        }
    }
}

 
 
 
 
public struct ClashGroupIconImagesKey: EnvironmentKey {
    public static let defaultValue = false
}

extension EnvironmentValues {
    public var clashGroupIconImages: Bool {
        get { self[ClashGroupIconImagesKey.self] }
        set { self[ClashGroupIconImagesKey.self] = newValue }
    }
}

 
 
 
public enum ClashTowerGroupIconPresentation: Equatable {
    case emoji(String)
    case symbol(ClashSymbol)
    case image(String)

    public static func of(_ icon: String, showsImages: Bool) -> ClashTowerGroupIconPresentation? {
        switch ClashProxyGroupIconKind.of(icon) {
        case .emoji(let value)?: return .emoji(value)
        case .symbol(let symbol)?: return .symbol(symbol)
        case .remote?: return showsImages ? .image(icon.trimmingCharacters(in: .whitespacesAndNewlines)) : nil
        case .unrecognized?, .none: return nil
        }
    }
}

 
 
 
 
public struct ClashTowerGroupIconView<Fallback: View>: View {
    let icon: String
    let size: CGFloat
    @ViewBuilder let fallback: () -> Fallback
    @Environment(\.clashGroupIconImages) private var showsImages

     
     
    public init(icon: String, size: CGFloat, @ViewBuilder fallback: @escaping () -> Fallback) {
        self.icon = icon
        self.size = size
        self.fallback = fallback
    }

    public var body: some View {
        switch ClashTowerGroupIconPresentation.of(icon, showsImages: showsImages) {
        case .emoji(let value)?:
            Text(verbatim: value).font(.title3)
        case .symbol(let symbol)?:
            Image(systemName: symbol.drawableName).font(.body).foregroundStyle(.secondary)
        case .image(let address)?:
            ProxyGroupIconView(address: address, size: size, connected: true) {
                RoundedRectangle(cornerRadius: ClashTheme.Layout.proxyGroupIconCornerRadius, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: size, height: size)
                    .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: ClashTheme.Layout.proxyGroupIconCornerRadius, style: .continuous))
        case nil:
            fallback()
        }
    }
}

public struct ClashTowerGroupIconEchoRow: View {
    let icon: String

    public init(icon: String) { self.icon = icon }

    public var body: some View {
        if let echo = ClashTowerGroupIconEcho.of(icon) {
            HStack {
                Text(LocalizedStringKey(echo.label))
                    .foregroundStyle(echo == .nothingDraws ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                Spacer(minLength: 8)
                switch echo {
                case .emoji(let emoji): Text(verbatim: emoji).foregroundStyle(.secondary)
                case .symbol(let symbol): Image(systemName: symbol.drawableName).foregroundStyle(.secondary)
                case .image(let host): Text(verbatim: host).foregroundStyle(.secondary)
                case .nothingDraws: EmptyView()
                }
            }
            .font(.footnote)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("configuration.rules.group.icon.echo")
        }
    }
}

 
 
 
 
 
public enum ClashGroupLeaveOutNodes {
     
     
     
    public static let copyPath = "proxy-groups[*].exclude-filter"

     
     
    public static func pattern(of document: OrderedJSON) -> String {
        switch document.topLevelValue("exclude-filter") {
        case .string(let value)?, .scalar(let value)?: return value
        default: return ""
        }
    }

     
    private static func pieces(_ field: String) -> [String] { field.components(separatedBy: "`") }

     
    public static func holdsInfoNodeExample(_ field: String) -> Bool { pieces(field).contains(infoNodeExample) }

     
     
     
     
     
     
    public static func addingInfoNodeExample(to field: String) -> String {
        guard !holdsInfoNodeExample(field) else { return field }
        let kept = pieces(field).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return (kept + [infoNodeExample]).joined(separator: "`")
    }

     
    public struct Answer: Equatable, Sendable {
        public let pattern: String
        public let refusal: String?
        public init(pattern: String, refusal: String?) { self.pattern = pattern; self.refusal = refusal }
    }

     
     
    public static func refuses(_ answer: Answer?, _ pattern: String) -> Bool {
        guard let answer, answer.pattern == pattern else { return false }
        return answer.refusal != nil
    }

     
     
    public static func refusal(group: String) -> ClashDisplayText {
        .format("“%@”: Leave Out Nodes is written in a form the core can't read.", [group])
    }

     
     
    public static func answer(_ pattern: String, known: Answer?, check: ClashGroupPatternCheck?) async -> Answer {
        if let known, known.pattern == pattern { return known }
        guard let check, !pattern.isEmpty else { return .init(pattern: pattern, refusal: nil) }
        return .init(pattern: pattern, refusal: await check.check("exclude-filter", pattern))
    }
}

 
 
 
 
 
 
public struct ClashGroupPatternCheck: Sendable {
    public let check: @Sendable (_ key: String, _ pattern: String) async -> String?
    public init(_ check: @escaping @Sendable (_ key: String, _ pattern: String) async -> String?) { self.check = check }
}

 
 
private struct ClashTowerSelectionFeedback: ViewModifier {
    let trigger: Set<String>
    func body(content: Content) -> some View {
        if #available(iOS 17, macOS 14, tvOS 17, *) {
            content.sensoryFeedback(.success, trigger: trigger)
        } else {
            content
        }
    }
}

#if os(iOS)
 
 
 
 
struct ClashTowerReorderButton: View {
    @Environment(\.editMode) private var editMode
    let identifier: String

    var body: some View {
        Button {
            guard let editMode else { return }
            withAnimation { editMode.wrappedValue = editMode.wrappedValue.isEditing ? .inactive : .active }
        } label: {
            Text(clash: .copy(editMode?.wrappedValue.isEditing == true ? "Done" : "Reorder List"))
        }
        .accessibilityIdentifier(identifier)
    }
}
#endif

struct ClashTowerReorderMode: ViewModifier {
    var active = true
     
    var applies = true
    func body(content: Content) -> some View {
#if os(iOS)
        if applies {
            content.environment(\.editMode, .constant(active ? .active : .inactive))
        } else {
            content
        }
#else
        content
#endif
    }
}


private struct ClashTowerSearchPlacement: ViewModifier {
    @Binding var text: String
    let palette: ClashProductPalette
    func body(content: Content) -> some View {
        content.clashProductModalSearchable(text: $text, prompt: Text("Search Rules"))
#if os(iOS)
            .listStyle(.insetGrouped)
#endif
    }
}

 
 
 
struct ClashTowerRuleSummary: View {
    let row: ConfigurationRuleDraft.Row
    let palette: ClashProductPalette
     
     
     
    var ruleSetNames: [String: String] = [:]
     
    var opens = true
    var body: some View {
        ConfigurationRuleRow(row.raw, ruleSetNames: ruleSetNames, showsChevron: opens)
    }
}

 
 
struct ClashTowerRuleSearchSnapshot {
    var query = ""
    var rows: [ConfigurationRuleDraft.Row] = []
    func visible(for query: String, refreshing: Bool) -> [ConfigurationRuleDraft.Row] {
        self.query == query ? rows : []
    }
}

private struct ClashTowerInlineRules: View {
    let rows: [ConfigurationRuleDraft.Row]
    let version: ConfigurationSourceVersion
    let query: String
    let palette: ClashProductPalette
     
     
     
    var remove: ((UUID) -> Void)? = nil
     
     
     
    var move: ((IndexSet, Int) -> Void)? = nil
    var ruleSetNames: [String: String] = [:]
     
    var addRule: (() -> Void)? = nil
     
     
    var edit: ((UUID) -> Void)? = nil
    @State private var results = ClashTowerRuleSearchSnapshot()
    @State private var completedRequest: SearchRequest?

    private struct SearchRequest: Equatable {
        let version: ConfigurationSourceVersion
        let count: Int
        let query: String
    }
    private var request: SearchRequest {
        .init(version: version, count: rows.count,
              query: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    var body: some View {
        let current = request
        let searching = !current.query.isEmpty && completedRequest != current
        let visible = current.query.isEmpty ? rows : results.visible(for: current.query, refreshing: searching)
        Section {
            ForEach(visible) { row in
                if let edit {
                    Button { edit(row.id) } label: {
                        ClashTowerRuleSummary(row: row, palette: palette, ruleSetNames: ruleSetNames)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("configuration.rules.rule.row")
                    .deleteDisabled(row.isFinal)
                    .moveDisabled(row.isFinal || !current.query.isEmpty)
                } else {
                    ClashTowerRuleSummary(row: row, palette: palette, ruleSetNames: ruleSetNames, opens: false)
                        .deleteDisabled(row.isFinal)
                        .moveDisabled(row.isFinal || !current.query.isEmpty)
                }
            }
             
            .onDelete(perform: remove.map { remove -> (IndexSet) -> Void in { offsets in
                for index in offsets where visible.indices.contains(index) && !visible[index].isFinal { remove(visible[index].id) }
            } })
             
             
            .onMove(perform: move == nil ? nil : { offsets, destination in
                 
                 
                guard let move, current.query.isEmpty else { return }
                move(offsets, destination)
            })
            if searching && results.query != current.query { ProgressView("Searching…") }
            else if !searching && visible.isEmpty { Text("No results").foregroundStyle(.secondary) }
            if let addRule, current.query.isEmpty {
                ClashAddRow(Text(clash: .copy("Add Rule"))) { addRule() }
                    .accessibilityIdentifier("configuration.rules.rule.add")
            }
        } header: {
            HStack {
                Text("Current Rules")
                Spacer()
                Text(clash: .format("%@ rules", [String(visible.count)]))
            }
        } footer: { Text("Matched from top to bottom") }
        .task(id: current) {
            guard !current.query.isEmpty else { results = .init(); completedRequest = current; return }
            let source = rows, text = current.query
            let worker = Task.detached(priority: .userInitiated) {
                var result: [ConfigurationRuleDraft.Row] = []
                for row in source {
                    if Task.isCancelled { return result }
                    if row.raw.localizedCaseInsensitiveContains(text) { result.append(row) }
                }
                return result
            }
            let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled else { return }
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) {
                results = .init(query: current.query, rows: result); completedRequest = current
            }
        }
    }
}


 
public enum ClashConfigurationRuleLibrarySection: CaseIterable {
    case builtin, custom, subscription, file
    public var title: String {
        switch self {
        case .builtin: "Built-in Rules"
        case .custom: "My Rules"
        case .subscription: "From Profile URLs"
        case .file: "From Files"
        }
    }
    public func contains(_ source: ConfigurationSourceRecord) -> Bool {
        switch source.origin {
        case .subscription: return self == .subscription
        case .file: return self == .file
        case .customNodes: return self == .custom
        case .bundled: return false
        }
    }
    public func contains(_ scheme: ConfigurationRuleScheme, library: ConfigurationLibrarySnapshot) -> Bool {
         
         
         
         
         
        if let baseID = scheme.ownViewBaseID, baseID != scheme.id,
           let base = ConfigurationBuiltins.schemes.first(where: { $0.id == baseID })
               ?? library.rules.first(where: { $0.id == baseID }) {
            if scheme.rulesFromSchemeID == nil, ConfigurationBuiltins.isNative(baseID) { return self == .custom }
            return contains(base, library: library)
        }
        if scheme.baseSchemeID.map(ConfigurationBuiltins.isNative) == true { return self == .custom }
        let base = scheme.baseSchemeID.flatMap { id in
            ConfigurationBuiltins.schemes.first { $0.id == id } ?? library.rules.first { $0.id == id }
        } ?? scheme
        switch base.kind {
        case .builtin: return self == .builtin
         
         
        case .community: return false
        case .custom: return self == .custom
        case .supplied, .imported:
            return library.sources.first { $0.id == base.sourceID }.map { contains($0) } ?? (self == .file)
        }
    }
}

extension ClashRulePolicyBuiltIns {
     
     
     
     
     
    public static let ruleSet: [(name: String, caption: String)] =
        rule.filter { ConfigurationRuleTargetCandidates.builtinPolicies.contains($0.name) }
}

 
 
 
 
 
 
 
 
 
struct ClashLibraryUpdateBar: View {
    let progress: String?
    let status: String?
    let failed: Bool
    let details: (() -> Void)?
    let dismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: ClashTheme.Spacing.compact) {
            if progress != nil {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: (failed ? ClashSymbol.exclamationmarkTriangleFill : .checkmarkCircleFill).rawValue)
                    .foregroundStyle(failed ? Color.orange : Color.green)
                    .accessibilityHidden(true)
            }
            Text(verbatim: progress ?? status ?? "")
                .font(.footnote).foregroundStyle(.secondary)
                .lineLimit(2).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("configuration.library.rules.update-bar.text")
            if let details {
                Button(action: details) {
                    Text("Details").frame(minHeight: ClashTheme.Control.minimumHitTarget).contentShape(Rectangle())
                }
                .font(.footnote).buttonStyle(.borderless)
                .accessibilityIdentifier("configuration.library.rules.update-bar.details")
            }
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: ClashSymbol.xmark.rawValue).font(.footnote.weight(.semibold))
                        .frame(minWidth: ClashTheme.Control.minimumHitTarget, minHeight: ClashTheme.Control.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .accessibilityLabel(ClashCopy.key("Dismiss"))
                .accessibilityIdentifier("configuration.library.rules.update-bar.dismiss")
            }
        }
         
        .transaction { $0.animation = nil }
        .padding(.leading, 20).padding(.trailing, 8)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Rectangle().fill(.bar)
                Divider()
            }
             
             
             
             
             
            .ignoresSafeArea(edges: [.bottom, .horizontal])
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("configuration.library.rules.update-bar")
    }
}

 
 
 
 
 
 
private struct ClashRuleSetRowUpdate: ViewModifier {
    let entry: ConfigurationCollectionEntry
    let enabled: Bool
    let update: ((ConfigurationCollectionEntry) -> Void)?

    private var offered: Bool {
        update != nil && entry.collection.type == "http" && entry.source.isRetainedSnapshot != true
    }

    func body(content: Content) -> some View {
        if offered, let update {
            content
                .contextMenu {
                    Button { update(entry) } label: {
                        Label(ClashCopy.key("Update"), systemImage: ClashSymbol.arrowClockwise.rawValue)
                    }
                    .disabled(!enabled)
                    .accessibilityIdentifier("configuration.collection.update.\(entry.source.id).\(entry.collection.name)")
                }
        } else {
            content
        }
    }
}
