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
        refreshAll: (() async -> Void)? = nil) {
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
    private func displayLabel(_ scheme: ConfigurationRuleScheme) -> String {
        let id = scheme.id
        if id == ConfigurationBuiltins.basicRuleID { return ClashCopy.string("Default Configuration", locale: locale) }
        if id == ConfigurationBuiltins.lazyRuleID { return ClashCopy.string("Lazy Configuration", locale: locale) }
        if scheme.baseSchemeID.map(ConfigurationBuiltins.isNative) == true {
            return scheme.label + " · " + ClashCopy.string("Custom", locale: locale)
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
                        section(group.title, items: items, entries: entries)
                    }
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
        .modifier(ClashLibraryTabTitle(isCenterSection: isCenterSection, standalone: .copy("Manage Rule Schemes")))
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
            let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, name != renaming.label { rename?(renaming.id, name) }
        }
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
                    count: ClashConfigurationSourceCopy.ruleSummary(record(scheme), locale: locale), showsInfo: showsInfo)
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
                    Button { renameText = scheme.label; renaming = scheme } label: {
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
    public init(group: ConfigurationRuleDraft.Group, index: Int, all: [ConfigurationRuleDraft.Group],
                nodeSections: [ConfigurationRuleTargetCandidates.Section], save: @escaping (OrderedJSON) async throws -> Void) {
        self.group = group; self.index = index; self.all = all; self.nodeSections = nodeSections; self.save = save
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
    case all, rules, groups, ruleSets, subRules
}

 
 
 
 
public enum ClashTowerSingleObject: Equatable, Sendable {
     
    case group(String)
}

 
 
 
public enum ClashTowerListOpening: Equatable, Sendable {
    case list, reordering, adding
}

 
 
final class ClashTowerSubRulesBox: ObservableObject {
    @Published var subRules: [ConfigurationRuleDraft.SubRule] = []
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
     
     
    @State private var notice: ClashDisplayText?
    @State private var modal: Modal?
    @State private var confirmsReset = false
     
     
    @State private var renaming = false
    @State private var renameText = ""
    @Environment(\.locale) private var locale
    @State private var deletingLocal: ConfigurationLocalRuleSet?
    @State private var deletingGroup: UUID?
    @State private var confirmsLeave = false
    private let pushed: Bool
    private let focus: ClashTowerRuleFocus
     
     
     
     
    private let savesEachChange: Bool
     
     
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
    @AppStorage("clash.configuration.ruleGroupEmoji") private var emojis = true
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
    private enum Modal: String, Identifiable { case identity, group, local, copy, manual, rule, subRule; var id: String { rawValue } }
    @StateObject private var subRulesBox = ClashTowerSubRulesBox()
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
        rename: ((String, String) async throws -> Void)? = nil) {
        self.rename = rename
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
        AnyView(ClashTowerGroupEditor(group: ClashTowerGroupEditor.blankGroup, all: draft.groups, identityOnly: false, nodeSections: nodeSections, save: { value in
            try await apply { snapshot in var changed = snapshot; try changed.setGroup(value, groupID: nil); return changed }
            var name = ""
            if case .string(let value) = value.topLevelValue("name") { name = value }
            done(name.isEmpty ? nil : name)
        }, close: { done(nil) }))
    }
     
     
     
    @ViewBuilder
    private var trailingButtons: some View {
        if focus != .all {
            if autosaving {
                ProgressView().accessibilityIdentifier("configuration.rules.focus.saving")
            }
            Button { addToFocus() } label: { Image(systemName: ClashSymbol.plus.rawValue) }
                .accessibilityLabel(Text(ClashCopy.key(addTitle)))
                .accessibilityIdentifier("configuration.rules.focus.add")
                .disabled(busy)
        }
        if focus == .all {
            Button {
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { reordering.toggle() }
            } label: { ClashActionProgressLabel(.copy(reordering ? "Done" : "Edit"), isBusy: busy && pushed) }.foregroundStyle(.tint).disabled(busy)
        } else if focus != .ruleSets {
             
             
             
            #if os(iOS)
            ClashTowerReorderButton(identifier: "configuration.rules.focus.reorder")
            #endif
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
                    groupPage(ClashTowerGroupPageRequest(group: group, index: index, all: draft.groups, nodeSections: sections,
                                                        save: { value in try await saveGroup(value, id: group.id) }))
                }
                    .clashPushedDetailPage()
                    .clashNativePushBoundary()
            } label: { label() }
        } else {
            Button { groupID = group.id; modal = .group } label: { label() }.buttonStyle(.plain)
        }
    }
     
     
    private var holdsUnsaved: Bool { savesEachChange ? hasUnsavedChanges && !autosaving : hasUnsavedChanges }
    private var pageTitle: String {
        switch focus {
        case .all: "Rule Customization"
        case .rules: "Rules"
        case .groups: "Policy Groups"
        case .ruleSets: "Rule Sets"
        case .subRules: "Sub-rules"
        }
    }
    private var addTitle: String {
        switch focus {
        case .rules: "Add Rule"
        case .groups: "Add Policy Group"
        case .ruleSets: "New Rule Set"
        case .subRules: "Add Sub-rule"
        case .all: "Add"
        }
    }
     
    private func addToFocus() {
        switch focus {
        case .rules: ruleID = nil; open(.rule)
        case .groups: groupID = nil; modal = .group
        case .ruleSets: localID = nil; open(.local)
        case .subRules: modal = .subRule
        case .all: break
        }
    }
     
     
     
    private func changeSubRules(_ transform: @escaping @Sendable (inout ConfigurationRuleDraft) throws -> Void) {
        Task { @MainActor in
            do {
                try await apply { current in var value = current; try transform(&value); return value }
            } catch {
                self.error = ClashConfigurationSubRuleCopy.message(error, locale: locale)
            }
        }
    }
     
     
    @ViewBuilder
    private var subRulesSection: some View {
        if !draft.subRulesEditable {
            Section { Text(clash: .copy("These sub-rules can only be changed in the source.")).foregroundStyle(.secondary) }
        }
        Section {
            ForEach(draft.subRules) { subRule in
                NavigationLink {
                    subRulePage(subRule.id)
                        .clashPushedDetailPage()
                        .clashNativePushBoundary()
                } label: {
                    HStack {
                        Text(verbatim: subRule.name)
                        Spacer()
                        Text(verbatim: String(subRule.rows.count)).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("configuration.rules.subrule.row")
            }
            .onDelete(perform: reorderingAList ? nil : { offsets in
                let ids = offsets.map { draft.subRules[$0].id }
                changeSubRules { value in for id in ids { try value.removeSubRule(id) } }
            })
            .onMove { from, to in changeSubRules { $0.moveSubRules(fromOffsets: from, toOffset: to) } }
        }
    }
    private func subRulePage(_ id: UUID) -> ClashTowerSubRulePage {
        ClashTowerSubRulePage(box: subRulesBox, subRuleID: id, palette: palette, ruleSetNames: ruleSetNames,
            builder: { editing, accept in
                ruleEditor(.init(editing: editing, draft: draft, options: sheetOptions, showsTarget: true, createGroup: nil), accept)
            },
            rename: { name in changeSubRules { try $0.renameSubRule(id, to: name) } },
            setRow: { raw, rowID in changeSubRules { try $0.setSubRuleRow(raw, rowID: rowID, in: id) } },
            delete: { rows in changeSubRules { $0.removeSubRuleRows(rows, in: id) } },
            move: { from, to in changeSubRules { $0.moveSubRuleRows(fromOffsets: from, toOffset: to, in: id) } })
    }
    private var visibleGroups: [ConfigurationRuleDraft.Group] { draft.groups.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.type.localizedCaseInsensitiveContains(search) } }
    private var entries: [ConfigurationRuleCatalogEntry] { ConfigurationRuleCatalog.builtIn.entries.filter { (category == nil || $0.category == category) && $0.matches(search) } }
    public var body: some View {
        root
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: pushed ? .primaryAction : .cancellationAction) {
                 
                if single == nil {
                    Menu {
                        Toggle("Show Group Icons", isOn: $emojis).accessibilityIdentifier("configuration.rules.emojis")
                        if rename != nil {
                            Button { renameText = draft.label; renaming = true } label: { Label("Rename…", systemImage: ClashSymbol.pencil.rawValue) }
                                .accessibilityIdentifier("configuration.rules.rename")
                        }
                        Button("Edit Rules Source") { modal = .manual }
                        Button("Save as New Scheme") { modal = .copy }
                        Divider()
                        Button("Restore Initial Rules", role: .destructive) { confirmsReset = true }
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
        .onChange(of: draft.subRules) { subRulesBox.subRules = $0 }
        .onAppear {
            subRulesBox.subRules = draft.subRules
             
             
            guard focus != .all, !opened else { return }
            opened = true
            switch opening {
            case .adding: addToFocus()
            case .reordering:
                #if os(iOS)
                if focus != .ruleSets { listEditMode?.wrappedValue = .active }
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
            let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let rename, !name.isEmpty, name != draft.label else { return }
            let id = draft.schemeID
            perform {
                try await rename(id, name)
                Self.takeRename(name, draft: &draft, baseline: &baseline)
            }
        }
        .clashDeleteConfirmation(presenting: $deletingGroup, name: { id in draft.groups.first(where: { $0.id == id })?.name ?? "" },
            actionTitle: .copy("Delete Rule Group"),
            message: { _ in .copy("This group and its associated rules will be removed from the current scheme.") },
            identifier: "configuration.rules.group.delete.confirm") { id in
                mutate { snapshot in var value = snapshot; try value.deleteRoutingGroup(id); return value }
            }
        .clashDeleteConfirmation(presenting: $deletingLocal, name: \.name,
            actionTitle: .copy("Delete Rule Set"),
            message: { _ in .copy("This local rule set will be deleted. Rule schemes in the library will also remove rules added from it.") },
            identifier: "configuration.rules.local.delete.confirm") { item in
                perform {
                    let updated = try await deleteLocal(item.id)
                    try await receiveHostWrite(updated.0) { scheme in scheme.removeRuleSet("local-" + item.id) }
                    localSets = updated.1
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
            return AnyView(groupPage(ClashTowerGroupPageRequest(group: group, index: index, all: draft.groups,
                                                               nodeSections: nodeSections,
                                                               save: { value in try await saveGroup(value, id: group.id) }))
                .id(group.id)
                .onAppear { if singleGroupID == nil { singleGroupID = group.id } })
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
            if shows(.groups) {
            Section {
                ForEach(visibleGroups) { group in
                    groupRow(group) {
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
                        .accessibilityIdentifier("configuration.rules.group.row")
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .moveDisabled(!search.isEmpty)
                        .contextMenu {
                            Button { groupID = group.id; modal = .identity } label: {
                                Label { Text("Edit Name and Icon") } icon: { Image(systemName: ClashSymbol.pencil.rawValue) }
                            }
                            Button(role: .destructive) { deletingGroup = group.id } label: {
                                Label { Text("Delete") } icon: { Image(systemName: ClashSymbol.trash.rawValue) }
                            }
                        }
                         
                         
                         
                        .clashSwipeToDelete(reorderingAList ? nil : { deletingGroup = group.id })
                        .accessibilityAction(named: Text("Edit Name and Icon")) { groupID = group.id; modal = .identity }
                }.onDelete(perform: reorderingAList ? nil : { offsets in
                    guard let index = offsets.first, visibleGroups.indices.contains(index) else { return }
                    deletingGroup = visibleGroups[index].id
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
            } header: { HStack { Text("Policy Groups"); Spacer(); Text(clash: .format("%@ groups", [String(visibleGroups.count)])) } }
            }
            if focus == .subRules { subRulesSection }
             
             
             
            if focus == .ruleSets || focus == .all { localRuleSetsSection }
            if focus == .ruleSets || (focus == .all && reordering) {
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
            if insideProductModal {
                 
                 
                Section("More") {
                    Toggle("Show Group Icons", isOn: $emojis).accessibilityIdentifier("configuration.rules.emojis")
                    Button("Edit Rules Source") { modal = .manual }
                    Button("Save as New Scheme") { modal = .copy }
                    Button("Restore Initial Rules", role: .destructive) { confirmsReset = true }
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
            actionDisabled: busy,
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
            change { value in var value = value; value.removeRuleSet(key); return value }
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
            } catch { self.error = ClashTowerRulesErrorText.describe(error) }
        }
    }
    private func toggleLocal(_ item: ConfigurationLocalRuleSet) {
        let key = "local-" + item.id
        let removing = installedRuleSets.contains(key)
        change { snapshot in
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
    private func change(_ transform: @escaping @Sendable (ConfigurationRuleDraft) throws -> ConfigurationRuleDraft) {
        Task { @MainActor in
            do { try await apply(transform) } catch { self.error = ClashTowerRulesErrorText.describe(error) }
        }
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
            groupEditor(identityOnly: kind == .identity, adding: kind == .group)
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
        case .subRule:
            ClashTowerSubRuleNameForm(taken: Set(draft.subRules.map(\.name))) { name in
                changeSubRules { _ = try $0.addSubRule(named: name) }
                modal = nil
            } close: { modal = nil }
        case .copy:
             
             
            ClashTowerNameEditor(title: "Save as New Scheme", name: draft.label + " · " + ClashCopy.string("Custom", locale: locale), save: { name in try await copy(draft, name); modal = nil; hasUnsavedChanges = false; close() }, close: { modal = nil })
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
    private func groupEditor(identityOnly: Bool, adding: Bool) -> some View {
        if let id = groupID, let group = draft.groups.first(where: { $0.id == id }) {
            ClashTowerGroupEditor(group: group, all: draft.groups, identityOnly: identityOnly, nodeSections: nodeSections,
                save: { (value: OrderedJSON) async throws -> Void in try await saveGroup(value, id: id) },
                close: { modal = nil }, savesEachChange: savesEachChange, groupTypes: groupTypes)
        } else if adding {
            ClashTowerGroupEditor(group: ClashTowerGroupEditor.blankGroup, all: draft.groups, identityOnly: false, nodeSections: nodeSections,
                save: { (value: OrderedJSON) async throws -> Void in try await saveGroup(value, id: nil) },
                close: { modal = nil }, groupTypes: groupTypes)
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
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; error = nil
        Task { @MainActor in defer { busy = false }; do { try await operation() } catch { self.error = ClashTowerRulesErrorText.describe(error) } }
    }
}

 
 
 
 
struct ClashTowerSubRulePage: View {
    @ObservedObject var box: ClashTowerSubRulesBox
    let subRuleID: UUID
    let palette: ClashProductPalette
    let ruleSetNames: [String: String]
    let builder: (ClashTowerRuleEditing?, @escaping (String, Bool, String) -> Void) -> AnyView
    let rename: (String) -> Void
    let setRow: (String, UUID?) -> Void
    let delete: (Set<UUID>) -> Void
    let move: (IndexSet, Int) -> Void
    @State private var name = ""
    @State private var editing: Editing?
    #if os(iOS)
     
    @Environment(\.editMode) private var listEditMode
    #endif

     
    private var reordering: Bool {
        #if os(iOS)
        return listEditMode?.wrappedValue.isEditing == true
        #else
        return false
        #endif
    }

    struct Editing: Identifiable {
        let id = UUID()
        let rowID: UUID?
    }

    private var subRule: ConfigurationRuleDraft.SubRule? { box.subRules.first { $0.id == subRuleID } }

    var body: some View {
        List {
            Section {
                TextField("Name", text: $name)
                    .onSubmit { commitName() }
                    .accessibilityIdentifier("configuration.rules.subrule.name")
            }
            Section {
                ForEach(subRule?.rows ?? []) { row in
                    Button { editing = Editing(rowID: row.id) } label: {
                        ClashTowerRuleSummary(row: row, palette: palette, ruleSetNames: ruleSetNames)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("configuration.rules.subrule.rule.row")
                }
                .onDelete(perform: reordering ? nil : { offsets in
                    let rows = subRule?.rows ?? []
                    delete(Set(offsets.compactMap { rows.indices.contains($0) ? rows[$0].id : nil }))
                })
                .onMove { move($0, $1) }
            }
        }
        .navigationTitle(Text(verbatim: subRule?.name ?? name))
        .clashToolbarUnlessInPanel {
            ToolbarItemGroup(placement: .confirmationAction) {
                Button { editing = Editing(rowID: nil) } label: { Image(systemName: ClashSymbol.plus.rawValue) }
                    .accessibilityLabel(Text(ClashCopy.key("Add Rule")))
                    .accessibilityIdentifier("configuration.rules.subrule.rule.add")
                #if os(iOS)
                if (subRule?.rows.count ?? 0) > 1 {
                    ClashTowerReorderButton(identifier: "configuration.rules.subrule.reorder")
                }
                #endif
            }
        }
        .clashProductModal(item: $editing, role: .form) { edit in
            ClashSingleColumnNavigationContainer {
                let row = edit.rowID.flatMap { id in subRule?.rows.first { $0.id == id } }
                builder(row.map { ClashTowerRuleEditing(raw: $0.raw, isEnabled: true, note: "") }) { raw, _, _ in
                    setRow(raw, edit.rowID)
                    editing = nil
                }
            }.environment(\.clashProductModalDismiss, { editing = nil })
        }
        .onAppear { if name.isEmpty { name = subRule?.name ?? "" } }
        .onDisappear { commitName() }
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != subRule?.name else { return }
        rename(trimmed)
    }
}

 
private struct ClashTowerSubRuleNameForm: View {
    let taken: Set<String>
    let add: (String) -> Void
    let close: () -> Void
    @State private var name = ""

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name).accessibilityIdentifier("configuration.rules.subrule.new-name")
            }
        }
        .clashPageTitle("Add Sub-rule")
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: close) }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { add(trimmed) }
                    .disabled(trimmed.isEmpty || taken.contains(trimmed))
                    .accessibilityIdentifier("configuration.rules.subrule.new-add")
            }
        }
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

private struct ClashTowerLocalRuleEditor: View {
     
    enum Kind: String, CaseIterable, Identifiable { case link, manual; var id: String { rawValue } }
    let value: ConfigurationLocalRuleSet?
    let options: ClashRulePolicyOptions
    let palette: ClashProductPalette
     
     
    let buildRule: (String?, @escaping (String) -> Void) -> AnyView
     
     
     
    let createGroup: ((@escaping (String?) -> Void) -> AnyView)?
    let save: (String, String, String) async throws -> Void
    let close: () -> Void
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
    init(value: ConfigurationLocalRuleSet?, policy: String, options: ClashRulePolicyOptions, palette: ClashProductPalette,
         buildRule: @escaping (String?, @escaping (String) -> Void) -> AnyView,
         createGroup: ((@escaping (String?) -> Void) -> AnyView)? = nil,
         save: @escaping (String, String, String) async throws -> Void, close: @escaping () -> Void) {
        self.value = value; self.options = options; self.palette = palette; self.buildRule = buildRule; self.createGroup = createGroup; self.save = save; self.close = close
        self.initialPolicy = policy
        let stored = value?.input ?? ""
        let link = Self.looksLikeLink(stored)
        _name = State(initialValue: value?.name ?? ""); _policy = State(initialValue: policy)
        _kind = State(initialValue: link ? .link : .manual)
        _input = State(initialValue: link ? stored : "")
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
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !policy.isEmpty
            && (kind == .link ? Self.looksLikeLink(input) : !lines.isEmpty)
    }
    private func commit(_ completion: @escaping (Bool) -> Void = { _ in }) {
        guard !busy, ready else { completion(false); return }
        busy = true; error = nil
        Task { @MainActor in defer { busy = false }; do { try await save(name, contents, policy); completion(true) } catch { self.error = ClashTowerRulesErrorText.describe(error); completion(false) } }
    }
    var body: some View {
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
            if let error { Text(verbatim: error).foregroundStyle(.orange) }
        }.disabled(busy).clashPageTitle(.copy(value == nil ? "New Rule Set" : "Edit Rule Set"))
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: close).disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button { commit() } label: { ClashActionProgressLabel(.copy("Save"), isBusy: busy) }.disabled(busy || !ready) }
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
                    ClashModalActionBar(primaryTitle: "Save", primaryDisabled: !ready, isBusy: busy, onPrimary: { commit() })
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
    static var blankGroup: ConfigurationRuleDraft.Group { ClashTowerGroupEditor.blankGroup }
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

     
     
     
     
    @ViewBuilder
    func clashPatternInput() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }
}

 
 
 
 
 
 
 
 
enum ClashTowerGroupCandidates {
    static let builtinMembers = ["DIRECT", "REJECT"]

     
     
    static func offersSearch(_ nodeSections: [ConfigurationRuleTargetCandidates.Section]) -> Bool {
        nodeSections.contains { $0.kind != .providers }
    }

    static func available(
        groups: [String], excludingGroup: String,
        nodeSections: [ConfigurationRuleTargetCandidates.Section],
        selected: [String], query: String
    ) -> [ConfigurationRuleTargetCandidates.Section] {
        let taken = Set(selected)
        var sections = [
            ConfigurationRuleTargetCandidates.Section(id: "builtin", kind: .builtin, names: builtinMembers),
            ConfigurationRuleTargetCandidates.Section(id: "groups", kind: .groups, names: groups.filter { $0 != excludingGroup }),
        ]
         
        sections.append(contentsOf: nodeSections.filter { $0.kind != .providers })
        let offered = sections.compactMap { section -> ConfigurationRuleTargetCandidates.Section? in
            var seen = Set<String>()
             
            let names = section.names.filter { !taken.contains($0) && (section.kind == .builtin || !builtinMembers.contains($0)) }
                .filter { seen.insert($0).inserted }
            return names.isEmpty ? nil : ConfigurationRuleTargetCandidates.Section(id: section.id, kind: section.kind, sourceLabel: section.sourceLabel, names: names)
        }
        return ConfigurationRuleTargetCandidates(sections: offered).filtered(by: query).sections
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

struct ClashTowerGroupIconEchoRow: View {
    let icon: String

    var body: some View {
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

 
 
 
enum ClashTowerGroupForm {
     
     
     
    static func isValid(name: String, identityOnly: Bool, selected: [String], includeAll: Bool, base: OrderedJSON) -> Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if identityOnly || !selected.isEmpty || includeAll { return true }
        if case .array(let use)? = base.topLevelValue("use") { return !use.isEmpty }
        return false
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func members(of base: OrderedJSON, kind: String, selected: [String], includeAll: Bool, filter: String,
                        excludeFilter: String? = nil) -> OrderedJSON {
        var document = base
        let isOn: (String) -> Bool = { base.topLevelValue($0) == .scalar("true") }
        let has: (String) -> Bool = { base.topLevelValue($0) != nil }
        let flag: String
        if isOn("include-all") { flag = "include-all" }
        else if isOn("include-all-proxies") { flag = "include-all-proxies" }
        else if has("include-all") || !has("include-all-proxies") { flag = "include-all" }
        else { flag = "include-all-proxies" }
        let other = flag == "include-all" ? "include-all-proxies" : "include-all"
        document = document.settingTopLevel("type", to: .string(kind))
        if !selected.isEmpty || has("proxies") { document = document.settingTopLevel("proxies", to: .array(selected.map(OrderedJSON.string))) }
        if includeAll || has(flag) { document = document.settingTopLevel(flag, to: .scalar(includeAll ? "true" : "false")) }
        if !includeAll, has(other) { document = document.settingTopLevel(other, to: .scalar("false")) }
        if !filter.isEmpty || has("filter") { document = document.settingTopLevel("filter", to: .string(filter)) }
        if let excludeFilter, !excludeFilter.isEmpty || has("exclude-filter") {
            document = document.settingTopLevel("exclude-filter", to: .string(excludeFilter))
        }
        if kind == "url-test" || kind == "fallback", case .array(let use)? = document.topLevelValue("use"), !use.isEmpty,
           document.topLevelValue("url") == nil {
            document = document.settingTopLevel("url", to: .string("https://www.gstatic.com/generate_204"))
            if document.topLevelValue("interval") == nil { document = document.settingTopLevel("interval", to: .scalar("300")) }
        }
        return document
    }
}

extension ClashTowerGroupForm {
     
     
    struct Fields: Equatable {
        var name: String
        var icon: String
        var kind: String
        var selected: [String]
        var includeAll: Bool
        var filter: String
         
        var excludeFilter: String = ""
    }

     
     
    static func excludeFilter(of document: OrderedJSON) -> String {
        switch document.topLevelValue("exclude-filter") {
        case .string(let value)?, .scalar(let value)?: return value
        default: return ""
        }
    }

     
     
     
    static let excludeFilterCopyPath = "proxy-groups[*].exclude-filter"

     
    private static func pieces(_ field: String) -> [String] { field.components(separatedBy: "`") }

     
    static func holdsInfoNodeExample(_ field: String) -> Bool { pieces(field).contains(infoNodeExample) }

     
     
     
     
     
     
    static func addingInfoNodeExample(to field: String) -> String {
        guard !holdsInfoNodeExample(field) else { return field }
        let kept = pieces(field).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return (kept + [infoNodeExample]).joined(separator: "`")
    }

     
     
    struct PatternAnswer: Equatable {
        let pattern: String
        let refusal: String?
    }

     
     
    static func refuses(_ answer: PatternAnswer?, _ pattern: String) -> Bool {
        guard let answer, answer.pattern == pattern else { return false }
        return answer.refusal != nil
    }

     
     
    static func leaveOutNodesRefusal(group: String) -> ClashDisplayText {
        .format("“%@”: Leave Out Nodes is written in a form the core can't read.", [group])
    }

     
     
    static func answer(_ pattern: String, known: PatternAnswer?, check: ClashGroupPatternCheck?) async -> PatternAnswer {
        if let known, known.pattern == pattern { return known }
        guard let check, !pattern.isEmpty else { return .init(pattern: pattern, refusal: nil) }
        return .init(pattern: pattern, refusal: await check.check("exclude-filter", pattern))
    }

     
     
     
    static func afterRefusal(sent: Fields, saved: Fields, current: Fields) -> Fields {
        var back = current
        func putBack<Value: Equatable>(_ field: WritableKeyPath<Fields, Value>) {
            if sent[keyPath: field] != saved[keyPath: field], current[keyPath: field] == sent[keyPath: field] {
                back[keyPath: field] = saved[keyPath: field]
            }
        }
        putBack(\.name); putBack(\.icon); putBack(\.kind)
        putBack(\.selected); putBack(\.includeAll); putBack(\.filter); putBack(\.excludeFilter)
        return back
    }
}

 
 
 
 
 
 
public struct ClashGroupPatternCheck: Sendable {
    public let check: @Sendable (_ key: String, _ pattern: String) async -> String?
    public init(_ check: @escaping @Sendable (_ key: String, _ pattern: String) async -> String?) { self.check = check }
}

 
struct ClashTowerGroupPatternRefusal: ClashAuthoredError {
    let displayText: ClashDisplayText
}

private struct ClashGroupPatternCheckKey: EnvironmentKey {
    static let defaultValue: ClashGroupPatternCheck? = nil
}

public extension EnvironmentValues {
    var clashGroupPatternCheck: ClashGroupPatternCheck? {
        get { self[ClashGroupPatternCheckKey.self] }
        set { self[ClashGroupPatternCheckKey.self] = newValue }
    }
}

 
 
 
 
@MainActor
final class ClashTowerGroupWrites: ObservableObject {
    typealias Fields = ClashTowerGroupForm.Fields
     
    private(set) var saved: Fields
    @Published private(set) var isWriting = false
    private var owed = false
    private var runner: Task<Void, Never>?
     
     
     
     
     
    private var changes = 0
    private var refusedAt = -1

     
     
     
    private var closing: (() -> Void)?

    init(saved: Fields) {
        self.saved = saved
    }

     
     
     
     
     
     
    func change(current: @escaping () -> Fields, writable: @escaping (Fields) -> Bool,
                write: @escaping (Fields) async throws -> Void, took: @escaping () -> Void,
                refused: @escaping (Error, Fields) -> Void, closing close: (() -> Void)? = nil) {
        if let close { closing = close }
        changes += 1
        start(current: current, writable: writable, write: write, took: took, refused: refused)
    }

    private func start(current: @escaping () -> Fields, writable: @escaping (Fields) -> Bool,
                       write: @escaping (Fields) async throws -> Void, took: @escaping () -> Void,
                       refused: @escaping (Error, Fields) -> Void) {
        if runner != nil {
            owed = true
            return
        }
        let carries = changes
        let sent = current()
        guard writable(sent), sent != saved else { return closeIfAsked() }
        isWriting = true
        runner = Task { @MainActor [weak self] in
            do {
                try await write(sent)
                guard let self else { return }
                saved = sent
                if carries > refusedAt { took() }
            } catch {
                guard let self else { return }
                closing = nil
                refusedAt = changes
                refused(error, ClashTowerGroupForm.afterRefusal(sent: sent, saved: saved, current: current()))
            }
            guard let self else { return }
            isWriting = false
            runner = nil
            if owed {
                owed = false
                start(current: current, writable: writable, write: write, took: took, refused: refused)
            } else {
                closeIfAsked()
            }
        }
    }

    private func closeIfAsked() {
        guard runner == nil, let close = closing else { return }
        closing = nil
        close()
    }

     
    func waitForWrites() async {
        while let runner {
            await runner.value
        }
    }
}

private struct ClashTowerGroupEditor: View {
    let group: ConfigurationRuleDraft.Group
    let all: [ConfigurationRuleDraft.Group]
    let identityOnly: Bool

     
     
    private var pageName: String { identityOnly ? "Edit Name and Icon" : group.name.isEmpty ? "New Policy Group" : group.name }
     
     
     
    private var pageTitle: ClashDisplayText { identityOnly || group.name.isEmpty ? .copy(pageName) : .verbatim(pageName) }
     
     
    let nodeSections: [ConfigurationRuleTargetCandidates.Section]
    let save: (OrderedJSON) async throws -> Void
    let close: () -> Void
     
     
     
    let savesEachChange: Bool
     
    let groupTypes: [String]
    @State private var query = ""
    @State private var name: String
    @State private var icon: String
    @State private var kind: String
    @State private var selected: [String]
    @State private var includeAll: Bool
    @State private var filter: String
     
    @State private var excludeFilter: String
     
    @State private var excludeCheck: ClashTowerGroupForm.PatternAnswer?
    @Environment(\.clashGroupPatternCheck) private var patternCheck
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
     
     
    @State private var busy = false
    @StateObject private var writes: ClashTowerGroupWrites
    @State private var error: String?
    @Environment(\.clashInsideProductModalPresentation) private var insideProductModal
    @Environment(\.clashRuleTargetSearch) private var targetSearch
     
     
    @State private var searched: [ConfigurationRuleTargetCandidates.Section] = []
     
     
    static var blankGroup: ConfigurationRuleDraft.Group {
        .init(id: UUID(), document: .object([("name", .string("")), ("type", .string("select")), ("proxies", .array([]))]))
    }
    init(group: ConfigurationRuleDraft.Group, all: [ConfigurationRuleDraft.Group], identityOnly: Bool,
        nodeSections: [ConfigurationRuleTargetCandidates.Section] = [],
        save: @escaping (OrderedJSON) async throws -> Void, close: @escaping () -> Void, savesEachChange: Bool = false,
        groupTypes: [String] = []) {
        self.group = group; self.all = all; self.identityOnly = identityOnly; self.nodeSections = nodeSections; self.save = save; self.close = close
        self.savesEachChange = savesEachChange
        self.groupTypes = groupTypes
        _name = State(initialValue: group.name); _kind = State(initialValue: group.type)
        _icon = State(initialValue: ClashTowerGroupIcon.read(group.document))
        if case .array(let values) = group.document.topLevelValue("proxies") { _selected = State(initialValue: values.compactMap { if case .string(let value) = $0 { return value }; return nil }) }
        else { _selected = State(initialValue: []) }
        _includeAll = State(initialValue: group.document.topLevelValue("include-all") == .scalar("true") || group.document.topLevelValue("include-all-proxies") == .scalar("true"))
        if case .string(let value) = group.document.topLevelValue("filter") { _filter = State(initialValue: value) } else { _filter = State(initialValue: "") }
        _excludeFilter = State(initialValue: ClashTowerGroupForm.excludeFilter(of: group.document))
        let opened = ClashTowerGroupForm.Fields(
            name: _name.wrappedValue, icon: _icon.wrappedValue, kind: _kind.wrappedValue, selected: _selected.wrappedValue,
            includeAll: _includeAll.wrappedValue, filter: _filter.wrappedValue, excludeFilter: _excludeFilter.wrappedValue)
        _writes = StateObject(wrappedValue: ClashTowerGroupWrites(saved: opened))
    }
    private var fields: ClashTowerGroupForm.Fields {
        .init(name: name, icon: icon, kind: kind, selected: selected, includeAll: includeAll, filter: filter, excludeFilter: excludeFilter)
    }
    private func show(_ fields: ClashTowerGroupForm.Fields) {
        name = fields.name; icon = fields.icon; kind = fields.kind
        selected = fields.selected; includeAll = fields.includeAll; filter = fields.filter; excludeFilter = fields.excludeFilter
    }
     
    private func document(_ fields: ClashTowerGroupForm.Fields) -> OrderedJSON {
        var document = ClashTowerGroupIcon.apply(fields.icon, to: group.document.settingTopLevel("name", to: .string(fields.name)))
        if !identityOnly {
            document = ClashTowerGroupForm.members(of: document, kind: fields.kind, selected: fields.selected,
                                                   includeAll: fields.includeAll, filter: fields.filter,
                                                   excludeFilter: fields.excludeFilter)
        }
        return document
    }
     
     
     
    private func excludeRefusal(_ pattern: String) async -> String? {
        guard !identityOnly else { return nil }
        let answer = await ClashTowerGroupForm.answer(pattern, known: excludeCheck, check: patternCheck)
         
         
        if answer.pattern == excludeFilter { excludeCheck = answer }
        return answer.refusal
    }
     
    private var excludeRefusalShown: ClashDisplayText? {
        ClashTowerGroupForm.refuses(excludeCheck, excludeFilter)
            ? ClashTowerGroupForm.leaveOutNodesRefusal(group: name.isEmpty ? group.name : name) : nil
    }
     
     
    private var excludeFilterCopy: ConfigurationFieldCopy.Entry? {
        fieldCopy.entry(forPath: ClashTowerGroupForm.excludeFilterCopyPath, language: ConfigurationFieldCopy.Language(locale: locale))
    }
    private var excludeFilterTitle: String { excludeFilterCopy?.title ?? "exclude-filter" }
    private var originalSelected: [String] {
        guard case .array(let values) = group.document.topLevelValue("proxies") else { return [] }
        return values.compactMap { if case .string(let name) = $0 { return name }; return nil }
    }
    private var originalIncludeAll: Bool { group.document.topLevelValue("include-all") == .scalar("true") || group.document.topLevelValue("include-all-proxies") == .scalar("true") }
    private var originalFilter: String { if case .string(let value) = group.document.topLevelValue("filter") { return value }; return "" }
    private var originalExcludeFilter: String { ClashTowerGroupForm.excludeFilter(of: group.document) }
    private var dirty: Bool { name != group.name || icon != ClashTowerGroupIcon.read(group.document) || kind != group.type || selected != originalSelected || includeAll != originalIncludeAll || filter != originalFilter || excludeFilter != originalExcludeFilter }
    private var availableSections: [ConfigurationRuleTargetCandidates.Section] {
        ClashTowerGroupCandidates.available(
            groups: all.filter { $0.id != group.id }.map(\.name), excludingGroup: group.name,
            nodeSections: nodeSections + (query.isEmpty ? [] : searched), selected: selected, query: query
        )
    }
     
     
    private var typeChoices: [String] {
        groupTypes.contains(group.type) || group.type.isEmpty ? groupTypes : [group.type] + groupTypes
    }
    private var isNew: Bool { group.name.isEmpty }
    private var savesAsItGoes: Bool { savesEachChange && !isNew }
     
     
    private var valid: Bool {
        ClashTowerGroupForm.isValid(name: name, identityOnly: identityOnly, selected: selected, includeAll: includeAll, base: group.document)
            && (identityOnly || !ClashTowerGroupForm.refuses(excludeCheck, excludeFilter))
    }
     
     
     
    private func saveAsItGoes(closing: (() -> Void)? = nil) {
        guard savesAsItGoes else { return }
        writes.change(current: { fields }, writable: { [group, identityOnly] fields in
            ClashTowerGroupForm.isValid(name: fields.name, identityOnly: identityOnly, selected: fields.selected,
                                        includeAll: fields.includeAll, base: group.document)
                && (identityOnly || !ClashTowerGroupForm.refuses(excludeCheck, fields.excludeFilter))
        }, write: { fields in
             
             
            if await excludeRefusal(fields.excludeFilter) != nil {
                throw ClashTowerGroupPatternRefusal(displayText: ClashTowerGroupForm.leaveOutNodesRefusal(group: fields.name))
            }
            try await save(document(fields))
        }, took: {
            error = nil
        }, refused: { failure, back in
            error = failure is ClashTowerGroupPatternRefusal
                ? ClashErrorCopy.message(failure, locale: locale) : ClashTowerRulesErrorText.describe(failure)
            show(back)
        }, closing: closing)
    }

     
     
     
    private func doneOnTheList() {
        saveAsItGoes(closing: close)
    }
    private func sectionTitle(_ section: ConfigurationRuleTargetCandidates.Section) -> Text {
        switch section.kind {
        case .builtin: return Text("Built-in")
        case .groups: return Text("Policy Groups")
        case .source, .providers: return Text(verbatim: section.sourceLabel ?? section.id)
        }
    }
    var body: some View {
        Form {
            if identityOnly {
                Section("Name and Icon") {
                    TextField("Group Name", text: $name).onSubmit { saveAsItGoes() }.accessibilityIdentifier("configuration.rules.group.name")
                    TextField("Icon URL", text: $icon, prompt: Text(verbatim: "https://…")).autocorrectionDisabled().onSubmit { saveAsItGoes() }.accessibilityIdentifier("configuration.rules.group.icon")
                    ClashTowerGroupIconEchoRow(icon: icon)
                }
            } else {
                Section("Name and Icon") {
                    TextField("Group Name", text: $name).onSubmit { saveAsItGoes() }.accessibilityIdentifier("configuration.rules.group.name")
                    TextField("Icon URL", text: $icon, prompt: Text(verbatim: "https://…")).autocorrectionDisabled().onSubmit { saveAsItGoes() }.accessibilityIdentifier("configuration.rules.group.icon")
                    ClashTowerGroupIconEchoRow(icon: icon)
                }
                Section {
                    Picker("Group Type", selection: $kind) { ForEach(typeChoices, id: \.self) { Text(verbatim: $0).tag($0) } }.accessibilityIdentifier("configuration.rules.group.type")
                } footer: { Text("Changing the group type changes how routes are chosen.") }
                Section("Selected (in priority order)") {
                    ForEach(selected, id: \.self) { item in
                        HStack { Text(verbatim: item); Spacer(); Button { selected.removeAll { $0 == item } } label: { Image(systemName: "minus.circle").foregroundStyle(.red) }.buttonStyle(.borderless) }
                    }.onMove { selected.move(fromOffsets: $0, toOffset: $1) }
                }
                if ClashTowerGroupCandidates.offersSearch(nodeSections) || targetSearch != nil {
                    Section("Available") {
                        TextField("Search nodes", text: $query).accessibilityIdentifier("configuration.rules.group.search")
                    }
                }
                ForEach(availableSections) { section in
                    Section {
                        ForEach(section.names, id: \.self) { item in
                            Button { targetSearch?.recordUse(item); selected.append(item) } label: { HStack { Text(verbatim: item).foregroundStyle(.primary); Spacer(); Image(systemName: "plus.circle") }.contentShape(Rectangle()) }.buttonStyle(.plain)
                        }
                    } header: { sectionTitle(section) }
                }
                Section("Node Name Match") {
                    Toggle("Include all proxies", isOn: $includeAll).accessibilityIdentifier("configuration.rules.group.include-all")
                    TextField("Include filter", text: $filter).clashPatternInput().onSubmit { saveAsItGoes() }.accessibilityIdentifier("configuration.rules.group.filter")
                     
                     
                     
                    HStack {
                        Text(verbatim: excludeFilterTitle)
                        Spacer(minLength: ClashTheme.Spacing.compact)
                        TextField(text: $excludeFilter, prompt: excludeFilterCopy?.example.map { Text(verbatim: $0) }) { Text(verbatim: excludeFilterTitle) }.labelsHidden().clashPatternInput().multilineTextAlignment(.trailing).onSubmit { saveAsItGoes() }.accessibilityIdentifier("configuration.rules.group.exclude-filter")
                    }
                    if let refusal = excludeRefusalShown {
                        Text(clash: refusal).font(.footnote).foregroundStyle(.red)
                            .accessibilityIdentifier("configuration.rules.group.exclude-filter.refusal")
                    }
                    Button {
                        excludeFilter = ClashTowerGroupForm.addingInfoNodeExample(to: excludeFilter)
                        saveAsItGoes()
                    } label: { Text(clash: .copy("Leave Out Info Nodes")) }
                        .disabled(ClashTowerGroupForm.holdsInfoNodeExample(excludeFilter))
                        .accessibilityIdentifier("configuration.rules.group.exclude-filter.example")
                }
            }
            if let error { Text(verbatim: error).foregroundStyle(.orange) }
        }
        .modifier(ClashTowerReorderMode())
        .task(id: query) {
            guard let targetSearch, !query.isEmpty else { searched = []; return }
            try? await Task.sleep(nanoseconds: ClashRuleTargetSearchHook.settle)
            guard !Task.isCancelled else { return }
            let found = await targetSearch.sections(query, selected)
            if !Task.isCancelled { searched = found }
        }
         
         
        .task(id: excludeFilter) {
            guard patternCheck != nil, !identityOnly, !excludeFilter.isEmpty else { return }
            if excludeFilter != originalExcludeFilter {
                try? await Task.sleep(nanoseconds: ClashRuleTargetSearchHook.settle)
                guard !Task.isCancelled else { return }
            }
            _ = await excludeRefusal(excludeFilter)
        }
        .disabled(busy).clashPageTitle(pageTitle, watchAs: pageName)
         
        .onChange(of: kind) { _ in saveAsItGoes() }
        .onChange(of: selected) { _ in saveAsItGoes() }
        .onChange(of: includeAll) { _ in saveAsItGoes() }
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) {
                if !savesAsItGoes { Button("Cancel", action: close).disabled(busy) }
            }
            ToolbarItem(placement: .confirmationAction) {
                if savesAsItGoes {
                     
                    Button { doneOnTheList() } label: { Text(clash: .copy("Done")) }
                        .disabled(writes.isWriting || !valid)
                        .accessibilityIdentifier("configuration.rules.group.done")
                } else {
                    Button { commit() } label: { ClashActionProgressLabel(.copy("Save"), isBusy: busy) }.disabled(busy || !valid)
                }
            }
        }
        .onDisappear { saveAsItGoes() }
        .clashRegistersDeparture(isDirty: savesAsItGoes ? false : dirty, isBusy: busy || writes.isWriting, whySaveIsBlocked: { valid ? nil : ClashDepartureSaveAnswer.incomplete }, save: { commit($0) }, discard: { name = group.name; icon = ClashTowerGroupIcon.read(group.document); kind = group.type; selected = originalSelected; includeAll = originalIncludeAll; filter = originalFilter; excludeFilter = originalExcludeFilter })
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if insideProductModal {
                 
                 
                ClashModalActionBar(primaryTitle: "Save", primaryDisabled: !valid || writes.isWriting, isBusy: busy || writes.isWriting,
                                    onPrimary: { if savesAsItGoes { doneOnTheList() } else { commit() } })
            }
        }
    }
    private func commit(_ completion: @escaping (Bool) -> Void = { _ in }) {
        guard !busy, valid else { completion(false); return }
        busy = true; error = nil
        let fields = fields
        Task { @MainActor in
            defer { busy = false }
             
             
            if await excludeRefusal(fields.excludeFilter) != nil { completion(false); return }
            do {
                try await save(document(fields)); completion(true)
            } catch { self.error = ClashTowerRulesErrorText.describe(error); completion(false) }
        }
    }
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
            .onMove { offsets, destination in
                 
                 
                guard let move, current.query.isEmpty else { return }
                move(offsets, destination)
            }
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
