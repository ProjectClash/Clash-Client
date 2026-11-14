import ClashClientKit
import ClashClientUI
import SwiftUI

 
public enum ClashMacConfigurationCenterItem: Hashable, Sendable {
    case configuration(Profile.ID)
    case source(String)
    case scheme(String)
     
    case collection(ConfigurationCollection.ID)
}

 
public struct ClashMacConfigurationCenterListActions {
     
     
     
    public var addConfiguration: @MainActor () -> Void
    public var addSource: @MainActor (ClashMacSourceImportSheet.Tab) -> Void
    public var addScheme: @MainActor (ClashMacSourceImportSheet.Tab) -> Void
     
    public var addChain: @MainActor () -> Void = {}
     
     
     
    public var createNode: @MainActor () -> Void = {}
     
    public var backupPage: (@MainActor () -> AnyView)? = nil
     
    public var modulesPage: (@MainActor () -> AnyView)? = nil
     
    public var modulesValue: ClashDisplayText = "Off"
    public var activate: @MainActor (Profile.ID) -> Void
    public var delete: @MainActor (ClashMacConfigurationCenterItem) -> Void
     
    public var reorder: (@MainActor ([Profile.ID]) -> Void)? = nil
     
     
    public var updateConfiguration: (@MainActor (Profile.ID) -> Void)? = nil
    public var copyProfileURL: (@MainActor (Profile.ID) -> Void)? = nil
     
     
     
    public var copySourceLink: (@MainActor (String) -> Void)? = nil
    public var hasProfileURL: @MainActor (Profile.ID) -> Bool = { _ in false }
     
    public var hasLegacyProfileURLs: Bool = false
     
    public var statusMessage: ClashDisplayText? = nil
     
    public var failure: (message: ClashDisplayText, canRetry: Bool)? = nil
    public var retryFailure: @MainActor () -> Void = {}
     
     
     
    public var editScheme: (@MainActor (String) -> Void)? = nil

    public init(
        addConfiguration: @escaping @MainActor () -> Void,
        addSource: @escaping @MainActor (ClashMacSourceImportSheet.Tab) -> Void,
        addScheme: @escaping @MainActor (ClashMacSourceImportSheet.Tab) -> Void,
        activate: @escaping @MainActor (Profile.ID) -> Void,
        delete: @escaping @MainActor (ClashMacConfigurationCenterItem) -> Void
    ) {
        self.addConfiguration = addConfiguration
        self.addSource = addSource
        self.addScheme = addScheme
        self.activate = activate
        self.delete = delete
    }

    public static var unavailable: Self {
        Self(addConfiguration: {}, addSource: { _ in }, addScheme: { _ in }, activate: { _ in }, delete: { _ in })
    }
}

 
 
 
 
 
 
 
public struct ClashMacConfigurationCenterListPage<Detail: View>: View {
    private let segment: ClashMacConfigurationCenterSegment
    @ObservedObject private var model: ClashMacConfigurationLibraryModel
    private let profiles: [ClashProfileSnapshot]
    @Binding private var pendingDelete: ClashMacConfigurationCenterItem?
    private let actions: ClashMacConfigurationCenterListActions
     
     
     
     
    private let quickAdd: ((ClashMacConfigurationCenterSegment) -> AnyView)?
    private let detail: (ClashMacConfigurationCenterItem) -> Detail
     
     
     
    @Binding private var pendingPush: ClashMacConfigurationCenterItem?
     
     
    @Binding private var pendingModules: Bool
    @Environment(\.clashPushRoute) private var pushRoute

    public init(
        segment: ClashMacConfigurationCenterSegment,
        model: ClashMacConfigurationLibraryModel,
        profiles: [ClashProfileSnapshot],
        pendingDelete: Binding<ClashMacConfigurationCenterItem?> = .constant(nil),
        pendingPush: Binding<ClashMacConfigurationCenterItem?> = .constant(nil),
        pendingModules: Binding<Bool> = .constant(false),
        actions: ClashMacConfigurationCenterListActions,
        quickAdd: ((ClashMacConfigurationCenterSegment) -> AnyView)? = nil,
        @ViewBuilder detail: @escaping (ClashMacConfigurationCenterItem) -> Detail
    ) {
        self.segment = segment
        self.model = model
        self.profiles = profiles
        _pendingDelete = pendingDelete
        _pendingPush = pendingPush
        _pendingModules = pendingModules
        self.actions = actions
        self.quickAdd = quickAdd
        self.detail = detail
    }

     
    private func pushPending() {
        pushPendingModules()
        guard let item = pendingPush, let pushRoute else { return }
        pendingPush = nil
        let token = UUID()
        let detail = self.detail
        ClashViewRouteRegistry.set(token, ownership: .oneShot, onReturn: {}) { AnyView(detail(item)) }
        pushRoute(ClashViewRoute(id: token))
    }

     
    private func pushPendingModules() {
        guard pendingModules, segment == .configurations, let pushRoute else { return }
        pendingModules = false
        guard let modulesPage = actions.modulesPage else { return }
        let token = UUID()
        ClashViewRouteRegistry.set(token, ownership: .oneShot, onReturn: {}) { modulesPage() }
        pushRoute(ClashViewRoute(id: token))
    }

     
     
    private var rowsShownAtOnce: Int { 24 }
    @State private var expandedShelves: Set<String> = []
    @State private var expandedNodeSets: Set<String> = []
    @State private var expandedRuleSets: Set<String> = []
    @Environment(\.locale) private var locale

    public var body: some View {
         
         
         
         
         
         
         
         
        ScrollViewReader { scroller in
            List {
                 
                Color.clear
                    .frame(height: ClashTheme.Spacing.standard)
                    .clashMacPlainRow()
                switch segment {
                case .configurations: configurationRows
                case .nodes: sourceRows
                case .rules: schemeRows
                }
                Color.clear
                    .frame(height: ClashTheme.Spacing.section)
                    .clashMacPlainRow()
            }
             
             
             
             
             
             
             
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .environment(\.clashMacGroupedList, true)
            .modifier(ClashMacHardTopEdge())
             
             
             
            .clashListRetainsRowSelection()
             
             
             
            .modifier(ClashMacCenterListIdentifier(segment: segment))
             
             
             
             
        }
        .alert(
            Text(clash: .copy("Update Conflict")),
            isPresented: Binding(get: { model.ruleConflictSourceID != nil }, set: { if !$0 { model.dismissRuleConflict() } }),
             
             
             
             
            presenting: model.ruleConflictSourceID
        ) { id in
             
             
            Button(role: .destructive) {
                model.dismissRuleConflict()
                Task { _ = await model.updateSourceSaying(id, replacingRules: true) }
            } label: {
                Text(clash: .copy("Use Profile URL Rules"))
            }
            .accessibilityIdentifier("configuration-center.update-conflict.replace")
            Button(role: .cancel) { model.dismissRuleConflict() } label: { Text(clash: .copy("Cancel")) }
                .accessibilityIdentifier("configuration-center.update-conflict.cancel")
        } message: { _ in
            Text(clash: .copy("Your rule edits conflict with this update. Use the profile URL rules to replace your edits, or cancel to keep the current profile. You can copy your rule scheme before updating."))
        }
         
         
         
         
        .onAppear { pushPending() }
        .onChange(of: pendingPush) { _ in pushPending() }
        .onChange(of: pendingModules) { _ in pushPending() }
    }

     
     
     
     
    private var updateIssuesLine: String? {
        let issues = model.snapshot.updateIssues ?? []
        guard !issues.isEmpty else { return nil }
        let names = issues.map { issue in
            model.snapshot.recipes.first { $0.id == issue.itemID }?.label
                ?? model.snapshot.sources.first { $0.id == issue.itemID }.map { $0.displayLabel(locale: locale) } ?? issue.itemID
        }
        return ClashCopy.string("Some references are unavailable. Previous versions were kept:", locale: locale) + " " + names.joined(separator: ", ")
    }

     
     
    private var listHasLine: Bool {
        if actions.failure != nil { return true }
        guard let status = actions.statusMessage else { return false }
        return !ClashCopy.string(for: status, locale: locale).isEmpty
    }

    @ViewBuilder
    private var listStatusLines: some View {
        if let failure = actions.failure {
            HStack(spacing: ClashTheme.Spacing.compact) {
                Text(clash: failure.message).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                if failure.canRetry {
                    Button { actions.retryFailure() } label: { Text(clash: .copy("Try Again")) }
                        .accessibilityIdentifier("configuration-center.configurations.retry")
                }
                Spacer()
            }
            .accessibilityIdentifier("configuration-center.configurations.failure")
             
             
            .clashFeedbackClaim(["profiles.failure"])
        } else if let status = actions.statusMessage, !ClashCopy.string(for: status, locale: locale).isEmpty {
            Text(clash: status).foregroundStyle(.secondary)
                .accessibilityIdentifier("configuration-center.configurations.status")
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    private func libraryNote(_ text: ClashDisplayText, identifier: String) -> some View {
        Text(clash: text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, ClashTheme.Spacing.row)
            .padding(.horizontal, ClashTheme.Spacing.tight)
            .accessibilityIdentifier(identifier)
            .clashMacPlainRow()
    }

     
    @ViewBuilder
    private var updateStatusLines: some View {
         
         
        let batchReports = model.updateProgress != nil
        let failures = model.updateProgress == nil ? model.updateError : nil
         
         
         
         
         
        let showsList = segment == .configurations && listHasLine && (actions.failure != nil || !batchReports)
        let issues = segment == .configurations ? nil : updateIssuesLine
        if showsList || issues != nil || failures != nil {
            Group {
                if showsList { listStatusLines }
                if let issues {
                    let line = Text(verbatim: issues).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    switch segment {
                    case .configurations: line.accessibilityIdentifier("configuration-center.configurations.update-issues")
                    case .nodes: line.accessibilityIdentifier("configuration-center.nodes.update-issues")
                    case .rules: line.accessibilityIdentifier("configuration-center.rules.update-issues")
                    }
                }
                if let failures {
                    let line = Text(verbatim: failures).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .id(Self.updateFailuresAnchor)
                    switch segment {
                    case .configurations: line.accessibilityIdentifier("configuration-center.configurations.update-failures")
                    case .nodes: line.accessibilityIdentifier("configuration-center.nodes.update-failures")
                    case .rules: line.accessibilityIdentifier("configuration-center.rules.update-failures")
                    }
                }
            }
            .padding(.top, ClashTheme.Spacing.row)
            .padding(.horizontal, ClashTheme.Spacing.tight)
            .clashMacPlainRow()
        }
    }

    private static var updateFailuresAnchor: String { "configuration-center.update-failures" }


     
     
    private var updatesAreBusy: Bool {
        model.isBusy || !model.updatingSourceIDs.isEmpty || !model.updatingCollectionIDs.isEmpty || model.isUpdatingAll
    }

     
    private func expansion(_ set: Binding<Set<String>>, _ id: String) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { open in if open { set.wrappedValue.insert(id) } else { set.wrappedValue.remove(id) } }
        )
    }

     
     
    private func collectionsBySource(_ kind: ConfigurationCollection.Kind) -> [String: [ConfigurationCollectionEntry]] {
        Dictionary(grouping: model.collections.filter { $0.id.kind == kind }, by: \.source.id)
    }

     

     
     
     
     
     
     
     
    @ViewBuilder
    private func configurationMenu(_ profile: ClashProfileSnapshot, index: Int) -> some View {
                    if actions.hasProfileURL(profile.id) {
                        if let update = actions.updateConfiguration {
                            Button { update(profile.id) } label: { Text(clash: .copy("Update")) }
                                .disabled(profile.isBusy)
                        }
                        if let copy = actions.copyProfileURL {
                            Button { copy(profile.id) } label: { Text(clash: .copy("Copy Link")) }
                        }
                        Divider()
                    }
                    if !profile.isCurrent {
                        Button { actions.activate(profile.id) } label: { Text(clash: .copy("Use This Profile")) }
                    }
                    if let reorder = actions.reorder, profiles.count > 1 {
                        if !profile.isCurrent { Divider() }
                        Button { reorder(Self.order(profiles, moving: profile.id, by: -1)) } label: { Text(clash: .copy("Move Up")) }
                            .disabled(index == 0)
                        Button { reorder(Self.order(profiles, moving: profile.id, by: 1)) } label: { Text(clash: .copy("Move Down")) }
                            .disabled(index == profiles.count - 1)
                    }
                    Divider()
                    Button(role: .destructive) { pendingDelete = .configuration(profile.id) } label: { Text(clash: .copy("Delete")) }
    }

    @ViewBuilder
    private var configurationRows: some View {
        ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                HStack(spacing: ClashTheme.Spacing.compact) {
                     
                     
                    Button {
                        actions.activate(profile.id)
                    } label: {
                        ClashSymbolImage(symbol: profile.isCurrent ? .checkmarkCircleFill : .circle)
                            .foregroundStyle(profile.isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                             
                            .frame(width: ClashTheme.Control.pointerRowTarget, height: ClashTheme.Control.pointerRowTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(profile.isCurrent || profile.isBusy)
                    .help(Text(clash: .copy("Use This Profile")))
                    .accessibilityLabel(Text(clash: .copy("Use This Profile")))
                    .accessibilityAddTraits(profile.isCurrent ? .isSelected : [])
                    .accessibilityIdentifier("configuration-center.configurations.select.\(profile.id.rawValue)")
                    ClashRoutedViewLink {
                        detail(.configuration(profile.id))
                    } label: {
                         
                         
                         
                         
                         
                         
                         
                         
                        ClashMacLibraryRowLabel(
                            title: .verbatim(profile.label),
                            badges: profile.badges,
                            note: profile.note,
                            usage: ClashMacConfigurationUsageFacts.usage(configurationID: profile.id.rawValue, fetched: profile.subscription, in: model.snapshot),
                            busy: profile.isBusy
                        )
                    }
                    .accessibilityIdentifier("configuration-center.configurations.row.\(profile.id.rawValue)")
                     
                     
                     
                    Menu { configurationMenu(profile, index: index) } label: {
                        ClashSymbolImage(symbol: .ellipsisCircle)
                            .foregroundStyle(.secondary)
                            .frame(width: ClashTheme.Control.pointerRowTarget)
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(Text(clash: .copy("More")))
                    .accessibilityLabel(Text(clash: .copy("More")))
                    .accessibilityIdentifier("configuration-center.configurations.menu.\(profile.id.rawValue)")
                }
                .contextMenu { configurationMenu(profile, index: index) }
                 
                 
                .accessibilityElement(children: .contain)
                .clashMacGroupRow(first: index == 0, last: index == profiles.count - 1, margin: 0)
        }
        if profiles.isEmpty {
            Text(clash: .copy("None")).foregroundStyle(.secondary)
                .clashMacGroupRow(first: true, last: true, margin: 0)
        }
        if let quickAdd { quickAdd(.configurations) }
         
         
         
        updateStatusLines
         
         
         
         
        if let modulesPage = actions.modulesPage {
            Text(clash: .copy("Modules"))
                .clashMacGroupHeader(margin: 0)
            ClashRoutedViewLink {
                modulesPage()
            } label: {
                Text(clash: actions.modulesValue)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("configuration-center.configurations.modules")
            .clashMacGroupRow(first: true, last: true, margin: 0)
        }
        if let backupPage = actions.backupPage {
            Text(clash: .copy("Data"))
                .clashMacGroupHeader(margin: 0)
            ClashRoutedViewLink {
                backupPage()
            } label: {
                Text(clash: .copy("iCloud Backup & Restore"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("configuration-center.configurations.backup")
            .clashMacGroupRow(first: true, last: true, margin: 0)
        }
    }

     
     
    enum NodeEntry: Identifiable {
        case source(ConfigurationSourceRecord, folds: Bool)
        case collection(ConfigurationCollectionEntry)
        case allSources(shelf: String)

        var id: String {
            switch self {
            case .source(let source, _): return "source." + source.id
            case .collection(let entry): return "collection." + String(describing: entry.id)
            case .allSources(let shelf): return "all." + shelf
            }
        }
    }

    static func nodeEntries(_ shown: [ConfigurationSourceRecord], nodeSets: [String: [ConfigurationCollectionEntry]],
                            expanded: Set<String>, shelf: String, more: Bool) -> [NodeEntry] {
        var entries: [NodeEntry] = []
        for source in shown {
            let collections = nodeSets[source.id] ?? []
            entries.append(.source(source, folds: !collections.isEmpty))
            if expanded.contains(source.id) { entries += collections.map { .collection($0) } }
        }
        if more { entries.append(.allSources(shelf: shelf)) }
        return entries
    }

     
     
    @ViewBuilder
    private var sourceRows: some View {
        let nodeSets = collectionsBySource(.nodes)
        ForEach(Array(model.nodeShelves.enumerated()), id: \.element.id) { shelfIndex, shelf in
            let showsAll = expandedShelves.contains(shelf.id) || shelf.sources.count <= rowsShownAtOnce
            let shown = showsAll ? shelf.sources : Array(shelf.sources.prefix(rowsShownAtOnce))
            let entries = Self.nodeEntries(shown, nodeSets: nodeSets, expanded: expandedNodeSets, shelf: shelf.id, more: !showsAll)
            Text(clash: .copy(shelf.group.title))
                .clashMacGroupHeader(first: shelfIndex == 0, margin: 0)
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                nodeRow(entry)
                    .clashMacGroupRow(first: index == 0, last: index == entries.count - 1, margin: 0)
            }
        }
        if model.nodeShelves.isEmpty {
            Text(clash: .copy("None")).foregroundStyle(.secondary)
                .clashMacGroupRow(first: true, last: true, margin: 0)
        }
         
         
         
        HStack(spacing: ClashTheme.Spacing.compact) {
            Spacer(minLength: 0)
             
             
             
             
            if model.hasLinkedNodes {
                Button { Task { await model.updateAllSources() } } label: { Text(clash: .copy("Update All")) }
                    .disabled(updatesAreBusy)
                    .accessibilityIdentifier("configuration-center.nodes.update-all")
            }
             
             
             
             
             
             
             
             
             
            Button { actions.createNode() } label: {
                Text(clash: .opens("Create Nodes", locale: locale))
            }
            .fixedSize()
            .accessibilityIdentifier("configuration-center.nodes.create")
            Button { actions.addChain() } label: {
                Text(clash: .opens("Proxy Chain", locale: locale))
            }
            .fixedSize()
            .accessibilityIdentifier("configuration-center.nodes.chain")
        }
        .clashMacFormActionChrome()
        .padding(.top, ClashTheme.Spacing.row)
        .clashMacPlainRow()
        if let quickAdd { quickAdd(.nodes) }
         
         
         
         
         
         
         
        libraryNote(
            .copy("These nodes are a source of their own. A configuration uses them once it turns this source on in its Proxies chapter."),
            identifier: "configuration.library.sources.what-this-is"
        )
        updateStatusLines
    }

    @ViewBuilder
    private func nodeRow(_ entry: NodeEntry) -> some View {
        switch entry {
        case .source(let source, let folds):
            HStack(spacing: 0) {
                if folds {
                    ClashMacFoldButton(isExpanded: expansion($expandedNodeSets, source.id), title: source.displayLabel(locale: locale))
                        .accessibilityIdentifier("configuration-center.nodes.node-sets.\(source.id)")
                }
                 
                 
                 
                let linked = ClashMacConfigurationLibraryModel.link(of: source) != nil
                ClashMacNodeSourceRow(
                    source: source, isUpdating: model.updatingSourceIDs.contains(source.id), detail: detail,
                    update: linked && source.isRetainedSnapshot != true ? { Task { _ = await model.updateSourceSaying(source.id) } } : nil,
                    copyLink: linked ? actions.copySourceLink.map { copy in { copy(source.id) } } : nil
                ) {
                    pendingDelete = .source(source.id)
                }
            }
        case .collection(let entry):
            ClashMacNodeCollectionRow(entry: entry, detail: detail)
                .padding(.leading, ClashMacFoldButton.indent)
        case .allSources(let shelf):
            Button { expandedShelves.insert(shelf) } label: { Text(clash: .copy("All Sources")) }
                .buttonStyle(.link)
                .accessibilityIdentifier("configuration-center.nodes.show-all")
        }
    }

     
    private struct RuleRowWords {
        let builtIn: String
        let usedBy: (one: String, other: String)
        let rules: (one: String, other: String)
    }

     
     
     
     
    enum RuleEntry: Identifiable {
        case scheme(ConfigurationRuleScheme, folds: Bool)
        case ruleSetSource(ConfigurationSourceRecord)
        case collection(ConfigurationCollectionEntry)

        var id: String {
            switch self {
            case .scheme(let scheme, _): return "scheme." + scheme.id
            case .ruleSetSource(let source): return "source." + source.id
            case .collection(let entry): return "collection." + String(describing: entry.id)
            }
        }
    }

     
     
     
    static func ruleEntries(_ shelf: ClashMacRuleLibrarySection,
                            ruleSets: [String: [ConfigurationCollectionEntry]], expanded: Set<String>) -> [RuleEntry] {
        var entries: [RuleEntry] = []
        for scheme in shelf.schemes {
            let folded = ClashMacConfigurationLibraryModel.foldedRuleSets(of: scheme, ruleSets) ?? []
            entries.append(.scheme(scheme, folds: !folded.isEmpty))
            if expanded.contains(scheme.id) { entries += folded.map { .collection($0) } }
        }
        for source in shelf.ruleSetSources {
            entries.append(.ruleSetSource(source))
            if expanded.contains(source.id) { entries += (ruleSets[source.id] ?? []).map { .collection($0) } }
        }
        return entries
    }

     
     
    @ViewBuilder
    private var schemeRows: some View {
         
         
         
        let linked = linkedSourceIDs
        let ruleCounts = Dictionary(model.snapshot.sources.map { ($0.id, $0.ruleCount) }, uniquingKeysWith: { first, _ in first })
        let ruleSets = collectionsBySource(.rules)
        let words = RuleRowWords(
            builtIn: ClashCopy.string("Built-in", locale: locale),
            usedBy: (one: ClashCopy.string("Used by %@ profile", locale: locale), other: ClashCopy.string("Used by %@ profiles", locale: locale)),
            rules: (one: ClashCopy.string("%@ rule", locale: locale), other: ClashCopy.string("%@ rules", locale: locale))
        )
        let sections = ClashMacConfigurationLibraryModel.ruleLibrarySections(
            model.snapshot, shelves: model.ruleShelves, collections: model.collections)
        ForEach(Array(sections.enumerated()), id: \.element.id) { shelfIndex, shelf in
            let entries = Self.ruleEntries(shelf, ruleSets: ruleSets, expanded: expandedRuleSets)
            Text(clash: .copy(shelf.section.title))
                .clashMacGroupHeader(first: shelfIndex == 0, margin: 0)
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                ruleRow(entry, linked: linked, ruleCounts: ruleCounts, ruleSets: ruleSets, words: words)
                    .clashMacGroupRow(first: index == 0, last: index == entries.count - 1, margin: 0)
            }
        }
         
         
         
        if model.hasLinkedRuleSets {
            HStack {
                Spacer(minLength: 0)
                Button { Task { await model.updateAllRuleSets() } } label: { Text(clash: .copy("Update All")) }
                    .disabled(updatesAreBusy)
                    .accessibilityIdentifier("configuration-center.rules.update-all")
            }
            .clashMacFormActionChrome()
            .padding(.top, ClashTheme.Spacing.row)
            .clashMacPlainRow()
        }
        if let quickAdd { quickAdd(.rules) }
        libraryNote(
            .copy("This is a library. A configuration uses a rule scheme from here once that configuration is set to use it."),
            identifier: "configuration.library.rules.what-this-is"
        )
        updateStatusLines
    }

    @ViewBuilder
    private func ruleRow(_ entry: RuleEntry, linked: Set<String>, ruleCounts: [String: Int],
                         ruleSets: [String: [ConfigurationCollectionEntry]], words: RuleRowWords) -> some View {
        switch entry {
        case .scheme(let scheme, let folds):
            HStack(spacing: 0) {
                if folds {
                    ClashMacFoldButton(isExpanded: expansion($expandedRuleSets, scheme.id), title: scheme.displayLabel)
                        .accessibilityIdentifier("configuration-center.rules.rule-sets.\(scheme.id)")
                }
                ClashMacSchemeRow(
                    scheme: scheme, status: schemeStatus(scheme, ruleCounts: ruleCounts, words: words),
                    isUpdating: model.updatingSourceIDs.contains(scheme.sourceID), detail: detail
                ) {
                    schemeMenu(scheme, linked: linked)
                }
            }
        case .ruleSetSource(let source):
            HStack(spacing: 0) {
                ClashMacFoldButton(isExpanded: expansion($expandedRuleSets, source.id), title: source.displayLabel(locale: locale))
                ClashMacRuleSetSourceRow(
                    source: source, collections: ruleSets[source.id] ?? [],
                    isUpdating: model.updatingSourceIDs.contains(source.id),
                    copyLink: linked.contains(source.id) ? actions.copySourceLink.map { copy in { copy(source.id) } } : nil,
                    delete: ClashMacConfigurationLibraryModel.canDeleteSource(source) ? { pendingDelete = .source(source.id) } : nil
                )
            }
            .accessibilityIdentifier("configuration-center.rules.source.\(source.id)")
        case .collection(let collection):
            ClashMacRuleSetRow(
                entry: collection, updating: model.updatingCollectionIDs.contains(collection.id),
                updateCollection: model.canUpdateCollections ? { entry in Task { await model.updateCollection(entry) } } : nil,
                updatesHeld: model.isUpdatingAll, detail: detail
            )
            .padding(.leading, ClashMacFoldButton.indent)
        }
    }

     
     
     
     
     
    @ViewBuilder
    private func schemeMenu(_ scheme: ConfigurationRuleScheme, linked: Set<String>) -> some View {
         
        if linked.contains(scheme.sourceID) {
            Button { Task { _ = await model.updateSourceSaying(scheme.sourceID, label: scheme.label) } } label: { Text(clash: .copy("Update")) }
                .accessibilityIdentifier("configuration-center.rules.row.update")
            if let copy = actions.copySourceLink {
                Button { copy(scheme.sourceID) } label: { Text(clash: .copy("Copy Link")) }
                    .accessibilityIdentifier("configuration-center.rules.row.copy-link")
            }
        }
        if scheme.isRetainedSnapshot != true, let editScheme = actions.editScheme {
            if linked.contains(scheme.sourceID) { Divider() }
            Button { editScheme(scheme.id) } label: { Text(clash: .copy("Edit")) }
        }
        if scheme.canBeDeleted {
            Divider()
            Button(role: .destructive) { pendingDelete = .scheme(scheme.id) } label: { Text(clash: .copy("Delete")) }
        }
    }

     
     
     
    private func schemeStatus(
        _ scheme: ConfigurationRuleScheme, ruleCounts: [String: Int], words: RuleRowWords
    ) -> ClashDisplayText {
        var parts: [String] = []
        if scheme.kind == .builtin {
            parts.append(words.builtIn)
        } else {
            let usage = model.usageCount(ofScheme: scheme.id)
            parts.append((usage == 1 ? words.usedBy.one : words.usedBy.other).replacingOccurrences(of: "%@", with: ClashCopy.count(usage, locale: locale)))
        }
        if let ruleCount = ruleCounts[scheme.sourceID], ruleCount > 0 {
             
            parts.append((ruleCount == 1 ? words.rules.one : words.rules.other).replacingOccurrences(of: "%@", with: ClashCopy.count(ruleCount, locale: locale)))
        }
        return .verbatim(parts.joined(separator: " · "))
    }

     
    private var linkedSourceIDs: Set<String> {
        Set(model.snapshot.sources.compactMap { source in ClashMacConfigurationLibraryModel.link(of: source) == nil ? nil : source.id })
    }

     

     
    static func order(_ profiles: [ClashProfileSnapshot], moving id: Profile.ID, by offset: Int) -> [Profile.ID] {
        var ids = profiles.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return ids }
        ids.swapAt(index, index + offset)
        return ids
    }
}

 
 
 
 
 
public enum ClashMacDeleteCopy {
    public static func title(_ item: ClashMacConfigurationCenterItem, isChain: Bool, locale: Locale) -> String {
        switch item {
        case .source: ClashCopy.string(isChain ? "Delete Proxy Chain" : "Delete Source", locale: locale)
        case .scheme: ClashCopy.string("Delete Rule Scheme", locale: locale)
        case .configuration, .collection: ClashCopy.string("Delete Profile", locale: locale)
        }
    }

     
     
    public static func message(_ item: ClashMacConfigurationCenterItem, isChain: Bool,
                               suppliesNodes: Bool = false, locale: Locale) -> String {
        switch item {
         
        case .source: ClashCopy.string(isChain
            ? "Saved profiles keep this chain. Its original nodes remain in the library."
            : suppliesNodes
            ? "Configurations that use this source lose its nodes."
            : "Saved profiles keep their current content and stop following this source.", locale: locale)
        case .scheme: ClashCopy.string("Saved profiles keep their current rules and stop following this scheme.", locale: locale)
        case .configuration: ClashCopy.string("This profile will be deleted. Sources and rule schemes in the library will remain.", locale: locale)
        case .collection: ""
        }
    }
}

 
 
 
 
 
 
public struct ClashMacObservedLibraryPage<Content: View>: View {
    @ObservedObject private var model: ClashMacConfigurationLibraryModel
    private let content: (ClashMacConfigurationLibraryModel) -> Content

    public init(model: ClashMacConfigurationLibraryModel, @ViewBuilder content: @escaping (ClashMacConfigurationLibraryModel) -> Content) {
        self.model = model
        self.content = content
    }

    public var body: some View { content(model) }
}

 
 
 
struct ClashMacPopsWhenGone: ViewModifier {
    let gone: Bool
    @StateObject private var dismiss = ClashDismissHandle()

    func body(content: Content) -> some View {
        content
            .clashCapturesDismiss(dismiss)
            .onChange(of: gone) { value in if value { dismiss() } }
    }
}

public extension View {
    func clashMacPopsWhenGone(_ gone: Bool) -> some View {
        modifier(ClashMacPopsWhenGone(gone: gone))
    }
}

 
 
 
 
private struct ClashMacCenterListIdentifier: ViewModifier {
    let segment: ClashMacConfigurationCenterSegment

    @ViewBuilder
    func body(content: Content) -> some View {
        switch segment {
        case .configurations: content.accessibilityIdentifier("configuration-center.configurations")
        case .nodes: content.accessibilityIdentifier("configuration-center.nodes")
        case .rules: content.accessibilityIdentifier("configuration-center.rules")
        }
    }
}

 
 
 
 
struct ClashMacLibraryRowLabel: View {
    let title: ClashDisplayText
    var subtitle: ClashDisplayText? = nil
     
     
     
     
     
    var badges: [ClashDisplayText] = []
     
     
     
    var note: ClashDisplayText? = nil
     
     
    var usage: ConfigurationSubscriptionUsage? = nil
    var busy = false
    @Environment(\.locale) private var locale

    var body: some View {
        LabeledContent {
            if busy {
                ProgressView().controlSize(.small)
            }
        } label: {
            if badges.isEmpty {
                Text(clash: title).lineLimit(1)
            } else {
                HStack(spacing: 5) {
                     
                     
                     
                     
                    Text(clash: title).lineLimit(1).layoutPriority(1)
                    ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                        ClashMacRowBadge(text: badge).fixedSize()
                    }
                }
            }
            if let subtitle {
                Text(clash: subtitle).lineLimit(1)
            }
            if let usage {
                Text(verbatim: trafficLine(usage)).lineLimit(1)
                if let fraction = usage.fraction {
                    ProgressView(value: min(1, max(0, fraction)))
                        .frame(maxWidth: 240)
                        .accessibilityLabel(Text(clash: .copy("Used")))
                }
                if let expiry = ClashMacSubscriptionUsageCopy.expiry(usage, locale: locale) {
                     
                    Text(clash: expiry)
                        .foregroundStyle(usage.expire < Int64(Date().timeIntervalSince1970) ? Color.red : Color.secondary)
                }
            } else if let note {
                Text(clash: note).lineLimit(1)
            }
        }
         
         
        .accessibilityValue(usage.map { Text(verbatim: trafficLine($0)) } ?? Text(verbatim: ""))
    }

    private func trafficLine(_ usage: ConfigurationSubscriptionUsage) -> String {
        let traffic = ClashCopy.string(for: ClashMacSubscriptionUsageCopy.traffic(usage), locale: locale)
        guard let note else { return traffic }
        return traffic + " · " + ClashCopy.string(for: note, locale: locale)
    }
}

 
 
 
 
 
struct ClashMacListRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: ClashTheme.Spacing.compact) { content() }
    }
}

 
 
 
struct ClashMacNodeSourceRow<Detail: View>: View {
    let source: ConfigurationSourceRecord
    let isUpdating: Bool
    let detail: (ClashMacConfigurationCenterItem) -> Detail
    let update: (() -> Void)?
    let copyLink: (() -> Void)?
    let delete: () -> Void

    var body: some View {
        ClashMacListRow {
            ClashRoutedViewLink {
                detail(.source(source.id))
            } label: {
                ClashMacLibraryRowLabel(
                    title: ClashConfigurationSourceCopy.name(source),
                     
                    subtitle: source.isRetainedSnapshot == true ? .copy("Saved Copy") : .count(source.nodeCount, one: "%@ node", other: "%@ nodes"),
                    usage: source.subscriptionUsage,
                    busy: isUpdating
                )
            }
            .contextMenu {
                if let update {
                    Button(action: update) { Text(clash: .copy("Update")) }
                        .accessibilityIdentifier("configuration-center.nodes.row.update")
                }
                if let copyLink {
                    Button(action: copyLink) { Text(clash: .copy("Copy Link")) }
                        .accessibilityIdentifier("configuration-center.nodes.row.copy-link")
                }
                if update != nil || copyLink != nil { Divider() }
                Button(role: .destructive, action: delete) { Text(clash: .copy("Delete")) }
            }
            .accessibilityIdentifier("configuration-center.nodes.row.\(source.id)")
        }
    }
}

 
 
struct ClashMacNodeCollectionRow<Detail: View>: View {
    let entry: ConfigurationCollectionEntry
    let detail: (ClashMacConfigurationCenterItem) -> Detail

    var body: some View {
        ClashMacListRow {
            ClashRoutedViewLink {
                detail(.collection(entry.id))
            } label: {
                ClashMacLibraryRowLabel(
                    title: .verbatim(entry.collection.name),
                    subtitle: entry.memberCount.map { .count($0, one: "%@ node", other: "%@ nodes") } ?? .verbatim(entry.collection.type),
                    usage: entry.subscriptionUsage
                )
            }
            .accessibilityIdentifier("configuration-center.nodes.collection.\(entry.source.id).\(entry.collection.name)")
        }
    }
}

 
 
 
 
 
struct ClashMacFoldButton: View {
    @Binding var isExpanded: Bool
    let title: String

     
    static let indent: CGFloat = 16

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
        } label: {
            Image(systemName: ClashSymbol.chevronForward.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: ClashMacGroupMetrics.inset, height: ClashMacGroupMetrics.inset * 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, -ClashMacGroupMetrics.inset)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(clash: .copy(isExpanded ? "Expanded" : "Collapsed")))
    }
}

 
 
 
 
struct ClashMacRowBadge: View {
    let text: ClashDisplayText

    var body: some View {
        Text(clash: text)
            .font(.caption2)
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(.secondary.opacity(0.55), lineWidth: 1)
            )
    }
}

 
struct ClashMacSchemeRow<Detail: View, Menu: View>: View {
    let scheme: ConfigurationRuleScheme
    let status: ClashDisplayText
    let isUpdating: Bool
    let detail: (ClashMacConfigurationCenterItem) -> Detail
    @ViewBuilder let menu: () -> Menu

    var body: some View {
        ClashMacListRow {
            ClashRoutedViewLink {
                detail(.scheme(scheme.id))
            } label: {
                ClashMacLibraryRowLabel(title: .verbatim(scheme.displayLabel), subtitle: status, busy: isUpdating)
            }
            .contextMenu { menu() }
            .accessibilityIdentifier("configuration-center.rules.row.\(scheme.id)")
        }
    }
}

 
 
struct ClashMacRuleSetRow<Detail: View>: View {
    let entry: ConfigurationCollectionEntry
    let updating: Bool
    let updateCollection: ((ConfigurationCollectionEntry) -> Void)?
    let updatesHeld: Bool
    let detail: (ClashMacConfigurationCenterItem) -> Detail

    var body: some View {
        ClashMacListRow {
            ClashRoutedViewLink {
                detail(.collection(entry.id))
            } label: {
                ClashMacLibraryRowLabel(
                    title: .verbatim(entry.collection.name),
                    subtitle: entry.memberCount.map { .count($0, one: "%@ rule", other: "%@ rules") } ?? .verbatim(entry.collection.type),
                    busy: updating
                )
            }
            .contextMenu {
                if entry.collection.type == "http", entry.source.isRetainedSnapshot != true, let updateCollection {
                    Button { updateCollection(entry) } label: { Text(clash: .copy("Update")) }
                        .disabled(updating || updatesHeld)
                        .accessibilityIdentifier("configuration-center.rules.collection.update")
                }
            }
            .accessibilityIdentifier("configuration-center.rules.collection.\(entry.source.id).\(entry.collection.name)")
        }
    }
}

 
 
 
 
struct ClashMacRuleSetSourceRow: View {
    let source: ConfigurationSourceRecord
    let collections: [ConfigurationCollectionEntry]
    let isUpdating: Bool
    let copyLink: (() -> Void)?
    let delete: (() -> Void)?

    var body: some View {
        ClashMacListRow {
            ClashMacLibraryRowLabel(
                title: ClashConfigurationSourceCopy.name(source),
                subtitle: .count(collections.count, one: "%@ collection", other: "%@ collections"),
                busy: isUpdating
            )
            .contextMenu {
                if let copyLink {
                    Button(action: copyLink) { Text(clash: .copy("Copy Link")) }
                        .accessibilityIdentifier("configuration-center.rules.source.copy-link")
                    if delete != nil { Divider() }
                }
                if let delete {
                    Button(role: .destructive, action: delete) { Text(clash: .copy("Delete")) }
                        .accessibilityIdentifier("configuration-center.rules.source.delete")
                }
            }
        }
    }
}

 
 
 
 
 
public struct ClashMacUnchangedPage<Key: Equatable, Content: View>: View, Equatable {
    let key: Key
    @ViewBuilder let content: () -> Content

    public init(key: Key, @ViewBuilder content: @escaping () -> Content) {
        self.key = key
        self.content = content
    }

    public var body: some View { content() }

    public nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }
}
