import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
public struct ClashMacConfigurationInspectorActions {
    public var rename: @MainActor (String) -> Void
    public var setSources: @MainActor ([String]) -> Void
    public var setScheme: @MainActor (String) -> Void
    public var activate: @MainActor () -> Void
     
     
    public var duplicate: @MainActor () async throws -> String
    public var export: @MainActor () -> Void
    public var editSource: @MainActor () -> Void
    public var delete: @MainActor () -> Void
     
    public var setSourceUpdates: @MainActor (Bool) -> Void
     
     
    public var followLink: @MainActor (String) -> Void = { _ in }
    public var openRuntimePreview: @MainActor () -> Void
    public var restoreLastKnownGood: @MainActor () -> Void
    public var setAutoUpdate: @MainActor (Bool) -> Void
    public var setInterval: @MainActor (Int) -> Void
    public var updateSource: @MainActor () -> Void
     
     
     
     
     
    public var isUpdatingSource = false
     
     
     
     
     
    public var updateError: String? = nil
     
     
     
     
    public var saveLibraryLink: (@MainActor (String) async throws -> Void)? = nil
     
    public var libraryLinkSharedBy = 1
     
     
     
    public var saveLibraryInterval: (@MainActor (Int) async throws -> Void)? = nil
    public var stripCredentials: @MainActor () -> Void
    public var adoptHeldBack: @MainActor (String) -> Void
    public var dismissHeldBack: @MainActor () -> Void
     
     
     
    public var setScope: @MainActor (String, ConfigurationNodeScope?) -> Void = { _, _ in }
     
    public var copyProfileURL: @MainActor () -> Bool = { false }
     
     
    public var customRules: ClashMacCustomRulesActions? = nil
     
     
     
    public var setOriginalUse: @MainActor (Bool) -> Void = { _ in }
    public var loadScopeChoices: @MainActor (ConfigurationSourceRecord) async throws -> ClashMacNodeScopeChoices = { _ in
        throw ConfigurationLibraryError.unreadable
    }
     
     
     
    public var loadOutline: (@MainActor (Int) async throws -> [ConfigurationOutlineRow])? = nil
     
     
    public var sourceNodes: (@MainActor (ConfigurationSourceRecord, ConfigurationNodeScope?) async throws -> ClashMacSourceNodes)? = nil
     
    public var outlineDestination: @MainActor (ConfigurationOutlineSection) -> ClashMacOutlineDestination? = { _ in nil }
     
     
    public var originalGroupPage: (@MainActor (String) -> AnyView)? = nil
     
     
    public var originalEntrySettings: ClashMacSettingsSectionActions? = nil
     
     
     
     
    public var schemeGroupPage: (@MainActor (String) -> AnyView)? = nil
     
     
    public var loadSchemeGroups: (@MainActor () async -> [(name: String, type: String)])? = nil
     
     
    public var editSchemeSource: (@MainActor () -> Void)? = nil
     
    public var saveAsScheme: (@MainActor (String) -> Void)? = nil
     
    public var compile: (@MainActor () async -> ClashMacCompileResult)? = nil
     
     
     
    public var settingsSection: ClashMacSettingsSectionActions? = nil

    public init(
        rename: @escaping @MainActor (String) -> Void,
        setSources: @escaping @MainActor ([String]) -> Void,
        setScheme: @escaping @MainActor (String) -> Void,
        activate: @escaping @MainActor () -> Void,
        duplicate: @escaping @MainActor () async throws -> String,
        export: @escaping @MainActor () -> Void,
        editSource: @escaping @MainActor () -> Void,
        delete: @escaping @MainActor () -> Void,
        setSourceUpdates: @escaping @MainActor (Bool) -> Void,
        openRuntimePreview: @escaping @MainActor () -> Void,
        restoreLastKnownGood: @escaping @MainActor () -> Void,
        setAutoUpdate: @escaping @MainActor (Bool) -> Void,
        setInterval: @escaping @MainActor (Int) -> Void,
        updateSource: @escaping @MainActor () -> Void,
        stripCredentials: @escaping @MainActor () -> Void,
        adoptHeldBack: @escaping @MainActor (String) -> Void,
        dismissHeldBack: @escaping @MainActor () -> Void
    ) {
        self.rename = rename; self.setSources = setSources; self.setScheme = setScheme
        self.activate = activate; self.duplicate = duplicate; self.export = export
        self.editSource = editSource; self.delete = delete
        self.setSourceUpdates = setSourceUpdates; self.openRuntimePreview = openRuntimePreview
        self.restoreLastKnownGood = restoreLastKnownGood
        self.setAutoUpdate = setAutoUpdate; self.setInterval = setInterval; self.updateSource = updateSource
        self.stripCredentials = stripCredentials; self.adoptHeldBack = adoptHeldBack; self.dismissHeldBack = dismissHeldBack
    }

    public static var unavailable: Self {
        Self(
            rename: { _ in }, setSources: { _ in }, setScheme: { _ in },
            activate: {}, duplicate: { throw CancellationError() }, export: {}, editSource: {}, delete: {},
            setSourceUpdates: { _ in }, openRuntimePreview: {}, restoreLastKnownGood: {},
            setAutoUpdate: { _ in }, setInterval: { _ in }, updateSource: {},
            stripCredentials: {}, adoptHeldBack: { _ in }, dismissHeldBack: {}
        )
    }
}

 
 
 
 
public struct ClashMacConfigurationInspector: View {
    private let profile: ClashProfileSnapshot
    private let sources: [ConfigurationSourceRecord]
     
    private let ruleShelves: [ClashMacRuleLibraryShelf]
    private let schemes: [ConfigurationRuleScheme]
     
     
    private let schemeChoices: [ConfigurationRuleScheme]?
    private let recipe: ConfigurationRecipe?
    private let scriptsActions: ClashMacScriptsActions
     
    private let scriptsQuickAdd: ((@escaping @MainActor () -> Void) -> AnyView)?
    private let profileURL: String?
    private let actions: ClashMacConfigurationInspectorActions
     
     
    private let door: (ClashMacConfigurationDoor) -> AnyView
     
     
    private let outlineScheme: ClashMacOutlineScheme?
     
    private let schemeUsage: [String: Int]
     
    private let followedLinks: [String: String]
     
    private let libraryGeneration: UInt64
     
     
     
    private let updateFollowing: ConfigurationUpdateFollowing?
     
     
    private let linksToRejoin: [ConfigurationSourceRecord]
     
     
    @State private var asksToGoBackToLink = false
     
    @State private var asksWhichLink = false
    @State private var name: String
    @FocusState private var nameIsFocused: Bool
     
     
    @State private var sentName: String?
    @State private var chosenSources: Set<String>
    @State private var chosenScheme: String
     
    @State private var scripts = ClashMacScriptsState.empty
    @State private var customRules = ClashMacCustomRulesState.empty
    @State private var showsAllHeldBack = false
     
    @State private var outlineRows: [ConfigurationOutlineRow]?
     
    @State private var pageObjects: ClashMacPageObjects?
     
     
    @State private var query = ""
    @State private var searchFields: [ClashMacSearchField] = []
    @Environment(\.configurationFieldCopy) private var fieldCopy
     
    @State private var outlineReads = 0
    @State private var compiling = false
    @State private var compilePresentation: ClashMacCompilePresentation?
    @State private var asksSchemeName = false
    @State private var schemeName = ""
     
     
     
     
    @Environment(\.clashFeedback) private var feedback
    @State private var duplicating = false
    @State private var leave = ClashDismissHandle()
    @Environment(\.locale) private var locale

    public init(
        profile: ClashProfileSnapshot,
        sources: [ConfigurationSourceRecord],
        ruleShelves: [ClashMacRuleLibraryShelf],
        recipe: ConfigurationRecipe?,
        scriptsActions: ClashMacScriptsActions,
        scriptsQuickAdd: ((@escaping @MainActor () -> Void) -> AnyView)? = nil,
        profileURL: String? = nil,
        actions: ClashMacConfigurationInspectorActions,
        door: @escaping (ClashMacConfigurationDoor) -> AnyView = { _ in AnyView(EmptyView()) },
        outlineScheme: ClashMacOutlineScheme? = nil,
        schemeUsage: [String: Int] = [:],
        followedLinks: [String: String] = [:],
        schemeChoices: [ConfigurationRuleScheme]? = nil,
        libraryGeneration: UInt64 = 0,
        updateFollowing: ConfigurationUpdateFollowing? = nil,
        linksToRejoin: [ConfigurationSourceRecord] = []
    ) {
        self.schemeChoices = schemeChoices
        self.profile = profile
        self.sources = sources
        let schemes = ruleShelves.flatMap(\.schemes)
        self.ruleShelves = ruleShelves
        self.schemes = schemes
        self.recipe = recipe
        self.scriptsActions = scriptsActions
        self.scriptsQuickAdd = scriptsQuickAdd
        self.profileURL = profileURL
        self.actions = actions
        self.door = door
        self.outlineScheme = outlineScheme
        self.schemeUsage = schemeUsage
        self.followedLinks = followedLinks
        self.libraryGeneration = libraryGeneration
        self.updateFollowing = updateFollowing
        self.linksToRejoin = linksToRejoin
        _name = State(initialValue: profile.label)
        let seeds = Self.seeds(profile: profile, recipe: recipe, sources: sources, schemes: schemes)
        _chosenSources = State(initialValue: seeds.sources)
        _chosenScheme = State(initialValue: seeds.scheme)
    }

    private var isComposed: Bool { recipe != nil }
     
    private static let heldBackRowsShownAtOnce = 8

    public var body: some View {
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        VStack(spacing: 0) {
        Form {
            Section {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField(text: $query, prompt: Text(clash: .copy("Search"))) { Text(clash: .copy("Search")) }
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier("configuration-center.configuration.search")
                }
            }
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ClashMacConfigurationSearchResults(query: query, objects: pageObjects ?? ClashMacPageObjects(), fields: searchFields,
                                                  page: objectPage, fieldPage: fieldPage, onReturn: cardPageReturned)
            } else {
             
             
             
             
             
             
            management
            if !profile.heldBackUpdates.isEmpty { heldBack }
             
             
             
             
             
            configurationCard
            pageActions
            }
        }
        .formStyle(.grouped)
        }
        .accessibilityIdentifier("configuration-center.configuration")
         
         
         
         
         
         
         
         
         
         
         
        .onChange(of: recipe?.sources.map(\.id)) { ids in
            let next = ids.map(Set.init) ?? Self.seeds(profile: profile, recipe: nil, sources: sources, schemes: schemes).sources
            ClashMacDebugLog.note("page.resync sources recipe=\(ids ?? []) chosen \(chosenSources.sorted()) → \(next.sorted())")
            chosenSources = next
        }
        .onChange(of: recipe?.ruleSchemeID) { scheme in
            let next = scheme ?? Self.seeds(profile: profile, recipe: nil, sources: sources, schemes: schemes).scheme
            ClashMacDebugLog.note("page.resync scheme recipe=\(scheme ?? "nil") chosen \(chosenScheme) → \(next)")
            chosenScheme = next
        }
        .task(id: profile.id) {
            scripts = await scriptsActions.load()
            if let load = actions.customRules?.load { customRules = await load() }
        }
        .task(id: outlineKey) { await readOutline() }
        .clashCapturesDismiss(leave)
        .sheet(item: $compilePresentation) { shown in
            ClashMacCompileResultSheet(result: shown.result) { compilePresentation = nil }
        }
        .alert(Text(clash: .copy("Save as Rule Scheme")), isPresented: $asksSchemeName) {
            TextField(text: $schemeName) { Text(clash: .copy("Name")) }
                .accessibilityIdentifier("configuration-center.configuration.save-as-scheme.name")
            Button(role: .cancel) {} label: { Text(clash: .copy("Cancel")) }
            Button {
                let name = schemeName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { actions.saveAsScheme?(name) }
            } label: { Text(clash: .copy("Save")) }
        }
        .onAppear { ClashMacDebugLog.note("page.appear \(profile.id.rawValue) composed=\(isComposed) follows=\(String(describing: updateFollowing)) canEditSource=\(profile.canEditSource)") }
        .onChange(of: updateFollowing) { follows in
            ClashMacDebugLog.note("page.profile \(profile.id.rawValue) follows=\(String(describing: follows)) composed=\(isComposed)")
        }
    }

     

     
     
     
    static func duplicateResult(_ label: String?) -> ClashFeedbackPresentation {
        guard let label, !label.isEmpty else {
            return .success(title: ClashFeedbackCopy.saved, accessibilityIdentifier: "feedback.configuration.duplicate.added")
        }
        return ClashMacFeedbackSentences.added(label, id: "configuration.duplicate")
    }

    private func duplicate() {
        guard !duplicating else { return }
        duplicating = true
        Task { @MainActor in
            defer { duplicating = false }
            do {
                let label = try await actions.duplicate()
                feedback?.say(Self.duplicateResult(label), operation: "configuration.duplicate")
                leave()
            } catch is CancellationError {
            } catch {
                feedback?.say(ClashMacFeedbackSentences.couldNotSave(reason: error.localizedDescription,
                                                                       id: "configuration.duplicate"),
                               operation: "configuration.duplicate")
            }
        }
    }

     
     
     
     
    private var management: some View {
        Section {
            nameRow
             
             
            if profile.source != .remote {
                LabeledContent { Text(clash: profile.sourceSummary) } label: { Text(clash: .copy("Source")) }
            }
             
             
            if profile.source == .remote { trafficRow }
            followLinkRow
            if profile.source == .remote { linkRows }
        } header: {
             
             
             
            HStack(spacing: ClashTheme.Spacing.compact) {
                Text(clash: .copy("Configuration")).accessibilityIdentifier("configuration-center.configuration.management-header")
                Spacer()
                statusControls
            }
        }
    }

    private var statusControls: some View {
                HStack(spacing: ClashTheme.Spacing.compact) {
                    if profile.isCurrent {
                        Label { Text(clash: .copy("In Use")) } icon: { Image(systemName: "checkmark.circle.fill") }
                            .foregroundStyle(.tint)
                            .accessibilityIdentifier("configuration-center.configuration.in-use")
                    } else {
                        Button { actions.activate() } label: { Text(clash: .copy("Use This Profile")) }
                            .disabled(profile.isBusy)
                            .accessibilityIdentifier("configuration-center.configuration.activate")
                    }
                    Menu {
                         
                         
                         
                        if profile.canOpenRuntimePreview {
                            Button { actions.openRuntimePreview() } label: { Text(clash: .copy("View Runtime Configuration")) }
                        }
                        if profile.canRestoreLastKnownGood {
                            Button { actions.restoreLastKnownGood() } label: { Text(clash: .copy("Restore Last Known Good")) }
                        }
                        if profile.canOpenRuntimePreview || profile.canRestoreLastKnownGood { Divider() }
                        Button(role: .destructive) { actions.delete() } label: { Text(clash: .copy("Delete")) }
                            .disabled(!profile.canDelete)
                            .accessibilityIdentifier("configuration-center.configuration.delete")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityIdentifier("configuration-center.configuration.more")
                }
    }

    private var nameRow: some View {
            TextField(text: $name) { Text(clash: .copy("Name")) }
                .accessibilityIdentifier("configuration-center.configuration.name")
                .focused($nameIsFocused)
                 
                 
                 
                 
                .onSubmit { commitName() }
                .onChange(of: nameIsFocused) { focused in
                    if !focused { commitName() }
                     
                     
                    if focused { sentName = nil }
                }
                .onDisappear { commitName() }
                 
                 
                 
                 
                 
                 
                .onChange(of: profile.label) { stored in
                    sentName = nil
                    if !nameIsFocused { name = stored }
                }
    }

     
     
     
     
    static func seeds(
        profile: ClashProfileSnapshot, recipe: ConfigurationRecipe?,
        sources: [ConfigurationSourceRecord], schemes: [ConfigurationRuleScheme]
    ) -> (sources: Set<String>, scheme: String) {
        if let recipe { return (Set(recipe.sources.map(\.id)), recipe.ruleSchemeID) }
        let own = "legacy-" + profile.id.rawValue
        let ownRules = "rules-" + own
        return (
            Set(sources.map(\.id).filter { $0 == own }),
            schemes.contains { $0.id == ownRules } ? ownRules : ""
        )
    }

    private func toggleSource(_ id: String) {
        let was = chosenSources.contains(id)
        if was { chosenSources.remove(id) } else { chosenSources.insert(id) }
        let ids = sources.map(\.id).filter { chosenSources.contains($0) }
        ClashMacDebugLog.note("page.toggle \(id) \(was ? "off" : "on") → setSources \(ids)")
        actions.setSources(ids)
    }

     
     
     
     
     
     
     
     
     
     
     
    private var offersOriginal: Bool { recipe.map { $0.sources.count == 1 } ?? profile.canEditSource }
     
     
    private var usesOriginal: Bool { recipe.map { $0.preservesOriginal == true } ?? true }
     
     
    private var originalSourceName: String? {
        let id = recipe?.sources.first?.id ?? "legacy-" + profile.id.rawValue
        return sources.first { $0.id == id }?.label ?? (recipe == nil ? profile.label : nil)
    }

     
     
     
     
     
     
     
    struct FollowLinkRow: Equatable {
        enum TurningOn: Equatable {
             
            case saves
             
            case asksToReplace
             
            case asksForLink
        }
        enum Control: Equatable {
             
            case hidden
            case toggle(isOn: Bool, turningOn: TurningOn)
             
             
            case noteOnly
        }
        let control: Control
         
        let note: ClashDisplayText?

         
        init(_ state: ConfigurationUpdateFollowing?, canPickLink: Bool) {
            guard let state else { (control, note) = (.hidden, nil); return }
            note = ClashProfileSnapshot.sourceUpdatesNote(state, canPickLink: canPickLink)
            if !ClashProfileSnapshot.offersSourceUpdatesSwitch(state, canPickLink: canPickLink) {
                control = .noteOnly
            } else if state == .copyWithoutOrigin {
                control = .toggle(isOn: false, turningOn: .asksForLink)
            } else {
                control = .toggle(isOn: state == .following,
                                  turningOn: ClashProfileSnapshot.turningOnReplacesChanges(state) ? .asksToReplace : .saves)
            }
        }
    }

     
     
     
     
     
     
     
    @ViewBuilder
    private var followLinkRow: some View {
        let row = FollowLinkRow(updateFollowing, canPickLink: !linksToRejoin.isEmpty)
        switch row.control {
        case .hidden:
            EmptyView()
        case let .toggle(isOn, turningOn):
            Toggle(isOn: Binding(get: { isOn }, set: { on in
                switch (on, turningOn) {
                case (true, .asksToReplace): asksToGoBackToLink = true
                case (true, .asksForLink): asksWhichLink = true
                default: actions.setSourceUpdates(on)
                }
            })) {
                Text(clash: .copy("Follow Link Updates"))
                if let note = row.note {
                    Text(clash: note).accessibilityIdentifier("configuration-center.configuration.source-updates.note")
                }
            }
            .toggleStyle(.switch)
            .disabled(profile.isBusy)
            .accessibilityIdentifier("configuration-center.configuration.source-updates")
            .alert(Text(clash: .copy("Go Back to the Link’s Content?")), isPresented: $asksToGoBackToLink) {
                Button(role: .cancel) {} label: { Text(clash: .copy("Cancel")) }
                Button(role: .destructive) { actions.setSourceUpdates(true) } label: { Text(clash: .copy("Go Back")) }
                    .accessibilityIdentifier("configuration-center.configuration.source-updates.confirm")
            } message: {
                Text(clash: .copy("What was changed in this configuration here will be replaced."))
            }
            .confirmationDialog(Text(clash: .copy("Go Back to the Link’s Content?")), isPresented: $asksWhichLink,
                                titleVisibility: .visible) {
                ForEach(linksToRejoin, id: \.id) { link in
                    Button(role: .destructive) { actions.followLink(link.id) } label: {
                        Text(clash: .format("Follow “%@”", [link.label]))
                    }
                    .accessibilityIdentifier("configuration-center.configuration.source-updates.link")
                }
                Button(role: .cancel) {} label: { Text(clash: .copy("Cancel")) }
            } message: {
                Text(clash: .copy("What was changed in this configuration here will be replaced."))
            }
        case .noteOnly:
            if let note = row.note {
                Text(clash: note)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("configuration-center.configuration.source-updates.note")
            }
        }
    }

     
     
    private var librarySourceInterval: Int? {
        guard let id = recipe?.sources.first?.id, recipe?.sources.count == 1 else { return nil }
        return sources.first { $0.id == id }?.updateIntervalHours
    }

    private func chooseScheme(_ id: String) {
         
         
        if offersOriginal, usesOriginal, let recipe {
            actions.setOriginalUse(false)
            if id != recipe.ruleSchemeID { chosenScheme = id; actions.setScheme(id) }
            return
        }
        guard id != chosenScheme || recipe == nil else { return }
        chosenScheme = id
        ClashMacDebugLog.note("page.choose scheme \(id)")
        actions.setScheme(id)
    }

     

     
     
    private var outlineForm: ConfigurationOutlineForm {
        recipe.map { $0.preservesOriginal == true ? .original : .composed } ?? .original
    }

    private struct OutlineKey: Hashable {
        let profile: String
        let generation: UInt64
        let customRules: Int
        let reads: Int
        let scheme: String?
        let original: Bool?
    }

    private var outlineKey: OutlineKey {
        OutlineKey(profile: profile.id.rawValue, generation: libraryGeneration, customRules: customRules.rules.count,
                   reads: outlineReads, scheme: recipe?.ruleSchemeID, original: recipe?.preservesOriginal)
    }

    private func readOutline() async {
        guard let load = actions.loadOutline else { return }
        do {
            let rows = try await load(customRules.rules.count)
            guard !Task.isCancelled else { return }
            outlineRows = rows
        } catch {
            ClashMacDebugLog.note("page.outline \(profile.id.rawValue): \(error.localizedDescription)")
        }
        await readPageObjects()
    }

     
     
     
    private func readPageObjects() async {
        guard let editing = actions.settingsSection,
              let document = try? await editing.load(.inbound), !Task.isCancelled else { return }
        let listsOriginal = outlineForm == .original && profileURL == nil
            && actions.originalGroupPage != nil && actions.originalEntrySettings != nil
        var schemeGroups: [(name: String, type: String)]?
        if outlineForm == .composed, actions.schemeGroupPage != nil, let load = actions.loadSchemeGroups {
            schemeGroups = await load()
            guard !Task.isCancelled else { return }
        }
        pageObjects = ClashMacPageObjects.read(document.running, listsOriginal: listsOriginal, schemeGroups: schemeGroups)
        if let catalog = document.catalog {
            searchFields = ClashMacSearchField.index(catalog, copy: fieldCopy, locale: locale,
                                                    lanShareKeys: editing.lanShare?.keys ?? [])
        }
    }

     
    private func fieldPage(_ field: ClashMacSearchField) -> AnyView? {
        guard let editing = actions.settingsSection else { return nil }
         
        if field.onLANShare, let lanShare = editing.lanShare { return lanShare.page() }
        let known = field.basePath.isEmpty
            ? ConfigurationOutline.knownTopLevelKeys.filter { ConfigurationOutline.section(forTopLevelKey: $0) == field.section }
            : []
        return AnyView(ClashMacSettingsSectionPage(section: field.section, basePath: field.basePath, knownKeys: known, actions: editing)
            .navigationTitle(Text(clash: ClashMacConfigurationOutlineCard.title(field.section))))
    }

     
     
     
    private func objectPage(_ object: ClashMacPageObject) -> AnyView? {
        switch object.kind {
        case .group:
            return outlineForm == .composed ? actions.schemeGroupPage?(object.name) : actions.originalGroupPage?(object.name)
        case .ruleSet:
            guard let entry = actions.originalEntrySettings else { return nil }
            return AnyView(ClashMacSettingsSectionPage(section: .ruleProviders, basePath: ["rule-providers", object.name],
                                                      knownKeys: [], actions: entry)
                .navigationTitle(Text(verbatim: object.name)))
        case .listener:
            guard let editing = actions.settingsSection else { return nil }
            return AnyView(ClashMacObjectListPage(section: .inbound, listPath: ["listeners"], actions: editing, only: object.index)
                .navigationTitle(Text(verbatim: object.name)))
        }
    }

     
     
    private func cardPageReturned() {
        Task { @MainActor in
            scripts = await scriptsActions.load()
            if let load = actions.customRules?.load { customRules = await load() }
            outlineReads &+= 1
        }
    }

    private var scriptValue: ClashDisplayText {
        scripts.selectedID.flatMap { id in scripts.scripts.first { $0.id == id } }.map { .verbatim($0.label) } ?? .copy("None")
    }

     
     
    private func outlineDestination(_ section: ConfigurationOutlineSection) -> ClashMacOutlineDestination? {
        switch section {
        case .customRules:
            guard let rules = actions.customRules else { return nil }
            let initial = customRules
            return .page {
                AnyView(ClashMacCustomRulesPage(actions: rules, initial: initial)
                    .navigationTitle(Text(clash: .copy("Custom Rules"))))
            }
        case .overrideScript:
            let initial = scripts
            return .page {
                AnyView(ClashMacScriptsPage(actions: scriptsActions, initial: initial, quickAdd: scriptsQuickAdd)
                    .navigationTitle(Text(clash: .copy("Overrides and Scripts"))))
            }
         
         
         
         
         
         
         
         
        case .general, .dns, .sniffer, .mitm, .inbound, .ntp, .experimental:
            guard let editing = actions.settingsSection else { return actions.outlineDestination(section) }
            let known = ConfigurationOutline.knownTopLevelKeys.filter { ConfigurationOutline.section(forTopLevelKey: $0) == section }
            return .page {
                AnyView(ClashMacSettingsSectionPage(section: section, basePath: [], knownKeys: known, actions: editing)
                    .navigationTitle(Text(clash: ClashMacConfigurationOutlineCard.title(section))))
            }
         
         
        case .tunnels:
            guard let editing = actions.settingsSection else { return nil }
            return .page {
                AnyView(ClashMacObjectListPage(section: section, listPath: ["tunnels"], actions: editing)
                    .navigationTitle(Text(clash: ClashMacConfigurationOutlineCard.title(section))))
            }
         
         
        case .unknown:
            guard let editing = actions.settingsSection else { return nil }
            let editSource = editSourceAction
            return .page {
                AnyView(ClashMacSettingsSectionPage(section: section, basePath: [], knownKeys: [], actions: editing,
                                                   readOnly: true, editSource: editSource)
                    .navigationTitle(Text(clash: ClashMacConfigurationOutlineCard.title(section))))
            }
         
         
         
         
         
        case .proxies where outlineForm == .composed && isComposed,
             .proxyProviders where outlineForm == .composed && isComposed:
            return .page { [sources, recipe, actions] in
                AnyView(ClashMacConfigurationSourcesPage(
                    sources: sources, chosen: $chosenSources, recipe: recipe, actions: actions, toggle: toggleSource,
                    section: section
                )
                .navigationTitle(Text(clash: ClashMacConfigurationOutlineCard.title(section))))
            }
        default:
            if let destination = actions.outlineDestination(section) { return destination }
             
             
            if outlineForm == .original, profile.canEditSource,
               [.proxies, .proxyProviders, .proxyGroups, .rules, .ruleProviders, .subRules].contains(section) {
                return .open { actions.editSource() }
            }
            return nil
        }
    }

    private var configurationCard: some View {
        ClashMacConfigurationOutlineCard(
            rows: outlineRows,
            form: outlineForm,
            scheme: outlineForm == .composed ? outlineScheme : nil,
            original: offersOriginal
                ? ClashMacOriginalChoice(isChosen: usesOriginal, sourceName: originalSourceName, choose: { actions.setOriginalUse(true) })
                : nil,
            schemes: schemeChoices ?? schemes,
            usage: schemeUsage,
            followedLinks: followedLinks,
            scriptValue: scriptValue,
            customRules: customRules.rules.count,
            busy: profile.isBusy,
            configurationLabel: profile.label,
            destination: outlineDestination,
            onReturn: cardPageReturned,
            chooseScheme: chooseScheme
        )
    }

    private var pageActions: some View {
        ClashMacConfigurationPageActions(
            editSource: editSourceAction,
            compile: actions.compile == nil ? nil : compileNow,
            compiling: compiling,
            export: actions.export,
            saveAsScheme: actions.saveAsScheme == nil ? nil : askSchemeName,
            duplicate: profile.canDuplicate ? duplicate : nil,
            duplicating: duplicating
        )
    }

     
     
    private var editSourceAction: (@MainActor () -> Void)? {
        if outlineForm == .composed, let open = actions.editSchemeSource { return open }
        return profile.canEditSource ? actions.editSource : nil
    }

    private func askSchemeName() {
        schemeName = profile.label
        asksSchemeName = true
    }

    private func compileNow() {
        guard let compile = actions.compile, !compiling else { return }
        compiling = true
        Task { @MainActor in
            let result = await compile()
            compiling = false
            compilePresentation = ClashMacCompilePresentation(result: result)
        }
    }

     
     
     
     
     
    @ViewBuilder
    private var linkRows: some View {
        if recipe == nil {
             
             
            Toggle(isOn: Binding(get: { profile.autoUpdate }, set: { actions.setAutoUpdate($0) })) {
                Text(clash: .copy("Automatic Updates"))
            }
            .toggleStyle(.switch)
            .accessibilityIdentifier("configuration-center.config-url.auto-update")
        }
         
         
         
        HStack(spacing: ClashTheme.Spacing.compact) {
            Button { actions.updateSource() } label: { Text(clash: .copy("Update Source")) }
                .disabled(profile.isBusy || actions.isUpdatingSource)
                .accessibilityIdentifier("configuration-center.config-url.update")
            Spacer()
            if actions.isUpdatingSource {
                ProgressView().controlSize(.small)
            } else {
                Text(clash: Self.lastUpdated(profile.lastUpdatedAt, locale: locale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(profile.lastUpdatedAt.map { Self.dateFormatters.formatter(for: locale).string(from: $0) } ?? "")
                    .accessibilityIdentifier("configuration-center.config-url.updated")
            }
        }
         
         
        if let updateError = actions.updateError {
            Text(verbatim: updateError)
                .foregroundStyle(.red)
                .accessibilityIdentifier("configuration-center.config-url.update-error")
        }
        ClashRoutedViewLink {
            ClashMacProfileURLSettingsPage(
                profileURL: profileURL, actions: actions, ownFile: recipe == nil,
                autoUpdate: profile.autoUpdate, profileInterval: profile.updateIntervalHours,
                libraryInterval: librarySourceInterval
            )
            .navigationTitle(Text(clash: .copy("Profile URL Settings")))
        } label: {
            Text(clash: .copy("Profile URL Settings"))
        }
        .accessibilityIdentifier("configuration-center.config-url.settings")
    }

    @ViewBuilder
    private var trafficRow: some View {
        if let usage = profile.subscription {
            LabeledContent {
                Text(clash: ClashMacSubscriptionUsageCopy.traffic(ConfigurationSubscriptionUsage(
                    upload: usage.uploadBytes, download: usage.downloadBytes, total: usage.totalBytes,
                    expire: usage.expiration.map { Int64($0.timeIntervalSince1970) } ?? 0
                )))
            } label: {
                Text(clash: .copy("Traffic"))
            }
        }
    }

     
    static func lastUpdated(_ date: Date?, locale: Locale) -> ClashDisplayText {
        guard let date else { return .copy("Never") }
        return .verbatim(date.formatted(Date.RelativeFormatStyle(presentation: .named, locale: locale, calendar: .current)))
    }

    private var heldBack: some View {
        Section {
            if profile.heldBackUpdates.count > Self.heldBackRowsShownAtOnce {
                DisclosureGroup(isExpanded: $showsAllHeldBack) {
                    heldBackRows
                } label: {
                    Text(clash: .copy("Details"))
                }
                .accessibilityIdentifier("configuration-center.configuration.held-back.disclosure")
            } else {
                heldBackRows
            }
            Button { actions.dismissHeldBack() } label: { Text(clash: .copy("Keep My Settings")) }
                .accessibilityIdentifier("configuration-center.configuration.held-back.dismiss")
        } footer: {
            Text(clash: .format(
                "The last update changed %@ setting(s) that your app-wide settings override. Each is shown with the new value; adopt it or keep yours.",
                [String(profile.heldBackUpdates.count)]
            ))
        }
    }

    private var heldBackRows: some View {
        ForEach(profile.heldBackUpdates) { item in
            LabeledContent {
                Button { actions.adoptHeldBack(item.keyPath) } label: {
                    Text(clash: item.change == .removed ? .copy("Follow Removal") : .copy("Use New Value"))
                }
                .accessibilityIdentifier("configuration-center.configuration.held-back.adopt.\(item.keyPath)")
            } label: {
                Text(verbatim: item.keyPath).monospaced()
                 
                Text(clash: Self.heldBackLine(item))
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("configuration-center.configuration.held-back.item.\(item.keyPath)")
        }
    }

    private static func heldBackLine(_ item: ClashProfileHeldBackUpdate) -> ClashDisplayText {
        switch item.change {
        case .removed: .format("Removed by the profile URL · yours: %@", [item.appValue])
        case .added, .changed: .format("Profile URL now: %@ · yours: %@", [item.newValue ?? "", item.appValue])
        }
    }

    private static let dateFormatters = ClashMacDateFormatterCache(dateStyle: .medium, timeStyle: .short)

     
     
    enum NameCommit: Equatable {
        case nothing, restore, send(String)

         
         
         
        static func decide(typed: String, stored: String, lastSent: String?) -> NameCommit {
            let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != stored else { return .restore }
            return trimmed == lastSent ? .nothing : .send(trimmed)
        }
    }

    private func commitName() {
        switch NameCommit.decide(typed: name, stored: profile.label, lastSent: sentName) {
        case .restore: name = profile.label
        case .nothing: break
        case .send(let trimmed):
            sentName = trimmed
            actions.rename(trimmed)
        }
    }
}

 
 
struct ClashMacTrailingChevron: View {
    var expanded: Bool = false

    var body: some View {
        ClashSymbolImage(symbol: .chevronForward)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(expanded ? 90 : 0))
    }
}

 
 
 
struct ClashMacPushRowLabel: View {
    let title: ClashDisplayText
    var value: ClashDisplayText? = nil
     
     
     
    @Environment(\.isEnabled) private var isEnabled
    init(_ title: ClashDisplayText, value: ClashDisplayText? = nil) { self.title = title; self.value = value }

    var body: some View {
        HStack(spacing: ClashTheme.Spacing.compact) {
            Text(clash: title).foregroundStyle(isEnabled ? .primary : .tertiary)
            Spacer()
            if let value {
                Text(clash: value).foregroundStyle(isEnabled ? .secondary : .tertiary).lineLimit(1).truncationMode(.tail)
            }
             
             
            if isEnabled { ClashMacTrailingChevron() }
        }
        .contentShape(Rectangle())
    }
}

 
 
 
struct ClashMacValueRow: View {
    let title: ClashDisplayText
    let value: ClashDisplayText
    init(_ title: ClashDisplayText, value: ClashDisplayText) { self.title = title; self.value = value }

    var body: some View {
        HStack(spacing: ClashTheme.Spacing.compact) {
            Text(clash: title)
            Spacer()
            Text(clash: value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }
}

 
struct ClashMacScopeRequest: Identifiable {
    let source: ConfigurationSourceRecord
     
     
     
    var chosen = true
    var id: String { source.id }
}


 

 
 
 
struct ClashMacConfigurationSourceRow: View {
    let source: ConfigurationSourceRecord
    let chosen: Bool
     
    var locked = false
    let toggle: () -> Void
    let inspect: () -> Void

    var body: some View {
        HStack(spacing: ClashTheme.Spacing.compact) {
             
             
             
            let checkbox = Toggle(isOn: Binding(get: { chosen }, set: { _ in toggle() })) {
                Text(verbatim: source.label)
                Text(clash: .count(source.nodeCount, one: "%@ node", other: "%@ nodes"))
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("configuration-center.configuration.source.\(source.id)")
            if locked {
                 
                 
                 
                 
                checkbox
                    .disabled(true)
                    .help(Text(clash: .copy("A configuration needs a source for its nodes. Turn on another source first.")))
            } else {
                checkbox
            }
            Spacer()
             
             
             
             
             
             
             
             
             
            Button(action: inspect) { Image(systemName: "info.circle") }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(clash: .copy("Node Collections")))
                .accessibilityIdentifier("configuration-center.configuration.scope.\(source.id)")
        }
    }
}

 
 
public struct ClashMacSourceNodes: Equatable, Sendable {
    public struct Node: Hashable, Sendable {
        public let name: String
        public let type: String
        public init(name: String, type: String) { self.name = name; self.type = type }
    }
    public let nodes: [Node]
    public let providers: [Node]
    public init(nodes: [Node], providers: [Node]) { self.nodes = nodes; self.providers = providers }
}

 
 
struct ClashMacSourceNodeLine: Identifiable, Hashable {
    let node: ClashMacSourceNodes.Node
    let isSet: Bool
    var id: String { (isSet ? "set:" : "node:") + node.name + "\u{1F}" + node.type }
}

 
 
 
struct ClashMacConfigurationSourcesPage: View {
    let sources: [ConfigurationSourceRecord]
    @Binding var chosen: Set<String>
    let recipe: ConfigurationRecipe?
    let actions: ClashMacConfigurationInspectorActions
    let toggle: (String) -> Void
     
     
    var section: ConfigurationOutlineSection = .proxies
     
    @State private var brought: [String: ClashMacSourceNodes] = [:]
    @State private var filter = ""
     
    @State private var showsAll = false
    @State private var scopeSource: ClashMacScopeRequest?
     
     
     
     
    @State private var writtenScopes: [String: ConfigurationNodeScope?] = [:]
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale

    private func scope(of id: String) -> ConfigurationNodeScope? {
        if let written = writtenScopes[id] { return written }
        return recipe?.nodeScopes?[id]
    }

    private var shown: [ConfigurationSourceRecord] {
        let offered = Self.offered(sources, chosen: chosen)
        let needle = filter.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return offered }
        return offered.filter { $0.label.localizedCaseInsensitiveContains(needle) }
    }

     
     
     
     
     
    static let firstPage = 100

    static func listed(_ shown: [ConfigurationSourceRecord], chosen: Set<String>, showsAll: Bool) -> [ConfigurationSourceRecord] {
        guard !showsAll, shown.count > firstPage else { return shown }
        var others = 0
        return shown.filter { source in
            if chosen.contains(source.id) { return true }
            others += 1
            return others <= firstPage
        }
    }

     
     
     
     
     
     
     
     
     
     
     
    static func offered(_ sources: [ConfigurationSourceRecord], chosen: Set<String>) -> [ConfigurationSourceRecord] {
        sources.filter { $0.isListedInLibrary || chosen.contains($0.id) }
    }

     
    static func isLast(_ id: String, chosen: Set<String>) -> Bool {
        chosen.count == 1 && chosen.contains(id)
    }

     
     
     
    static func shelves(_ sources: [ConfigurationSourceRecord]) -> [ClashMacNodeLibraryShelf] {
        ClashMacNodeLibraryGroup.allCases.compactMap { group in
            let members = sources.filter { group.contains($0) }
            return members.isEmpty ? nil : ClashMacNodeLibraryShelf(group: group, sources: members)
        }
    }

     
     
    static func lines(_ group: ClashMacSourceNodes, section: ConfigurationOutlineSection) -> [ClashMacSourceNodeLine] {
        let sets = group.providers.map { ClashMacSourceNodeLine(node: $0, isSet: true) }
        return section == .proxyProviders ? sets : group.nodes.map { ClashMacSourceNodeLine(node: $0, isSet: false) } + sets
    }

     
     
    private func readBrought() async {
        guard let read = actions.sourceNodes else { return }
        var next: [String: ClashMacSourceNodes] = [:]
        for source in sources where chosen.contains(source.id) {
            if let group = try? await read(source, scope(of: source.id)) { next[source.id] = group }
        }
        if next != brought { brought = next }
    }

    private var broughtKey: String {
        chosen.sorted().joined(separator: ",") + "|"
            + writtenScopes.map { "\($0.key)=\(String(describing: $0.value))" }.sorted().joined(separator: ",")
    }

    var body: some View {
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        VStack(spacing: 0) {
        TextField(text: $filter, prompt: Text(clash: .copy("Filter"))) { Text(clash: .copy("Filter")) }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .accessibilityIdentifier("configuration-center.configuration.sources.filter")
        let matching = shown
        let listed = Self.listed(matching, chosen: chosen, showsAll: showsAll)
        List {
            ForEach(Self.shelves(listed)) { shelf in
                Section {
                    ForEach(shelf.sources) { source in
                         
                         
                         
                        let locked = Self.isLast(source.id, chosen: chosen)
                        ClashMacConfigurationSourceRow(
                            source: source, chosen: chosen.contains(source.id), locked: locked,
                            toggle: { if !locked { toggle(source.id) } },
                            inspect: { scopeSource = ClashMacScopeRequest(source: source, chosen: chosen.contains(source.id)) }
                        )
                    }
                } header: {
                    Text(clash: .copy(shelf.group.title))
                } footer: {
                     
                    if shelf.sources.contains(where: { Self.isLast($0.id, chosen: chosen) }) {
                        Text(clash: .copy("At least one node source stays on."))
                    }
                }
            }
            if listed.count < matching.count {
                Section {
                    Button { showsAll = true } label: { Text(clash: .format("Show all %@ sources", [String(matching.count)])) }
                        .accessibilityIdentifier("configuration-center.configuration.sources.show-all")
                }
            }
             
             
             
             
             
            let nodeTypes = ClashMacValueWords.valueNames(path: "proxies[*].type", copy: copy, locale: locale)
            let setTypes = ClashMacValueWords.valueNames(path: "proxy-providers.*.type", copy: copy, locale: locale)
            ForEach(sources.filter { chosen.contains($0.id) }) { source in
                if let group = brought[source.id], !Self.lines(group, section: section).isEmpty {
                    Section {
                        ForEach(Self.lines(group, section: section)) { line in
                            LabeledContent {
                                Text(verbatim: (line.isSet ? setTypes : nodeTypes)[line.node.type.lowercased()] ?? line.node.type)
                            } label: { Text(verbatim: line.node.name) }
                                .accessibilityIdentifier("configuration-center.configuration.source-node")
                        }
                    } header: {
                        Text(verbatim: source.label)
                    }
                }
            }
        }
        .listStyle(.inset)
        }
        .task(id: broughtKey) { await readBrought() }
        .sheet(item: $scopeSource) { request in
            ClashMacScopeSheet(request: request, initial: scope(of: request.source.id), actions: actions, done: { scope in
                writtenScopes[request.source.id] = .some(scope)
                if scope?.isEmpty == true { chosen.remove(request.source.id) } else { chosen.insert(request.source.id) }
                scopeSource = nil
            }, back: { scopeSource = nil },
            refusesEmpty: chosen.count == 1 && chosen.contains(request.source.id))
        }
    }
}

 
 
 
 
 
struct ClashMacScopeSheet: View {
    let request: ClashMacScopeRequest
     
     
    let initial: ConfigurationNodeScope?
    let actions: ClashMacConfigurationInspectorActions
    let done: (ConfigurationNodeScope?) -> Void
    let back: () -> Void
     
    var refusesEmpty = false

    var body: some View {
        ClashMacNodeScopePage(
            source: request.source,
            load: { [actions] in try await actions.loadScopeChoices(request.source) },
            initial: initial,
            save: { scope in
                actions.setScope(request.source.id, scope)
                done(scope)
            },
            back: back,
            closeTitle: .copy("Cancel"),
            savesUnchanged: !request.chosen,
            refusesEmpty: refusesEmpty
        )
    }
}


 
 
 
 
 
struct ClashMacProfileURLSettingsPage: View {
    let profileURL: String?
    let actions: ClashMacConfigurationInspectorActions
     
    let ownFile: Bool
    let autoUpdate: Bool
    let profileInterval: Int
     
    let libraryInterval: Int?
    @State private var linkDraft: String
    @FocusState private var linkIsFocused: Bool
    @State private var interval: Int
    @State private var saving = false
    @State private var failure: String?
    @State private var copied = false
    @State private var confirmsCredentialRemoval = false

    init(profileURL: String?, actions: ClashMacConfigurationInspectorActions, ownFile: Bool,
         autoUpdate: Bool, profileInterval: Int, libraryInterval: Int?) {
        self.profileURL = profileURL; self.actions = actions; self.ownFile = ownFile
        self.autoUpdate = autoUpdate; self.profileInterval = profileInterval; self.libraryInterval = libraryInterval
        _linkDraft = State(initialValue: profileURL ?? "")
        _interval = State(initialValue: ownFile ? profileInterval : libraryInterval ?? 0)
    }

    var body: some View {
        Form {
            Section {
                if let save = actions.saveLibraryLink {
                     
                    TextField(text: $linkDraft, prompt: Text(verbatim: "https://example.com/config.yaml")) {
                        Text(clash: .copy("Profile URL"))
                    }
                    .focused($linkIsFocused)
                    .disabled(saving)
                    .onSubmit { commitLink(save) }
                    .onChange(of: linkIsFocused) { focused in if !focused { commitLink(save) } }
                    .onDisappear { commitLink(save) }
                    .accessibilityIdentifier("configuration-center.config-url.link")
                } else if let profileURL {
                    LabeledContent {
                        Text(verbatim: profileURL).textSelection(.enabled).lineLimit(2).multilineTextAlignment(.trailing)
                    } label: {
                        Text(clash: .copy("Profile URL"))
                    }
                }
                intervalRow
                if let failure {
                    Text(verbatim: failure).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("configuration-center.config-url.link-error")
                }
            } footer: {
                if actions.saveLibraryLink != nil, actions.libraryLinkSharedBy > 1 {
                    Text(clash: .format("%@ configurations use this link; changing it changes it for all of them.",
                                       [String(actions.libraryLinkSharedBy)]))
                }
            }
            Section {
                 
                 
                 
                 
                 
                Button {
                    guard actions.copyProfileURL() else { return }
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        copied = false
                    }
                } label: {
                    HStack {
                        Text(clash: .copy("Copy Profile URL"))
                        Spacer()
                        if copied { Text(clash: .copy("Copied")).foregroundStyle(.secondary) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("configuration-center.config-url.copy")
                Button { confirmsCredentialRemoval = true } label: { Text(clash: .copy("Remove Stored URL Credentials")) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("configuration-center.config-url.strip")
            }
        }
        .formStyle(.grouped)
        .alert(Text(clash: .copy("Remove Stored URL Credentials")), isPresented: $confirmsCredentialRemoval) {
            Button(role: .destructive) { actions.stripCredentials() } label: { Text(clash: .copy("Remove Stored URL Credentials")) }
                .accessibilityIdentifier("configuration-center.config-url.strip.confirm")
            Button(role: .cancel) {} label: { Text(clash: .copy("Cancel")) }
        } message: {
            Text(clash: .copy("The saved profile URL carries sign-in details or query values. Removing them keeps the scheme, host and path only, and may require re-importing if the provider needs them."))
        }
    }

    @ViewBuilder
    private var intervalRow: some View {
        if ownFile {
            Picker(selection: Binding(get: { interval }, set: { hours in interval = hours; actions.setInterval(hours) })) {
                ForEach([1, 3, 6, 12, 24, 48, 72], id: \.self) { hours in
                    Text(clash: .format("Every %@ hours", [String(hours)])).tag(hours)
                }
            } label: {
                Text(clash: .copy("Interval"))
            }
            .pickerStyle(.menu)
            .disabled(!autoUpdate)
            .accessibilityIdentifier("configuration-center.config-url.interval")
        } else if let save = actions.saveLibraryInterval {
             
             
             
            Picker(selection: Binding(get: { interval }, set: { hours in commitInterval(hours, save) })) {
                Text(clash: .copy("Manually")).tag(0)
                ForEach(Self.intervalChoices(interval), id: \.self) { hours in
                    Text(clash: .format("Every %@ hours", [String(hours)])).tag(hours)
                }
            } label: {
                Text(clash: .copy("Update Interval"))
            }
            .pickerStyle(.menu)
            .disabled(saving)
            .accessibilityIdentifier("configuration-center.config-url.library-interval")
        } else if let hours = libraryInterval {
             
             
            LabeledContent { Text(clash: .format("Every %@ hours", [String(hours)])) } label: { Text(clash: .copy("Update Interval")) }
        }
    }

     
     
    static func intervalChoices(_ current: Int) -> [Int] {
        let offered = [1, 6, 12, 24, 48, 168]
        return current == 0 || offered.contains(current) ? offered : (offered + [current]).sorted()
    }

    private func commitInterval(_ hours: Int, _ save: @escaping @MainActor (Int) async throws -> Void) {
        guard !saving, hours != interval else { return }
        let was = interval
        interval = hours
        saving = true
        Task { @MainActor in
            defer { saving = false }
            do {
                try await save(hours)
                failure = nil
            } catch is CancellationError {
            } catch {
                interval = was
                failure = error.localizedDescription
            }
        }
    }

     
     
    private func commitLink(_ save: @escaping @MainActor (String) async throws -> Void) {
        let typed = linkDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !saving, typed != (profileURL ?? "") else { return }
        guard !typed.isEmpty else {
            linkDraft = profileURL ?? ""
            return
        }
        saving = true
        Task { @MainActor in
            defer { saving = false }
            do {
                try await save(typed)
                failure = nil
            } catch is CancellationError {
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
