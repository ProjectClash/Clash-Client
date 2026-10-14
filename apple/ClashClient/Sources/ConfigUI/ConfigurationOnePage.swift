#if os(iOS)
import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
 
 

 
 
 
 
@MainActor
final class ConfigurationAlertHosts: ObservableObject {
    @Published private(set) var stack: [UUID] = []

    func appeared(_ id: UUID) {
        stack.removeAll { $0 == id }
        stack.append(id)
    }

    func disappeared(_ id: UUID) { stack.removeAll { $0 == id } }

    func isTop(_ id: UUID) -> Bool { stack.last == id }
}

 
 
struct ConfigurationAlertHosting {
    let hosts: ConfigurationAlertHosts
}

private struct ConfigurationAlertHostingKey: EnvironmentKey {
    static let defaultValue: ConfigurationAlertHosting? = nil
}

extension EnvironmentValues {
    var configurationAlertHosting: ConfigurationAlertHosting? {
        get { self[ConfigurationAlertHostingKey.self] }
        set { self[ConfigurationAlertHostingKey.self] = newValue }
    }
}

 
 
 
 
struct ConfigurationPushedAlertHost: ViewModifier {
    @ObservedObject var session: ConfigurationEditorSession
    @Environment(\.configurationAlertHosting) private var hosting
    @State private var editingSource = false

    func body(content: Content) -> some View {
        if let hosting {
            content
                .modifier(ConfigurationAlertHost(session: session, hosts: hosting.hosts, editSource: { editingSource = true },
                                                 covered: editingSource))
                .sheet(isPresented: $editingSource, onDismiss: { Task { await session.reload() } }) {
                    if let profile = session.model.profiles.first(where: { $0.id == session.profileID }) {
                        ProfileSourceEditorLoader(profile: profile, model: session.model,
                                                  savesIndependentSource: session.isComposed)
                            .configurationEditorOwnsItsScreen()
                            .clashModalPresentation(.page)
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    func configurationPushedAlertHost(_ session: ConfigurationEditorSession) -> some View {
        modifier(ConfigurationPushedAlertHost(session: session))
    }
}

private struct ConfigurationAlertHost: ViewModifier {
    @ObservedObject var session: ConfigurationEditorSession
    @ObservedObject var hosts: ConfigurationAlertHosts
    let editSource: () -> Void
     
    var covered = false
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .modifier(ConfigurationEditorAlerts(session: session, editSource: editSource,
                                                isActive: hosts.isTop(id) && !covered))
            .onAppear { hosts.appeared(id) }
            .onDisappear { hosts.disappeared(id) }
    }
}

 
 
@MainActor
final class ConfigurationPageState: ObservableObject {
    let model: ProfilesViewModel
    let profileID: String
    let session: ConfigurationEditorSession
    let alertHosts = ConfigurationAlertHosts()
    @Published var sheet: ConfigurationEditorSheet?
    @Published var editingSource = false
    @Published var compiling = false
    @Published var compileAnswer: ConfigurationCompileResult?
    @Published var schemes: [ConfigurationRuleScheme] = []
    @Published var choosing = false
     
     
    @Published var query = ""
    var isSearching: Bool { !ConfigurationPageSearch.normalized(query).isEmpty }
     
     
     
     
    @Published private(set) var libraryRevision = 0

     
    func noting(_ forward: ((ConfigurationLibrarySnapshot) -> Void)?) -> (ConfigurationLibrarySnapshot) -> Void {
        { [weak self] snapshot in
            Task { @MainActor in self?.libraryRevision += 1 }
            forward?(snapshot)
        }
    }

    init(model: ProfilesViewModel, profileID: String, selections: GroupSelectionCarrying?) {
        self.model = model
        self.profileID = profileID
        session = ConfigurationEditorSession(profileID: profileID, model: model, selections: selections)
    }

    func loadSchemes() async {
        schemes = (try? await model.availableRuleSchemes(for: profileID)) ?? []
    }

    func compile() {
        compiling = true
        Task {
            defer { compiling = false }
            compileAnswer = ConfigurationCompileResult(answer: await ProfilesViewModel.compileConfiguration(profileID))
        }
    }

     
     
    func choose(_ choice: ConfigurationSchemeChooser.Choice, setUsesOriginal: ((Bool) async throws -> Void)?) {
        guard let setUsesOriginal else { return }
        let chooser = ConfigurationSchemeChooser(
            form: { [model, profileID] in try await model.loadConfigurationEditorPage(profileID: profileID).form },
            setUsesOriginal: setUsesOriginal,
            switchScheme: { [model, profileID] in try await model.switchConfigurationScheme(profileID, to: $0) })
        choosing = true
        Task {
            defer { choosing = false }
            do {
                try await chooser.choose(choice)
            } catch is CancellationError {
            } catch {
                session.failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            await session.reload()
        }
    }
}

 
 
 
 
struct ConfigurationPageHost: View {
     
     
     
     
    let model: ProfilesViewModel
    let profileID: String
    var libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?
    let content: AnyView
    @StateObject private var state: ConfigurationPageState

    init(model: ProfilesViewModel, profileID: String, libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)? = nil,
         selections: GroupSelectionCarrying? = nil, content: AnyView) {
        self.model = model
        self.profileID = profileID
        self.libraryChanged = libraryChanged
        self.content = content
        _state = StateObject(wrappedValue: ConfigurationPageState(model: model, profileID: profileID, selections: selections))
    }

    private var profile: Profile? { model.profiles.first { $0.id == profileID } }

    var body: some View {
        content
             
             
             
             
            .environment(\.clashConfigurationSearching, state.isSearching)
            .searchable(text: $state.query, prompt: Text(clash: .copy("Search")))
            .environmentObject(state)
            .environmentObject(state.session)
             
             
             
            .task(id: profile?.activeRevision ?? "") { await state.session.reload() }
            .task { await state.loadSchemes() }
            .modifier(ConfigurationAlertHost(session: state.session, hosts: state.alertHosts,
                                             editSource: { state.editingSource = true },
                                             covered: state.sheet != nil || state.compileAnswer != nil || state.editingSource))
            .sheet(item: $state.sheet, onDismiss: { Task { await state.session.reload() } }) { which in
                ConfigurationEditorSheetContent(model: model, profileID: profileID, session: state.session, which: which,
                                                libraryChanged: libraryChanged, close: { state.sheet = nil })
                    .clashModalPresentation(which == .saveAsScheme ? .form : .page)
                    .environment(\.clashProductModalDismiss, nil)
            }
            .sheet(item: $state.compileAnswer) { result in
                ConfigurationCompileResultView(answer: result.answer).clashModalPresentation(.page)
                    .environment(\.clashProductModalDismiss, nil)
            }
            .sheet(isPresented: $state.editingSource, onDismiss: { Task { await state.session.reload() } }) {
                if let profile {
                    ProfileSourceEditorLoader(profile: profile, model: model, savesIndependentSource: state.session.isComposed)
                        .configurationEditorOwnsItsScreen()
                        .clashModalPresentation(.page)
                }
            }
    }
}

 
 
 
 
 
 
 
 
struct ConfigurationPageSections: View {
     
     
    let canUseOriginal: Bool
     
    let setUsesOriginal: ((Bool) async throws -> Void)?
     
    var libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?
    @EnvironmentObject private var state: ConfigurationPageState
    @EnvironmentObject private var session: ConfigurationEditorSession

    var body: some View {
         
        if state.isSearching, let page = session.page {
            ConfigurationPageSearchResults(page: page, query: state.query, libraryChanged: state.noting(libraryChanged))
        } else {
            pageSections
        }
    }

     
     
     
     
     
    @ViewBuilder
    private var pageSections: some View {
        if let page = session.page {
            let current = currentChoice(page.form)
            let own = Self.configurationsOwn(of: page.rows)
            if current != nil || session.isSaving || state.choosing || !own.isEmpty {
                Section {
                    if session.isSaving || state.choosing {
                        HStack(spacing: ClashTheme.Spacing.compact) {
                            ProgressView()
                            Text(clash: .copy("Saving…")).foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("configuration-editor.saving")
                    }
                    if let current {
                        schemeRow(page, current: current)
                    }
                    ForEach(own, id: \.section) { row in
                        sectionRow(row, form: page.form)
                    }
                } header: {
                    Text(clash: .copy("Configuration Override")).accessibilityIdentifier("configuration-editor.override-header")
                } footer: {
                    if current == .original || !own.isEmpty {
                        VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                            if current == .original {
                                Text(clash: Self.originalRulesNote)
                                    .accessibilityIdentifier("configuration-editor.original-rules-note")
                            }
                            if !own.isEmpty {
                                Text(clash: .copy("Custom rules and the override script are this configuration’s own and stay when you switch schemes."))
                            }
                        }
                    }
                }
            }
             
             
             
            Section {
                ForEach(Self.chapters(of: page.rows, form: page.form), id: \.section) { row in
                    sectionRow(row, form: page.form)
                }
            } header: {
                detailsHeader
            }
        } else {
            Section {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("configuration-editor.loading")
            } header: {
                detailsHeader
            }
        }
    }

     
    private var detailsHeader: some View {
        Text(clash: Self.detailsTitle(label: state.model.profiles.first { $0.id == state.profileID }?.label))
            .accessibilityIdentifier("configuration-editor.details-header")
    }

     
     
    static let originalRulesNote: ClashDisplayText =
        .copy("An original configuration runs its own rules, so rule library changes do not reach it; pick a rule scheme above to use them.")

    static func detailsTitle(label: String?) -> ClashDisplayText {
        guard let label, !label.trimmingCharacters(in: .whitespaces).isEmpty else { return .copy("Configuration Details") }
        return .format("%@ Configuration Details", [label])
    }

     
     
     
     
     
    static func chapters(of rows: [ConfigurationOutlineRow],
                         form: ProfilesViewModel.ConfigurationEditorPage.Form = .original) -> [ConfigurationOutlineRow] {
        let elsewhere = notChapters(form: form)
        return rows.filter { !$0.section.isConfigurationsOwn && ConfigurationEditorCopy.drawsRow($0) && !elsewhere.contains($0.section) }
    }

     
     
     
     
    static func notChapters(form: ProfilesViewModel.ConfigurationEditorPage.Form) -> Set<ConfigurationOutlineSection> {
        []
    }

     
    static func configurationsOwn(of rows: [ConfigurationOutlineRow]) -> [ConfigurationOutlineRow] {
        rows.filter(\.section.isConfigurationsOwn)
    }

     

    private func currentChoice(_ form: ProfilesViewModel.ConfigurationEditorPage.Form) -> ConfigurationSchemeChooser.Choice? {
        switch form {
        case .composed(let scheme, _): return .scheme(scheme.id)
        case .original: return canUseOriginal && setUsesOriginal != nil ? .original : nil
        }
    }

     
     
    private func choices(_ page: ProfilesViewModel.ConfigurationEditorPage) -> [ConfigurationRuleScheme] {
        guard case .composed(let scheme, _) = page.form, !state.schemes.contains(where: { $0.id == scheme.id }) else {
            return state.schemes
        }
        return [scheme] + state.schemes
    }

     
     
     
     
     
    private func schemeRow(_ page: ProfilesViewModel.ConfigurationEditorPage,
                           current: ConfigurationSchemeChooser.Choice) -> some View {
        var shared: ClashDisplayText?
        if case .composed(_, let ownership) = page.form { shared = Self.sharedBy(ownership) }
         
         
         
        let all = choices(page)
        let builtinIDs = Set(ConfigurationBuiltins.schemes.map(\.id))
        let builtins = all.filter { builtinIDs.contains($0.id) }
        return Picker(selection: Self.schemeSelection(current: current, choose: choose)) {
            ForEach(builtins) { scheme in
                Text(verbatim: scheme.displayLabel).tag(ConfigurationSchemeChooser.Choice.scheme(scheme.id))
            }
            if canUseOriginal, setUsesOriginal != nil {
                Text(clash: .copy("Original")).tag(ConfigurationSchemeChooser.Choice.original)
            }
            ForEach(all.filter { !builtinIDs.contains($0.id) }) { scheme in
                Text(verbatim: scheme.displayLabel).tag(ConfigurationSchemeChooser.Choice.scheme(scheme.id))
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(clash: .copy("Rule Scheme"))
                if let shared { Text(clash: shared).font(.caption).foregroundStyle(.secondary) }
                if let follows = Self.followsLine(page.followedLink) {
                    Text(clash: follows).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .pickerStyle(.menu)
        .disabled(session.isSaving || state.choosing)
        .accessibilityIdentifier("configuration-editor.rule-scheme")
    }

    private func choose(_ choice: ConfigurationSchemeChooser.Choice) {
        state.choose(choice, setUsesOriginal: setUsesOriginal)
    }

     
     
    static func schemeSelection(current: ConfigurationSchemeChooser.Choice,
                                choose: @escaping (ConfigurationSchemeChooser.Choice) -> Void) -> Binding<ConfigurationSchemeChooser.Choice> {
        Binding(get: { current }, set: { choice in
            guard choice != current else { return }
            choose(choice)
        })
    }

     
    static func sharedBy(_ ownership: ConfigurationSchemePageOwnership) -> ClashDisplayText? {
        if case .own(_, _, let configurations) = ownership, configurations > 1 {
            return .format("Used by %@ configurations", [String(configurations)])
        }
        return nil
    }

     
     
     
    static func followsLine(_ link: String?) -> ClashDisplayText? {
        link.map { .format("Follows the “%@” link", [$0]) }
    }

     

    private func sectionRow(_ row: ConfigurationOutlineRow, form: ProfilesViewModel.ConfigurationEditorPage.Form) -> some View {
        NavigationLink {
            ConfigurationSectionDestination(model: state.model, profileID: state.profileID, session: session,
                                            section: row.section, form: form, alertHosts: state.alertHosts,
                                            libraryChanged: state.noting(libraryChanged))
                .equatable()
                 
                 
                .environment(\.clashProductModalDismiss, nil)
        } label: {
            valueRow(ConfigurationEditorCopy.title(of: row.section),
                     value: row.section == .overrideScript ? overrideScriptName
                        : ConfigurationEditorCopy.value(of: row, snifferEnabled: row.section == .sniffer
                        ? ConfigurationEditorCopy.snifferEnabled(in: session) : nil,
                        mitmEnabled: row.section == .mitm
                        ? ConfigurationEditorCopy.mitmEnabled(in: session) : nil))
        }
        .accessibilityIdentifier("configuration-editor.section.\(row.section.rawValue)")
    }

     
     
    private var overrideScriptName: ClashDisplayText? {
        guard let profile = state.model.profiles.first(where: { $0.id == state.profileID }) else { return nil }
        return Self.overrideScriptName(profile, scripts: ScriptLibrary.load())
    }

    static func overrideScriptName(_ profile: Profile, scripts: [ConfigScript]) -> ClashDisplayText? {
        guard profile.overwriteMode == .script, let id = profile.selectedScriptID,
              let label = scripts.first(where: { $0.id == id })?.label else { return nil }
        return .verbatim(label)
    }

     
     
    @ViewBuilder
    private func valueRow(_ title: String, value: ClashDisplayText?) -> some View {
        if #available(iOS 16.0, *) {
            LabeledContent {
                if let value { Text(clash: value) }
            } label: {
                Text(clash: .copy(title))
            }
        } else {
            valueRowBefore16(title, value: value)
        }
    }

     
     
     
    private func valueRowBefore16(_ title: String, value: ClashDisplayText?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.row) {
            Text(clash: .copy(title))
            Spacer(minLength: ClashTheme.Spacing.row)
            if let value { Text(clash: value).foregroundStyle(.secondary) }
        }
    }
}

 
 
enum ConfigurationPageObject: Equatable {
     
    case originalEntry(String)
     
    case listener(Int)
     
     
    case schemeGroup(String)
     
     
    case originalNode(String)
     
    case lanShare
}

 
 
 
@MainActor
final class ConfigurationSchemeGroupsLoader: ObservableObject {
    struct Row: Identifiable, Equatable, Sendable {
        let name: String
        let type: String
        var id: String { name }
    }

    @Published private(set) var groups: [Row]?
    private var loadedKey: String?
    private var loading: Task<Void, Never>?

    func load(schemeID: String, key: String, model: ProfilesViewModel) {
        guard loadedKey != key, let store = model.configurationLibraryStore else { return }
        loadedKey = key
        loading?.cancel()
        loading = Task { [weak self] in
            let read = try? await Task.detached(priority: .userInitiated) { () -> [Row] in
                let library = try store.snapshot()
                 
                guard let scheme = library.rules.first(where: { $0.id == schemeID })
                        ?? ConfigurationBuiltins.schemes.first(where: { $0.id == schemeID }) else { return [] }
                return try ConfigurationRuleDraft(scheme: scheme, payload: store.ruleSchemePayload(scheme.id)).groups
                    .map { Row(name: $0.name, type: $0.type) }
            }.value
            guard !Task.isCancelled else { return }
            self?.groups = read ?? []
        }
    }
}

 
 
 
 
 
 
 
enum ConfigurationPageSearch {
     
    static let perSection = 30

     
    struct Candidates {
         
         
        var groups: [(name: String, type: String)] = []
        var ruleSets: [String] = []
        var nodes: [(name: String, type: String)] = []
         
        var schemeGroups: [(name: String, type: String)] = []
        var listeners: [(index: Int, title: String, type: String)] = []
        var composed = false
    }

    struct Hit: Identifiable, Equatable {
        let id: String
         
        let title: String
         
        let place: String?
        let section: ConfigurationOutlineSection
         
        let object: ConfigurationPageObject?
    }

    struct Part: Identifiable, Equatable {
        let section: ConfigurationOutlineSection
        let hits: [Hit]
        var id: String { section.rawValue }
    }

    static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

     
     
    static func objects(_ query: String, in candidates: Candidates) -> [Part] {
        let words = normalized(query)
        guard !words.isEmpty else { return [] }
        func matches(_ text: String) -> Bool { text.lowercased().contains(words) }
        var parts: [Part] = []
        let groups = candidates.composed
            ? candidates.schemeGroups.filter { matches($0.name) }.map {
                Hit(id: "group:\($0.name)", title: $0.name, place: nil, section: .proxyGroups, object: .schemeGroup($0.name))
            }
            : candidates.groups.filter { matches($0.name) }.map {
                Hit(id: "group:\($0.name)", title: $0.name, place: nil, section: .proxyGroups, object: .originalEntry($0.name))
            }
        if !groups.isEmpty { parts.append(Part(section: .proxyGroups, hits: Array(groups.prefix(perSection)))) }
        let sets = candidates.ruleSets.filter(matches).map {
            Hit(id: "ruleSet:\($0)", title: $0, place: nil, section: .ruleProviders, object: .originalEntry($0))
        }
        if !sets.isEmpty { parts.append(Part(section: .ruleProviders, hits: Array(sets.prefix(perSection)))) }
        let listeners = candidates.listeners.filter { matches($0.title) || matches($0.type) }.map {
            Hit(id: "listener:\($0.index)", title: $0.title, place: nil, section: .inbound, object: .listener($0.index))
        }
        if !listeners.isEmpty { parts.append(Part(section: .inbound, hits: Array(listeners.prefix(perSection)))) }
        return parts
    }

     
     
    static func settings(_ query: String, in candidates: Candidates, catalog: ConfigurationFieldCatalog?,
                         copy: ConfigurationFieldCopy, locale: Locale) -> [Hit] {
        let words = normalized(query)
        guard !words.isEmpty, let catalog else { return [] }
         
         
         
         
         
         
        var ranked: [[Hit]] = [[], [], []]
        var seen = Set<String>()
        func full(_ rank: Int) -> Bool { ranked[rank].count >= perSection }
        func add(_ hit: Hit, rank: Int) {
            guard seen.insert(hit.id).inserted, !full(rank) else { return }
            ranked[rank].append(hit)
        }
        let nodes = Dictionary(grouping: candidates.nodes) { $0.type.lowercased() }
        let groups = Dictionary(grouping: candidates.composed ? candidates.schemeGroups : candidates.groups) { $0.type.lowercased() }
        let listeners = Dictionary(grouping: candidates.listeners) { $0.type.lowercased() }
        for field in catalog.fields {
             
            if full(0) { break }
             
             
            let path = field.path
            let last = path.split(separator: ".").last.map(String.init) ?? path
            let key = last.firstIndex(of: "[").map { String(last[..<$0]) } ?? last
            let title = copy.title(for: field, key: key, locale: locale)
            guard let rank = rank(words, title: title, key: key, path: path), !full(rank) else { continue }
            let generic = path.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "[*]", options: .regularExpression)
            let top = String(path.prefix { $0 != "." && $0 != "[" })
            let type = bracketed(path)?.lowercased()
            switch top {
            case "proxies":
                guard !candidates.composed, let type else { continue }
                for node in nodes[type] ?? [] {
                    if full(rank) { break }
                    add(Hit(id: "node:\(node.name):\(generic)", title: title, place: node.name,
                            section: .proxies, object: .originalNode(node.name)), rank: rank)
                }
            case "proxy-groups":
                guard let type else { continue }
                for group in groups[type] ?? [] {
                    if full(rank) { break }
                    add(Hit(id: "group:\(group.name):\(generic)", title: title, place: group.name, section: .proxyGroups,
                            object: candidates.composed ? .schemeGroup(group.name) : .originalEntry(group.name)), rank: rank)
                }
            case "rule-providers":
                guard !candidates.composed else { continue }
                for set in candidates.ruleSets {
                    if full(rank) { break }
                    add(Hit(id: "ruleSet:\(set):\(generic)", title: title, place: set, section: .ruleProviders,
                            object: .originalEntry(set)), rank: rank)
                }
            case "listeners":
                guard let type else { continue }
                for listener in listeners[type] ?? [] {
                    if full(rank) { break }
                    add(Hit(id: "listener:\(listener.index):\(generic)", title: title, place: listener.title, section: .inbound,
                            object: .listener(listener.index)), rank: rank)
                }
            case "rules", "sub-rules":
                continue
            case "proxy-providers" where candidates.composed:
                 
                continue
            default:
                let section = ConfigurationOutline.section(forTopLevelKey: top)
                guard section != .unknown else { continue }
                 
                let object: ConfigurationPageObject? = ConfigurationSectionKeys.lanShareKeys.contains(top) ? .lanShare : nil
                add(Hit(id: "setting:\(generic)", title: title, place: nil, section: section, object: object), rank: rank)
            }
        }
        return Array((ranked[0] + ranked[1] + ranked[2]).prefix(perSection))
    }

     
     
    static func rank(_ words: String, title: String, key: String, path: String) -> Int? {
        let title = title.lowercased(), key = key.lowercased()
        if title == words || key == words { return 0 }
        if title.hasPrefix(words) || key.hasPrefix(words) { return 1 }
        if title.contains(words) || key.contains(words) || path.lowercased().contains(words) { return 2 }
        return nil
    }

     
    private static func bracketed(_ path: String) -> String? {
        guard let open = path.firstIndex(of: "["), let close = path[open...].firstIndex(of: "]") else { return nil }
        let inside = String(path[path.index(after: open)..<close])
        return inside.isEmpty || inside == "*" ? nil : inside
    }
}

extension View {
     
     
     
     
     
     
     
     
     
     
     
    func configurationEditorOwnsItsScreen() -> some View {
        environment(\.clashInsideProductModalPresentation, false)
            .environment(\.clashProductModalDismiss, nil)
    }
}

 
 
 
struct ConfigurationPageActions: View {
    @EnvironmentObject private var state: ConfigurationPageState
    @EnvironmentObject private var session: ConfigurationEditorSession

    var body: some View {
        if session.page != nil, !state.isSearching {
            Group {
                Button { state.editingSource = true } label: {
                    Label { Text(clash: .copy("Edit Source")) } icon: { Image(systemName: ClashSymbol.curlybraces.name) }
                }
                .accessibilityIdentifier("configuration-editor.action.edit-source")
                Button { state.compile() } label: {
                    HStack {
                        Label { Text(clash: .copy("Compile Configuration")) } icon: { Image(systemName: ClashSymbol.checkmarkCircle.name) }
                        if state.compiling {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(state.compiling)
                .accessibilityIdentifier("configuration-editor.action.compile")
                Button { state.sheet = .saveAsScheme } label: {
                    Label { Text(clash: .copy("Save as Rule Scheme")) } icon: { Image(systemName: ClashSymbol.squareAndArrowDown.name) }
                }
                .accessibilityIdentifier("configuration-editor.action.save-as-scheme")
            }
            .disabled(session.isSaving)
        }
    }
}

 
 
struct ConfigurationPageSearchResults: View {
    let page: ProfilesViewModel.ConfigurationEditorPage
    let query: String
    var libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?
    @EnvironmentObject private var state: ConfigurationPageState
    @EnvironmentObject private var session: ConfigurationEditorSession
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
    @StateObject private var schemeGroups = ConfigurationSchemeGroupsLoader()

    var body: some View {
        let candidates = self.candidates
        let objects = ConfigurationPageSearch.objects(query, in: candidates)
        let settings = ConfigurationPageSearch.settings(query, in: candidates, catalog: session.catalog?.fieldCatalog,
                                                        copy: fieldCopy, locale: locale)
        if objects.isEmpty && settings.isEmpty {
            Section {
                Text(clash: .copy("No results")).foregroundStyle(.secondary)
                    .onAppear(perform: loadSchemeGroups)
                    .accessibilityIdentifier("configuration-editor.search.none")
            }
        }
        ForEach(objects) { part in
            Section {
                ForEach(part.hits) { hit in row(hit, value: nil) }
            } header: {
                Text(clash: .copy(ConfigurationEditorCopy.title(of: part.section)))
            }
        }
        if !settings.isEmpty {
            Section {
                ForEach(settings) { hit in
                    row(hit, value: hit.place.map { ClashDisplayText.verbatim($0) }
                        ?? ClashDisplayText.copy(hit.object == .lanShare ? "LAN Proxy Share"
                                                    : ConfigurationEditorCopy.title(of: hit.section)))
                }
            } header: {
                Text(clash: .copy("Settings"))
            }
        }
    }

    private func row(_ hit: ConfigurationPageSearch.Hit, value: ClashDisplayText?) -> some View {
        NavigationLink {
            ConfigurationSectionDestination(model: state.model, profileID: state.profileID, session: session,
                                            section: hit.section, form: page.form, alertHosts: state.alertHosts,
                                            libraryChanged: libraryChanged, object: hit.object)
                .equatable()
                .environment(\.clashProductModalDismiss, nil)
        } label: {
            if let value {
                ConfigurationRowLabel(title: .verbatim(hit.title), value: value)
            } else {
                Text(verbatim: hit.title)
            }
        }
        .accessibilityIdentifier("configuration-editor.search.result.\(hit.id)")
        .onAppear(perform: loadSchemeGroups)
    }

     
    private func loadSchemeGroups() {
        guard case .composed(let scheme, _) = page.form else { return }
        schemeGroups.load(schemeID: scheme.id, key: scheme.id, model: state.model)
    }

    private var candidates: ConfigurationPageSearch.Candidates {
        var candidates = ConfigurationPageSearch.Candidates()
        switch page.form {
        case .composed:
            candidates.composed = true
            candidates.schemeGroups = (schemeGroups.groups ?? []).map { ($0.name, $0.type) }
        case .original:
            candidates.groups = OriginalEntry.all(in: session.value(at: ["proxy-groups"])).map { ($0.name, $0.type ?? "") }
            candidates.ruleSets = OriginalEntry.all(in: session.value(at: ["rule-providers"])).map(\.name)
            candidates.nodes = OriginalEntry.all(in: session.value(at: ["proxies"])).map { ($0.name, $0.type ?? "") }
        }
        let items = ConfigurationListLocation.key(["listeners"]).items(in: session.settingsDocument)
        candidates.listeners = items.enumerated().map { index, item in
            let type: String = { if case .string(let value)? = item.topLevelValue("type") { return value }; return "" }()
            return (index, ConfigurationObjectList.title(of: item, index: index), type)
        }
        return candidates
    }
}

 
 
 
enum ConfigurationSectionRoute: Equatable {
     
     
    case schemeRules
    case customRules
    case overrideScript
     
     
    case settings([String])
     
    case objectList([String])
     
    case originalEntries
    case originalRules
    case originalSubRules
    case originalProxies
    case originalProxyProviders
     
     
    case sourcedNodes
     
    case readOnly

     
     
     
     
     
     
     
     
    static func of(_ section: ConfigurationOutlineSection, form: ProfilesViewModel.ConfigurationEditorPage.Form,
                   followsSubscription: Bool) -> ConfigurationSectionRoute {
        let original = form == .original
        switch section {
         
         
         
         
        case .general, .dns, .sniffer, .mitm, .inbound, .ntp, .experimental: return .settings([])
        case .tunnels: return .objectList(["tunnels"])
        case .customRules: return .customRules
        case .overrideScript: return .overrideScript
        case .unknown: return .readOnly
         
         
         
        case .proxies, .proxyProviders:
            guard original else { return .sourcedNodes }
            return section == .proxies ? .originalProxies : .originalProxyProviders
        case .proxyGroups, .rules, .subRules, .ruleProviders:
            guard original else { return .schemeRules }
            switch section {
            case .rules: return .originalRules
            case .subRules: return .originalSubRules
            default: return .originalEntries
            }
        }
    }
}

 
 
 
 
struct ConfigurationSectionDestination: View, Equatable {
     
     
     
     
     
    let model: ProfilesViewModel
    let profileID: String
    @ObservedObject var session: ConfigurationEditorSession
    let section: ConfigurationOutlineSection
    let form: ProfilesViewModel.ConfigurationEditorPage.Form
    @ObservedObject var alertHosts: ConfigurationAlertHosts
    var libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?
     
     
    var object: ConfigurationPageObject? = nil
    @State private var editingSource = false
     
    @Environment(\.configurationLinkedPage) private var shellPage
    @Environment(\.locale) private var locale

    private var profile: Profile? { model.profiles.first { $0.id == profileID } }

     
     
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.profileID == rhs.profileID && lhs.section == rhs.section && lhs.form == rhs.form && lhs.object == rhs.object
            && lhs.session === rhs.session && lhs.alertHosts === rhs.alertHosts && lhs.model === rhs.model
    }

    var body: some View {
        destination
             
            .environment(\.configurationLinkedPage, { linkedPage($0) })
             
            .environment(\.configurationAlertHosting, ConfigurationAlertHosting(hosts: alertHosts))
            .modifier(ConfigurationAlertHost(session: session, hosts: alertHosts, editSource: { editingSource = true },
                                             covered: editingSource))
             
            .onDisappear { Task { await session.reload() } }
            .sheet(isPresented: $editingSource, onDismiss: { Task { await session.reload() } }) {
                if let profile {
                    ProfileSourceEditorLoader(profile: profile, model: model, savesIndependentSource: session.isComposed)
                        .configurationEditorOwnsItsScreen()
                        .clashModalPresentation(.page)
                }
            }
    }

     
     
     
    private func linkedPage(_ page: ConfigurationLinkedPage) -> AnyView? {
        switch page {
        case .owner(.certificatesAndTrust):
            guard let profile else { return nil }
             
             
             
            return AnyView(ProfileRuntimeTrustEditor.opening(profile: profile, sourceYAML: model.sourceYAML(for: profile),
                                                             patchJSON: profile.override.patchJSON) { patchJSON in
                Task {
                    var draft = ProfileAdvancedOverridesDraft(profile: profile)
                    draft.rawPatchJSON = patchJSON
                    do { try await model.updateAdvancedOverrides(draft) } catch {
                        session.failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                    await session.reload()
                }
            })
        case .owner(.tunnelAndRoutes):
            guard let profile else { return nil }
            return AnyView(ConfigurationTunnelRoutesPage(model: model, profile: profile))
        case .owner(.lanSharing):
            return AnyView(ProxyShareConfigurationView(profiles: model, session: session))
        default:
            return shellPage?(page)
        }
    }

    @ViewBuilder
    private var destination: some View {
        if let object {
            switch object {
            case .originalEntry(let name):
                ConfigurationOriginalEntryView(session: session, section: section, name: name)
            case .listener(let index):
                ConfigurationObjectItemView(session: session, location: .key(["listeners"]), index: index)
            case .schemeGroup(let name):
                 
                 
                 
                if case .composed(let scheme, _) = form {
                    ConfigurationSchemeRulesPushed(model: model, profileID: profileID, schemeID: scheme.id,
                                                   focus: .groups, single: .group(name),
                                                   changed: { libraryChanged?($0) })
                }
            case .originalNode(let name):
                ConfigurationOriginalNodePage(session: session, name: name)
            case .lanShare:
                ProxyShareConfigurationView(profiles: model, session: session)
            }
        } else {
            chapter
        }
    }

    @ViewBuilder
    private var chapter: some View {
        switch ConfigurationSectionRoute.of(section, form: form, followsSubscription: session.page?.followsSubscription == true) {
         
         
         
        case .schemeRules:
            if case .composed(let scheme, _) = form {
                ConfigurationSchemeRulesPushed(model: model, profileID: profileID, schemeID: scheme.id,
                                               focus: ConfigurationSchemeRulesPushed.focus(of: section),
                                               changed: { libraryChanged?($0) })
            }
        case .customRules:
            if let profile {
                ProfileProjectionLoader(profile: profile, model: model) { projected in
                    ProfileRulesAdapter(profile: profile, sourceYAML: projected, ownsNavigationContainer: false) { draft in
                        try model.updateRules(draft)
                    }
                }
            }
        case .overrideScript:
            if let profile {
                ProfileOverrideView(profile: profile, rawYAML: model.cachedUIProjectedYAML(for: profile),
                                    configurationCenter: true, ownsNavigationContainer: false,
                                    loadRawYAML: { await model.loadUIProjectedYAML(for: profile) }) {
                    try model.updateOverrideSettings(from: $0)
                }
            }
         
         
         
        case .settings(let basePath):
            ConfigurationSettingsSectionView(session: session, section: section, basePath: basePath)
         
         
        case .objectList(let path):
            ConfigurationObjectListView(session: session, location: .key(path),
                                        title: ClashCopy.string(ConfigurationEditorCopy.title(of: section), locale: locale))
         
        case .originalEntries:
            ConfigurationOriginalEntriesView(session: session, section: section)
        case .originalRules:
            ConfigurationOriginalRulesView(session: session, base: ["rules"], title: .copy(ConfigurationEditorCopy.title(of: .rules)))
        case .originalSubRules:
            ConfigurationOriginalSubRulesView(session: session)
        case .originalProxies:
            ConfigurationOriginalProxiesView(session: session)
        case .originalProxyProviders:
            ConfigurationOriginalProxyProvidersView(session: session)
         
         
         
        case .sourcedNodes:
            ConfigurationNodeSourcesPage(model: model, profileID: profileID, section: section, libraryChanged: libraryChanged)
         
        case .readOnly:
            ConfigurationReadOnlySectionView(session: session, section: section, editSource: { editingSource = true })
        }
    }

}

 
 
 
private struct ConfigurationTunnelRoutesPage: View {
    @ObservedObject var model: ProfilesViewModel
    let profile: Profile

    var body: some View {
        CurrentConfigurationSettingsHost(profiles: model, profile: profile) { settings, reread in
            ProfileBaseDocumentHost(profiles: model, profile: settings.profile) { base in
                ProfileRoutePresetView(profile: settings.profile, sourceYAML: base, ownsNavigationContainer: false,
                                       scopeFooter: settings.scopeSentence) {
                    try await model.updateRoutePreset($0, readAs: settings)
                    await reread()
                }
            }
        }
    }
}

 
 
private struct ConfigurationSchemeRulesPushed: View {
    @ObservedObject var model: ProfilesViewModel
    let profileID: String
    let schemeID: String
     
    var focus: ClashTowerRuleFocus = .all
     
     
    var single: ClashTowerSingleObject? = nil
     
    var opening: ClashTowerListOpening = .list
    let changed: (ConfigurationLibrarySnapshot) -> Void

     
    static func focus(of section: ConfigurationOutlineSection) -> ClashTowerRuleFocus {
        switch section {
        case .rules: .rules
        case .proxyGroups: .groups
        case .ruleProviders: .ruleSets
        case .subRules: .subRules
        default: .all
        }
    }
    @State private var loaded: ConfigurationSchemeRulesLoader.Loaded?
    @State private var failure: String?
    @State private var dismiss = ClashDismissHandle()

    var body: some View {
        Group {
            if let loaded {
                ConfigurationTowerRuleCustomizationAdapter(model: model, scheme: loaded.scheme, library: loaded.library,
                                                           pushed: true, profileID: profileID, changed: changed,
                                                           close: { dismiss() }, focus: focus, savesEachChange: true,
                                                           single: single, opening: opening)
            } else if let failure {
                ClashStatusMessage(text: .copy(failure), kind: .error).padding()
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clashCapturesDismiss(dismiss)
        .task {
            do {
                guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                let library = try await Task.detached(priority: .userInitiated) { try store.snapshot() }.value
                 
                 
                guard let scheme = library.rules.first(where: { $0.id == schemeID })
                        ?? ConfigurationBuiltins.schemes.first(where: { $0.id == schemeID }) else {
                    throw ConfigurationLibraryError.missingDependency(schemeID)
                }
                loaded = ConfigurationSchemeRulesLoader.Loaded(library: library, scheme: scheme)
            } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

 
 
 
struct ConfigurationSchemeChooser {
    enum Choice: Hashable {
        case scheme(String)
         
        case original
    }

    let form: () async throws -> ProfilesViewModel.ConfigurationEditorPage.Form
     
    let setUsesOriginal: (Bool) async throws -> Void
    let switchScheme: (String) async throws -> Void

     
     
     
    func choose(_ choice: Choice) async throws {
        switch choice {
        case .original:
            try await setUsesOriginal(true)
        case .scheme(let id):
            if try await form() == .original {
                try await setUsesOriginal(false)
                 
                 
                if case .composed(let scheme, _) = try await form(), scheme.id == id { return }
            }
            try await switchScheme(id)
        }
    }
}

 
 
 
 
struct ConfigurationEditorSheetContent: View {
    @ObservedObject var model: ProfilesViewModel
    let profileID: String
    @ObservedObject var session: ConfigurationEditorSession
    let which: ConfigurationEditorSheet
    var libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?
    let close: () -> Void

    private var profile: Profile? { model.profiles.first { $0.id == profileID } }

    var body: some View {
        switch which {
        case .saveAsScheme:
            ConfigurationSchemeNameSheet(initial: session.page?.label ?? "") { name in
                Task { await session.saveAsScheme(named: name) }
            }
        }
    }
}

 
 
 
 
 
 
 
struct ConfigurationRulesChapterHost: View {
    let model: ProfilesViewModel
    let profileID: String
    @StateObject private var state: ConfigurationPageState

    init(model: ProfilesViewModel, profileID: String) {
        self.model = model
        self.profileID = profileID
        _state = StateObject(wrappedValue: ConfigurationPageState(model: model, profileID: profileID, selections: nil))
    }

    var body: some View {
        ConfigurationRulesChapterPage(state: state, session: state.session)
            .environmentObject(state)
            .environmentObject(state.session)
            .task { await state.session.reload() }
    }
}

 
 
private struct ConfigurationRulesChapterPage: View {
    let state: ConfigurationPageState
    @ObservedObject var session: ConfigurationEditorSession

    var body: some View {
        if let page = session.page {
            ConfigurationSectionDestination(model: state.model, profileID: state.profileID, session: session,
                                            section: .rules, form: page.form, alertHosts: state.alertHosts)
                .equatable()
                 
                .environment(\.clashProductModalDismiss, nil)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
#endif
