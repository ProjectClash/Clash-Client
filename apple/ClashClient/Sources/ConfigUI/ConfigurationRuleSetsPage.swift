#if os(iOS)
import ClashClientKit
import ClashClientUI
import Foundation
import SwiftUI

 
 
 
 
 

 
 
struct ConfigurationRuleSetsSnapshot: Equatable {
    struct Row: Equatable, Identifiable {
         
         
        let id: String
        let name: String
         
         
        let detail: String
         
         
        let isOn: Bool?
    }

     
     
     
    let brought: [Row]
     
    let mine: [Row]
     
     
     
     
     
    let online: [Row]
     
     
    let note: String?
    var isEmpty: Bool { brought.isEmpty && mine.isEmpty && online.isEmpty }

     
     
    static let broughtTitleKey = "Included in the Rule Scheme"
    static let emptyKey = "This configuration has no rule sets yet."

     
     
     
     
     
     
    static func make(draft: ConfigurationRuleDraft, localSets: [ConfigurationLocalRuleSet],
                     collections: [ConfigurationCollectionEntry], profileID: String,
                     library: ConfigurationLibrarySnapshot, profiles: [LibraryUsage.Configuration], locale: Locale,
                     now: Date = Date(),
                     copy: (ConfigurationCollectionEntry) -> ConfigurationCollectionContentBridge.Cache?
                        = ConfigurationCollectionContentBridge.libraryCopyRecord(of:)) -> Self {
        let sourceID = draft.version.id
        let all = ConfigurationCollection.read(sourceID: sourceID, document: draft.currentDocument(), kind: .rules)
        let own = all.filter { !$0.name.hasPrefix("local-") && !$0.name.hasPrefix("catalog-") }
        let brought = own.map { set -> Row in
            switch ConfigurationRuleSetLine.origin(of: set.definition) {
            case .inProfile:
                 
                 
                return Row(id: set.name, name: set.name, detail: ConfigurationRuleSetLine.detail(
                    nil, count: set.inlineCount, updatedAt: nil, locale: locale, now: now), isOn: nil)
            case let origin:
                let held = collections.first { $0.source.id == sourceID && $0.collection.name == set.name }.flatMap(copy)
                return Row(id: set.name, name: set.name, detail: ConfigurationRuleSetLine.detail(
                    origin, count: held?.count, updatedAt: held?.updatedAt, locale: locale, now: now), isOn: nil)
            }
        }
        let routed = draft.referencedRuleSets
        let mine = localSets.map { set in
             
             
            let count = set.ruleCount
            return Row(id: set.id, name: set.name, detail: ConfigurationRuleSetLine.detail(
                set.link == nil ? .local : .link, count: count > 0 ? count : nil, updatedAt: nil, locale: locale, now: now),
                isOn: routed.contains("local-" + set.id))
        }
         
         
         
        let catalog = ConfigurationRuleCatalog.builtIn.entries
        let online = all.filter { $0.name.hasPrefix("catalog-") }.map { set -> Row in
            let id = String(set.name.dropFirst("catalog-".count))
            let held = collections.first { $0.source.id == sourceID && $0.collection.name == set.name }.flatMap(copy)
            return Row(id: set.name, name: catalog.first { $0.id == id }?.name ?? id,
                       detail: ConfigurationRuleSetLine.detail(ConfigurationRuleSetLine.origin(of: set.definition),
                                                               count: held?.count, updatedAt: held?.updatedAt,
                                                               locale: locale, now: now),
                       isOn: nil)
        }
        return Self(brought: brought, mine: mine, online: online,
                    note: ConfigurationSchemeChangeNote.make(profileID: profileID, library: library, profiles: profiles,
                                                             locale: locale))
    }
}

 
 
 
enum ConfigurationRuleSetLine {
    enum Origin: Equatable { case link, local, inProfile }

     
     
     
    static let linkKey = "Link"
    static let localKey = "Local"
    static let inProfileKey = "In the Profile"
    static let updatedKey = "Last updated %@"

     
     
    static func origin(of definition: OrderedJSON) -> Origin {
        switch definition.topLevelValue("type")?.foundationValue as? String {
        case "http": .link
        case "file": .local
        default: .inProfile
        }
    }

     
     
    static func detail(_ origin: Origin?, count: Int?, updatedAt: Date?, locale: Locale, now: Date = Date()) -> String {
        var parts: [String] = []
        switch origin {
        case .link?: parts.append(ClashCopy.string(linkKey, locale: locale))
        case .local?: parts.append(ClashCopy.string(localKey, locale: locale))
        case .inProfile?: parts.append(ClashCopy.string(inProfileKey, locale: locale))
        case nil: break
        }
        if let count {
            parts.append(ClashCopy.format(count == 1 ? "%@ rule" : "%@ rules", locale: locale, ClashCopy.count(count, locale: locale)))
        }
        if let updatedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = locale
            formatter.unitsStyle = .full
             
             
            let when = formatter.localizedString(for: min(updatedAt, now.addingTimeInterval(-1)), relativeTo: now)
            parts.append(ClashCopy.format(updatedKey, locale: locale, when))
        }
        return parts.joined(separator: " · ")
    }
}

 

 
 
 
 
 
 
 
 
struct ConfigurationRuleSetsPage: View {
    let model: ProfilesViewModel
    let profileID: String
    @ObservedObject var editor: ConfigurationEditorSession
    let form: ProfilesViewModel.ConfigurationEditorPage.Form
    let libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?

    init(model: ProfilesViewModel, profileID: String, editor: ConfigurationEditorSession,
         form: ProfilesViewModel.ConfigurationEditorPage.Form, libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?) {
        self.model = model; self.profileID = profileID; self.editor = editor; self.form = form; self.libraryChanged = libraryChanged
    }

     
     
    static let addedKey = "Rule sets you add are used for “%@”."

    static func addedNote(_ configurationName: String, locale: Locale) -> String {
        ClashCopy.format(addedKey, locale: locale, configurationName)
    }

     
     
    static func prefill(link: String) -> (name: String, link: String)? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ConfigurationLocalRuleSetLines.looksLikeLink(trimmed) else { return nil }
        return (ClashRuleSetSniff.linkStem(trimmed), trimmed)
    }

     
     
     
    @discardableResult
    static func switchMine(_ set: ConfigurationLocalRuleSet, on: Bool, in session: ConfigurationSchemeDraftSession) async -> Bool {
        let key = "local-" + set.id
        return await session.change { draft in
            if on {
                try draft.addRuleSet(key: key, name: set.name, rules: set.rules, defaultRoute: "proxy", link: set.link,
                                     behavior: set.behavior)
            } else {
                draft.removeRuleSet(key)
            }
        }
    }

    private var configurationName: String { model.profiles.first { $0.id == profileID }?.label ?? "" }

    var body: some View {
        if case .composed = form {
            ComposedRuleSets(model: model, profileID: profileID, configurationName: configurationName,
                             libraryChanged: libraryChanged)
        } else {
            ConfigurationOriginalRuleSetsPage(session: editor)
        }
    }
}

 
private struct ComposedRuleSets: View {
    let model: ProfilesViewModel
    let profileID: String
    let configurationName: String
    let libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?
    @StateObject private var session: ConfigurationSchemeDraftSession
     
     
    @StateObject private var switches = ClashStoredSwitch<String>()
    @Environment(\.locale) private var locale
    @Environment(\.clashFeedback) private var feedback
     
     
    @State private var collections: [ConfigurationCollectionEntry] = []
    @State private var copies: [ConfigurationCollection.ID: ConfigurationCollectionContentBridge.Cache] = [:]
    @State private var search = ""
    @State private var link = ""
     
    @State private var adding: NewRuleSet?
     
    @State private var opened: ConfigurationRuleSetDetailPage.Item?
     
     
     
    @State private var groupNodes: [ConfigurationRuleTargetCandidates.Section] = []
    @State private var groupCatalog: ProfilesViewModel.SyntaxCatalog?
     
    @State private var targetNodes = RuleTargetNodeSource()

    private struct CopiesKey: Equatable {
        let sourceID: String?
        let generation: UInt64?
    }

    private struct NewRuleSet: Identifiable {
        let id = UUID()
        let prefill: (name: String, link: String)?
    }

    init(model: ProfilesViewModel, profileID: String, configurationName: String,
         libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?) {
        self.model = model; self.profileID = profileID; self.configurationName = configurationName
        self.libraryChanged = libraryChanged
        _session = StateObject(wrappedValue: ConfigurationSchemeDraftSession(model: model, profileID: profileID))
    }

    private var snapshot: ConfigurationRuleSetsSnapshot? {
        guard let draft = session.draft, let library = session.library else { return nil }
        let copies = self.copies
        return ConfigurationRuleSetsSnapshot.make(
            draft: draft, localSets: library.localRuleSets ?? [], collections: collections, profileID: profileID,
            library: library, profiles: model.profiles.map { .init(id: $0.id, name: $0.label) }, locale: locale,
            copy: { copies[$0.id] })
    }

    private func shown(_ rows: [ConfigurationRuleSetsSnapshot.Row]) -> [ConfigurationRuleSetsSnapshot.Row] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return query.isEmpty ? rows : rows.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        let snapshot = self.snapshot
        Form {
            if let snapshot {
                broughtSection(snapshot)
                 
                 
                onlineSection(snapshot)
                mineSection(snapshot)
                Section {
                    ClashNativeNavigationLink {
                        ConfigurationOnlineRuleLibraryPage(session: session)
                    } label: {
                        Text(clash: .copy("Add from the Online Rule Library"))
                    }
                    .accessibilityIdentifier("configuration.rule-sets.online")
                }
                addSection
            } else if let failure = session.failure {
                Section { Text(verbatim: failure).foregroundStyle(.orange) }
            }
        }
        .clashPageTitle(.verbatim(ConfigurationOriginalRuleSetsPage.title(configurationName, locale: locale)), watchAs: "rule-sets")
        .clashProductModalSearchable(text: $search, prompt: Text(clash: .copy("Search rule sets")))
        .task {
            session.locale = locale
            session.libraryChanged = libraryChanged
            session.feedback = feedback
            await session.load()
        }
         
         
        .clashOnScreen { session.pageOnScreen($0) }
         
         
         
         
        .task(id: CopiesKey(sourceID: session.draft?.version.id, generation: session.library?.generation)) {
            await readCopies()
        }
         
         
         
        .clashProductModal(item: $adding, role: .form) { request in
            ClashSingleColumnNavigationContainer {
                newRuleSetForm(request)
            }
            .environment(\.clashProductModalDismiss, { adding = nil })
        }
        .task(id: adding?.id) {
            guard adding != nil, let library = session.library else { return }
            groupNodes = await ConfigurationRuleSetsPage.groupNodeSections(model: model, library: library, locale: locale)
            if groupCatalog == nil { groupCatalog = try? await ProfilesViewModel.loadSyntaxCatalog() }
        }
         
        .background(ClashRoutedViewDestination(isPresented: Binding(get: { opened != nil }, set: { if !$0 { opened = nil } })) {
            if let opened {
                ConfigurationRuleSetDetailPage(model: model, item: opened, library: session.library ?? ConfigurationLibrarySnapshot(),
                                               profileID: profileID, changed: changed)
            }
        })
    }

     
     
    @ViewBuilder
    private func broughtSection(_ snapshot: ConfigurationRuleSetsSnapshot) -> some View {
        let rows = shown(snapshot.brought)
        if !snapshot.brought.isEmpty {
            Section {
                ForEach(rows) { row in
                     
                     
                    HStack(spacing: ClashTheme.Spacing.row) {
                        RuleSetRow(name: row.name, detail: row.detail)
                            .accessibilityIdentifier("configuration.rule-sets.brought")
                        Spacer(minLength: 0)
                        if let entry = entry(row) {
                            InfoButton { opened = .collection(entry, brought: true) }
                                .accessibilityIdentifier("configuration.rule-sets.brought.info")
                        }
                    }
                }
            } header: {
                Text(clash: .copy(ConfigurationRuleSetsSnapshot.broughtTitleKey))
            }
        }
    }

     
     
     
    @ViewBuilder
    private func onlineSection(_ snapshot: ConfigurationRuleSetsSnapshot) -> some View {
         
        let rows = shown(snapshot.online)
        if !rows.isEmpty {
            Section {
                ForEach(rows) { row in
                    ClashNativeNavigationLink {
                        ConfigurationOnlineRuleLibraryPage(session: session)
                    } label: {
                        RuleSetRow(name: row.name, detail: row.detail)
                    }
                    .accessibilityIdentifier("configuration.rule-sets.online-set")
                }
            } header: {
                Text(clash: .copy("Online Rule Library"))
            }
        }
    }

     
     
    private func mineSection(_ snapshot: ConfigurationRuleSetsSnapshot) -> some View {
        let sets = session.library?.localRuleSets ?? []
        let rows = shown(snapshot.mine)
        return Section {
            if snapshot.isEmpty {
                Text(clash: .copy(ConfigurationRuleSetsSnapshot.emptyKey)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("configuration.rule-sets.empty")
            }
            ForEach(rows) { row in
                if let set = sets.first(where: { $0.id == row.id }) {
                    HStack(spacing: ClashTheme.Spacing.row) {
                        RuleSetRow(name: row.name, detail: row.detail)
                            .accessibilityIdentifier("configuration.rule-sets.mine")
                        Spacer(minLength: 0)
                        InfoButton { opened = .mine(set) }
                            .accessibilityIdentifier("configuration.rule-sets.mine.info")
                        ClashStoredToggle(switches, key: set.id, stored: row.isOn == true,
                                          identifier: "configuration.rule-sets.mine.switch", write: { on in
                            guard on != (session.draft?.referencedRuleSets.contains("local-" + set.id) == true) else { return }
                            guard await ConfigurationRuleSetsPage.switchMine(set, on: on, in: session) else {
                                throw ClashStoredWriteSaidElsewhere()
                            }
                        }) { Text(verbatim: row.name) }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
        } header: {
             
             
             
            if snapshot.isEmpty || !rows.isEmpty {
                Text(clash: .copy("My Rule Sets"))
            }
        } footer: {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                if let failure = session.failure {
                    Text(verbatim: failure).foregroundStyle(.red).accessibilityIdentifier("configuration.rule-sets.failure")
                }
                if let note = snapshot.note {
                    Text(verbatim: note).accessibilityIdentifier("configuration.rule-sets.note")
                }
            }
        }
    }

     
     
     
    private var addSection: some View {
        Section {
            HStack {
                TextField(text: $link, prompt: Text(verbatim: "https://")) { Text(clash: .copy("Link")) }
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .onSubmit(openLink)
                    .accessibilityIdentifier("configuration.rule-sets.link")
                ClashPasteControl(style: .square) { pasted in
                    link = pasted
                    openLink()
                }
            }
            Button { adding = NewRuleSet(prefill: nil) } label: {
                Label { Text(clash: .copy("New Rule Set")) } icon: { Image(systemName: ClashSymbol.plus.name) }
            }
            .accessibilityIdentifier("configuration.rule-sets.new")
        } header: {
            Text(clash: .copy("Add Rule Set"))
        } footer: {
            Text(verbatim: ConfigurationRuleSetsPage.addedNote(configurationName, locale: locale))
                .accessibilityIdentifier("configuration.rule-sets.added-note")
        }
    }

    private func openLink() {
        guard let prefill = ConfigurationRuleSetsPage.prefill(link: link) else { return }
        adding = NewRuleSet(prefill: prefill)
    }

     
     
     
    private func newRuleSetForm(_ request: NewRuleSet) -> some View {
        let draft = session.draft
        let options = draft.map { ConfigurationGroupEditorBridge.ruleOptions($0).shared } ?? .empty
        return ClashTowerLocalRuleEditor(
            value: nil, policy: draft?.groups.first { !$0.isHidden }?.name ?? "DIRECT", options: options, palette: .clashProduct,
            buildRule: { line, accept in
                AnyView(RuleBuilderAdapter(raw: line ?? "", options: RulePolicyOptions(shared: options), showsPersonalMetadata: false,
                                           showsTarget: false, createGroup: nil, enabled: true, comment: "",
                                           pageTitle: line == nil ? "Add Rule" : "Rule",
                                           saveDetails: { raw, _, _ in accept(raw) }, save: { raw in accept(raw) }))
            },
            createGroup: createGroup,
            confirmTitle: "Add", prefill: request.prefill,
            save: { name, input, policy in
                try await ConfigurationRuleSetsPage.add(name: name, input: input, policy: policy, in: session)
                link = ""
                adding = nil
            },
            close: { adding = nil })
    }

     
     
     
     
     
    private func createGroup(_ done: @escaping (String?) -> Void) -> AnyView {
        let groups = session.draft?.groups ?? []
        var request = ClashTowerGroupPageRequest(
            group: ClashTowerRuleCustomizationView.blankGroup, index: groups.count, all: groups, nodeSections: groupNodes,
            save: { value in done(try await ConfigurationRuleSetsPage.addGroup(value, in: session)) })
        request.mode = .adding(cancel: { done(nil) })
        request.targetSearch = memberSearch
        return AnyView(ConfigurationSchemeGroupPage(request: request, catalog: groupCatalog, schemeNote: groupSchemeNote))
    }

     
    private var memberSearch: ClashRuleTargetSearchHook {
        let nodes = targetNodes, profileID = profileID
        let search = ConfigurationRuleTargetSearch(configurationID: profileID, defaults: DelayTestSettings.appGroupDefaults,
                                                   locale: locale) { await nodes.source(profileID: profileID) }
        return ClashRuleTargetSearchHook(sections: { query, current in await search.sections(query: query, current: current) },
                                         recordUse: { search.recordUse($0) })
    }

     
     
     
    private var groupSchemeNote: String? {
        guard let library = session.library else { return nil }
        let locale = locale
        let profiles = model.profiles.map {
            LibraryUsage.Configuration(id: $0.id, name: ProfileRowPresentation.label(for: $0, locale: locale))
        }
        return ConfigurationRulesEditSnapshot.composed(profileID: profileID, library: library, profiles: profiles, locale: locale).note
    }

    private func entry(_ row: ConfigurationRuleSetsSnapshot.Row) -> ConfigurationCollectionEntry? {
        guard let sourceID = session.draft?.version.id else { return nil }
        return collections.first { $0.source.id == sourceID && $0.collection.name == row.id && $0.collection.id.kind == .rules }
    }

    private func changed(_ library: ConfigurationLibrarySnapshot) {
        libraryChanged?(library)
        Task { await session.adopt(library) }
    }

     
     
    private func readCopies() async {
        guard let store = model.configurationLibraryStore, let library = session.library,
              let sourceID = session.draft?.version.id else { return }
        let read = await Task.detached(priority: .userInitiated) { () -> ([ConfigurationCollectionEntry], [ConfigurationCollection.ID: ConfigurationCollectionContentBridge.Cache]) in
            guard let catalog = try? ConfigurationCollectionContentBridge.catalog(store, snapshot: library) else { return ([], [:]) }
            var copies: [ConfigurationCollection.ID: ConfigurationCollectionContentBridge.Cache] = [:]
            for entry in catalog where entry.source.id == sourceID && entry.collection.id.kind == .rules {
                if let held = ConfigurationCollectionContentBridge.libraryCopyRecord(of: entry) { copies[entry.id] = held }
            }
            return (catalog, copies)
        }.value
        collections = read.0
        copies = read.1
    }
}

extension ConfigurationRuleSetsPage {
     
     
     
     
    static func add(name: String, input: String, policy: String, in session: ConfigurationSchemeDraftSession) async throws {
        let read = try await ConfigurationTowerRuleReader.ruleSet(input)
        let id = UUID().uuidString.lowercased()
        let value = ConfigurationLocalRuleSet(id: id, name: name, input: input, rules: read.rules, link: read.link,
                                              behavior: read.behavior)
        guard await session.saveLocalRuleSet(value, deleting: nil) else {
            throw ConfigurationRuleSetAddFailure(message: session.failure)
        }
        let key = "local-" + id
        let attached = await session.change { draft in
            try draft.attachRuleSet(key: key, name: name, rules: read.rules, policy: policy, link: read.link,
                                    behavior: read.behavior)
        }
        await session.waitForSaves()
         
         
         
        guard attached, session.draft?.referencedRuleSets.contains(key) == true else {
            let said = session.failure
            await session.saveLocalRuleSet(nil, deleting: id)
            throw ConfigurationRuleSetAddFailure(message: said)
        }
    }
}

 
extension ConfigurationRuleSetsPage {
     
     
     
     
    static func addGroup(_ value: OrderedJSON, in session: ConfigurationSchemeDraftSession) async throws -> String {
        let added = await session.change { draft in try draft.setGroup(value, groupID: nil) }
        await session.waitForSaves()
        guard added, session.failure == nil, !session.hasUnsavedChanges,
              case .string(let name)? = value.topLevelValue("name"),
              session.draft?.groups.contains(where: { $0.name == name }) == true else {
            throw ConfigurationRuleSetAddFailure(message: session.failure)
        }
        return name
    }

     
     
     
    static func groupNodeSections(model: ProfilesViewModel, library: ConfigurationLibrarySnapshot,
                                  locale: Locale) async -> [ConfigurationRuleTargetCandidates.Section] {
        guard let store = model.configurationLibraryStore else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let candidates = try? ConfigurationRuleTargetCandidates.make(groups: [], snapshot: library, providers: true,
                                                                          naming: { $0.displayLabel(locale: locale) },
                                                                          payload: { try store.payload($0) })
            return candidates?.sections.filter { $0.kind == .source || $0.kind == .providers } ?? []
        }.value
    }
}

struct ConfigurationRuleSetAddFailure: LocalizedError {
    let message: String?
    var errorDescription: String? { message }
}

 
private struct InfoButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: ClashSymbol.infoCircle.name) }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(clash: .copy("View Details")))
    }
}

 
private struct RuleSetRow: View {
    let name: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: name).foregroundStyle(.primary).lineLimit(1)
            if !detail.isEmpty {
                Text(verbatim: detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}
#endif
