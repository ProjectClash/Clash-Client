#if os(iOS)
import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 

 
 
struct ConfigurationOriginalRuleSetsSnapshot: Equatable {
    struct Row: Equatable, Identifiable {
         
        let id: String
        let name: String
         
         
        let detail: String
    }

    let rows: [Row]
     
     
    let note: String?

     
     
     
     
    @MainActor
    static func make(document: OrderedJSON?, followsSubscription: Bool, configurationName: String,
                     copies: [String: ConfigurationCollectionContentBridge.Cache], locale: Locale,
                     now: Date = Date()) -> Self {
        let entries = OriginalEntry.all(in: document?.topLevelValue("rule-providers"))
        let rows = entries.map { entry -> Row in
            let origin = ConfigurationRuleSetLine.origin(of: entry.value)
            let detail: String
            switch origin {
            case .inProfile:
                 
                 
                var count: Int?
                if case .array(let payload)? = entry.value.topLevelValue("payload") { count = payload.count }
                detail = ConfigurationRuleSetLine.detail(.inProfile, count: count, updatedAt: nil, locale: locale, now: now)
            case .link:
                let held = copies[entry.name]
                detail = ConfigurationRuleSetLine.detail(.link, count: held?.count, updatedAt: held?.updatedAt,
                                                         locale: locale, now: now)
            case .local:
                 
                detail = ConfigurationRuleSetLine.detail(.local, count: copies[entry.name]?.count, updatedAt: nil,
                                                         locale: locale, now: now)
            }
            return Row(id: entry.name, name: entry.name, detail: detail)
        }
        return Self(rows: rows, note: ConfigurationEditorSession.linkNote(name: configurationName, followsLink: followsSubscription,
                                                                          locale: locale))
    }

     
     
     
    static func copies(of profileID: String, in store: ConfigurationLibraryStore)
        -> [String: ConfigurationCollectionContentBridge.Cache] {
        guard let snapshot = try? store.snapshot(),
              let recipe = snapshot.recipes.first(where: { $0.id == profileID }),
              let catalog = try? ConfigurationCollectionContentBridge.catalog(store, snapshot: snapshot) else { return [:] }
        var copies: [String: ConfigurationCollectionContentBridge.Cache] = [:]
        for entry in catalog where entry.source.id == recipe.ruleSource.id && entry.collection.id.kind == .rules {
            if let held = ConfigurationCollectionContentBridge.libraryCopyRecord(of: entry) { copies[entry.collection.name] = held }
        }
        return copies
    }

     
     
    static func matching(_ rows: [Row], query: String) -> [Row] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return rows }
        return rows.filter { $0.name.lowercased().contains(query) }
    }

     
     
    static func refusal(_ name: String, places: [String], locale: Locale) -> String? {
        guard !places.isEmpty else { return nil }
        return ClashCopy.string(for: .format("Can’t delete “%@”: it’s still used in the places below. Change them first.", [name]),
                                locale: locale)
    }

     
     
     
    enum Place: Equatable {
        case rule(String)
        case elsewhere(String)
    }

     
    static func shownPlaces(_ places: [String], in document: OrderedJSON) -> [Place] {
        var rules = Set<String>()
        if case .array(let items)? = document.topLevelValue("rules") {
            for case .string(let rule) in items { rules.insert(rule) }
        }
        if case .object(let branches)? = document.topLevelValue("sub-rules") {
            for branch in branches {
                guard case .array(let items) = branch.value else { continue }
                for case .string(let rule) in items { rules.insert(rule) }
            }
        }
        return places.prefix(5).map { rules.contains($0) ? .rule($0) : .elsewhere($0) }
    }
}

 
struct ConfigurationOriginalRuleSetsPage: View {
    @ObservedObject var session: ConfigurationEditorSession
    @Environment(\.locale) private var locale
    @State private var adding = false
    @State private var search = ""
    @State private var copies: [String: ConfigurationCollectionContentBridge.Cache] = [:]

     
     
    static let titleKey = "Rule Sets of “%@”"
    static let addKey = "Add Rule Set"

    static func title(_ configurationName: String, locale: Locale) -> String {
        ClashCopy.format(titleKey, locale: locale, configurationName)
    }

    init(session: ConfigurationEditorSession) {
        self.session = session
    }

    var body: some View {
        let snapshot = ConfigurationOriginalRuleSetsSnapshot.make(
            document: session.page?.document, followsSubscription: session.page?.followsSubscription == true,
            configurationName: session.page?.label ?? "", copies: copies, locale: locale)
        List {
            Section {
                if snapshot.rows.isEmpty {
                    Text(clash: ConfigurationEmptyList.sentence(for: "rule-providers")).foregroundStyle(.secondary)
                        .accessibilityIdentifier("configuration.original-rule-sets.empty")
                }
                ForEach(ConfigurationOriginalRuleSetsSnapshot.matching(snapshot.rows, query: search)) { row in
                    ClashNativeNavigationLink {
                         
                        ConfigurationOriginalEntryView(session: session, section: .ruleProviders, name: row.name)
                            .configurationPushedAlertHost(session)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: row.name).foregroundStyle(.primary).lineLimit(1)
                            if !row.detail.isEmpty {
                                Text(verbatim: row.detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                     
                    .accessibilityIdentifier("configuration-editor.original.rule-providers.\(row.name)")
                }
                Button { adding = true } label: {
                    Label { Text(clash: .copy(Self.addKey)) } icon: { Image(systemName: ClashSymbol.plus.name) }
                }
                .disabled(session.isSaving || session.hasOriginalChangesOwed)
                .accessibilityIdentifier("configuration-editor.original.add")
            } footer: {
                if let note = snapshot.note {
                    Text(verbatim: note).accessibilityIdentifier("configuration.original-rule-sets.note")
                }
            }
        }
        .clashPageTitle(.verbatim(Self.title(session.page?.label ?? "", locale: locale)), watchAs: "original-rule-sets")
        .clashProductModalSearchable(text: $search)
        .configurationPushedAlertHost(session)
        .task { await readCopies() }
        .clashSheet(isPresented: $adding) {
            ConfigurationOriginalNewEntryForm(section: .ruleProviders, catalog: session.catalog, note: session.linkNote(locale: locale),
                                              confirmTitle: "Add",
                                              taken: Set(snapshot.rows.map(\.name))) { name, json in
                let insertion = OriginalListEdits.insertion(of: json, named: name, groups: false,
                                                            into: session.value(at: ["rule-providers"]))
                Task { await session.editOriginal(insertion.path, insertion.edit) }
            }
            .clashModalPresentation(.form)
        }
    }

     
     
    private func readCopies() async {
        guard let store = session.model.configurationLibraryStore else { return }
        let id = session.profileID
        copies = await Task.detached(priority: .userInitiated) {
            ConfigurationOriginalRuleSetsSnapshot.copies(of: id, in: store)
        }.value
    }
}

 
 
 
 
 
 
 
 
enum ConfigurationOriginalRuleSetDeletion {
    @MainActor
    static func delete(_ name: String, session: ConfigurationEditorSession, feedback: ClashFeedbackCenter?) async -> Bool {
        guard let document = session.page?.document else { return false }
        let places = OriginalListEdits.uses(ofRuleSet: name, in: document)
        guard places.isEmpty else {
            session.refuseDeleting(name, usedBy: places)
            return false
        }
        guard await !session.keptRulesRefuseDeleting([name], ruleSets: true) else { return false }
        let list = session.page?.document.topLevelValue("rule-providers")
        guard let step = OriginalEntry.step(of: name, in: list),
              let entry = OriginalEntry.all(in: list).first(where: { $0.name == name }) else { return false }
        let store = session.model.configurationLibraryStore
        let id = session.profileID
        let followedLink = await Task.detached(priority: .userInitiated) {
            (try? store.map { try ConfigurationOriginalGroupDeletion.followsLink(id, in: $0.snapshot()) }) == true
        }.value
        guard await session.editOriginal([.key("rule-providers"), step], .delete) else { return false }
         
        let textAfter: String?
        if followedLink {
            textAfter = await Task.detached(priority: .userInitiated) {
                store.flatMap { try? ConfigurationOriginalGroupDeletion.text(of: id, in: $0) }
            }.value
        } else {
            textAfter = nil
        }
        let json = entry.value.serialized()
        ConfigurationLibraryUndo.offer(feedback, title: ClashFeedbackCopy.deleted(name), restored: ClashFeedbackCopy.restored(name),
                                       operation: "configuration.rule-set.delete", identifier: "feedback.rule-set.delete",
                                       model: session.model) {
            try await undo(json, named: name, followedLink: followedLink, textAfter: textAfter, session: session)
        }
        return true
    }

    @MainActor
    static func undo(_ json: String, named name: String, followedLink: Bool, textAfter: String?,
                     session: ConfigurationEditorSession) async throws {
        if followedLink {
            try await ConfigurationOriginalGroupDeletion.rejoinLink(profileID: session.profileID, model: session.model,
                                                                    expecting: textAfter)
            await session.reload()
            return
        }
        guard await restore(json, named: name, session: session) else { throw ConfigurationLibraryError.staleGeneration }
    }

     
     
     
    @MainActor
    static func restore(_ json: String, named name: String, session: ConfigurationEditorSession) async -> Bool {
        let list = session.page?.document.topLevelValue("rule-providers")
        guard !OriginalEntry.all(in: list).contains(where: { $0.name == name }) else { return false }
        let insertion = OriginalListEdits.insertion(of: json, named: name, groups: false, into: list)
        return await session.editOriginal(insertion.path, insertion.edit)
    }
}
#endif
