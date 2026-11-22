import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 

 

 
 

 
 
 
 
enum ConfigurationGroupExcludes {
     
    static func text(_ value: OrderedJSON?) -> String {
        switch value {
        case .string(let text)?, .scalar(let text)?: return text
        default: return ""
        }
    }

     
    static func types(_ text: String) -> [String] {
        text.split(separator: "|", omittingEmptySubsequences: true).map(String.init)
    }

     
    static func excludes(_ type: String, in types: [String]) -> Bool {
        types.contains { $0.caseInsensitiveCompare(type) == .orderedSame }
    }

     
     
    static func toggling(_ type: String, in types: [String]) -> [String] {
        excludes(type, in: types) ? types.filter { $0.caseInsensitiveCompare(type) != .orderedSame } : types + [type]
    }

     
     
    static func title(_ copy: ConfigurationFieldCopy, locale: Locale) -> String {
        copy.entry(forPath: ClashGroupLeaveOutNodes.copyPath, language: .init(locale: locale))?.title ?? "exclude-filter"
    }

     
     
    static func summary(pattern: OrderedJSON?, types: OrderedJSON?, locale: Locale = AppPreferences.language().locale) -> ClashDisplayText {
        let written = text(pattern)
        let count = Self.types(text(types)).count
        guard count > 0 else { return written.isEmpty ? .copy("None") : .verbatim(written) }
        let protocols = ClashCopy.format(count == 1 ? "%@ protocol" : "%@ protocols", locale: locale, ClashCopy.count(count, locale: locale))
        return .verbatim(written.isEmpty ? protocols : written + " · " + protocols)
    }

     
     
     
    static func typeLabel(_ label: String) -> ClashDisplayText {
        .format("Leave out %@", [label])
    }

     
     
    static func typeRows(_ copy: ConfigurationFieldCopy, locale: Locale, written: [String]) -> [ConfigurationFieldCopy.Preset] {
        let presets = copy.entry(forPath: "proxy-groups[*].exclude-type", language: .init(locale: locale))?.presets ?? []
        let others = written.filter { type in !presets.contains { $0.value.caseInsensitiveCompare(type) == .orderedSame } }
        return presets + others.map { ConfigurationFieldCopy.Preset(value: $0, label: $0) }
    }
}

 
 
 
 
 
 
 
@MainActor
final class ConfigurationGroupExcludesModel: ObservableObject {
    let group: String
    @Published var pattern: String
     
    @Published private(set) var written: String
    @Published private(set) var types: [String]
     
    private var writtenTypes: [String]
     
    private var writing: Task<Void, Never>?
     
    @Published private(set) var answer: ClashGroupLeaveOutNodes.Answer?
     
    @Published private(set) var failure: String?
    private let check: ClashGroupPatternCheck?
    private let write: (String, OrderedJSON?) async -> String?

    init(group: String, pattern: String, types: String, check: ClashGroupPatternCheck?,
         write: @escaping (String, OrderedJSON?) async -> String?) {
        self.group = group
        self.pattern = pattern
        written = pattern
        let parsed = ConfigurationGroupExcludes.types(types)
        self.types = parsed
        writtenTypes = parsed
        self.check = check
        self.write = write
    }

     
    var refusal: ClashDisplayText? {
        ClashGroupLeaveOutNodes.refuses(answer, pattern) ? ClashGroupLeaveOutNodes.refusal(group: group) : nil
    }

     
    var holdsInfoNodes: Bool { ClashGroupLeaveOutNodes.holdsInfoNodeExample(pattern) }

    func excludes(_ type: String) -> Bool { ConfigurationGroupExcludes.excludes(type, in: types) }

     
    func checkPattern() async {
        let asked = pattern
        let answer = await ClashGroupLeaveOutNodes.answer(asked, known: answer, check: check)
        if answer.pattern == pattern { self.answer = answer }
    }

     
     
     
    @discardableResult
    func submitPattern() async -> Bool {
        let text = pattern
        guard text != written else { return true }
        let answer = await ClashGroupLeaveOutNodes.answer(text, known: answer, check: check)
        if answer.pattern == pattern { self.answer = answer }
        guard answer.refusal == nil else { return false }
        return await take(write("exclude-filter", text.isEmpty ? nil : .string(text))) { self.written = text }
    }

     
     
    @discardableResult
    func addInfoNodes() async -> Bool {
        pattern = ClashGroupLeaveOutNodes.addingInfoNodeExample(to: pattern)
        return await submitPattern()
    }

     
     
     
    @discardableResult
    func toggle(_ type: String) async -> Bool {
        types = ConfigurationGroupExcludes.toggling(type, in: types)
        return await writeTypes()
    }

     
     
     
    func press(_ type: String, on: Bool) {
        guard on != excludes(type) else { return }
        types = ConfigurationGroupExcludes.toggling(type, in: types)
        let previous = writing
        writing = Task { [weak self] in
            await previous?.value
            _ = await self?.writeTypes()
        }
    }

    private func writeTypes() async -> Bool {
        let shown = types
        let taken = await take(write("exclude-type", shown.isEmpty ? nil : .string(shown.joined(separator: "|")))) {
            self.writtenTypes = shown
        }
        if !taken { types = writtenTypes }
        return taken
    }

    private func take(_ answer: String?, then: () -> Void) -> Bool {
        guard let answer else {
            failure = nil
            then()
            return true
        }
        failure = answer.isEmpty ? nil : answer
        return false
    }
}

#if os(iOS)
 
 
 
 
 
 
struct ConfigurationGroupExcludesPage: View {
    @StateObject private var model: ConfigurationGroupExcludesModel
    let schemeNote: String?
    let reading: Bool
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    init(group: String, pattern: String, types: String, schemeNote: String?, reading: Bool,
         check: ClashGroupPatternCheck? = ConfigurationTowerRuleCustomizationAdapter.groupPatternCheck,
         write: @escaping (String, OrderedJSON?) async -> String?) {
        _model = StateObject(wrappedValue: ConfigurationGroupExcludesModel(group: group, pattern: pattern, types: types,
                                                                           check: check, write: write))
        self.schemeNote = schemeNote
        self.reading = reading
    }

    private var language: ConfigurationFieldCopy.Language { .init(locale: locale) }
    private var patternCopy: ConfigurationFieldCopy.Entry? { fieldCopy.entry(forPath: ClashGroupLeaveOutNodes.copyPath, language: language) }
    private var typesCopy: ConfigurationFieldCopy.Entry? { fieldCopy.entry(forPath: "proxy-groups[*].exclude-type", language: language) }

    var body: some View {
        List {
            Section {
                TextField(text: $model.pattern, prompt: patternCopy?.example.map { Text(verbatim: $0) }) {
                    Text(verbatim: ConfigurationGroupExcludes.title(fieldCopy, locale: locale))
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { Task { await model.submitPattern() } }
                .accessibilityIdentifier("configuration.group.excludes.pattern")
                if let refusal = model.refusal {
                    Text(clash: refusal).font(.footnote).foregroundStyle(.red)
                        .accessibilityIdentifier("configuration.group.excludes.pattern.refusal")
                }
                Button { Task { await model.addInfoNodes() } } label: { Text(clash: .copy("Leave Out Info Nodes")) }
                    .disabled(model.holdsInfoNodes)
                    .accessibilityIdentifier("configuration.group.excludes.info-nodes")
            } header: {
                Text(clash: .copy("By Name"))
            } footer: {
                if let summary = patternCopy?.summary { Text(verbatim: summary) }
            }
             
             
            .disabled(reading)
            Section {
                 
                 
                 
                ForEach(ConfigurationGroupExcludes.typeRows(fieldCopy, locale: locale, written: model.types), id: \.value) { row in
                    Toggle(isOn: Binding(get: { model.excludes(row.value) }, set: { on in
                        model.press(row.value, on: on)
                    })) {
                        Text(verbatim: row.label)
                    }
                    .accessibilityLabel(Text(clash: ConfigurationGroupExcludes.typeLabel(row.label)))
                    .accessibilityIdentifier("configuration.group.excludes.type.\(row.value)")
                }
            } header: {
                Text(clash: .copy("By Protocol"))
            } footer: {
                if let summary = typesCopy?.summary { Text(verbatim: summary) }
            }
            .disabled(reading)
            if let failure = model.failure {
                Section { Text(verbatim: failure).foregroundStyle(.orange) }
            }
            if let schemeNote {
                Section {} footer: { Text(verbatim: schemeNote) }
            }
        }
        .navigationTitle(Text(verbatim: ConfigurationGroupExcludes.title(fieldCopy, locale: locale)))
         
         
        .task(id: model.pattern) {
            guard !model.pattern.isEmpty else { return }
            if model.pattern != model.written {
                 
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
            }
            await model.checkPattern()
        }
         
        .onDisappear { if !reading { Task { await model.submitPattern() } } }
    }
}

 

 
 
 
 
 
 
 
 
 
struct ConfigurationPolicyGroupSheet: View {
    enum Opening: Hashable, Identifiable {
        case group(String)
        case adding
        case reordering

        var id: String {
            switch self {
            case .group(let name): return "group:" + name
            case .adding: return "adding"
            case .reordering: return "reordering"
            }
        }
    }

    @ObservedObject var model: ProfilesViewModel
    @Environment(\.locale) private var locale
    let profileID: String
    let opening: Opening
     
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
    @StateObject private var session: ConfigurationEditorSession

    init(model: ProfilesViewModel, profileID: String, opening: Opening,
         changed: @escaping (ConfigurationLibrarySnapshot) -> Void, close: @escaping () -> Void) {
        _model = ObservedObject(wrappedValue: model)
        self.profileID = profileID
        self.opening = opening
        self.changed = changed
        self.close = close
        _session = StateObject(wrappedValue: ConfigurationEditorSession(profileID: profileID, model: model))
    }

    var body: some View {
        Group {
            if session.page?.form == .original, opening == .adding {
                 
                 
                originalNewGroup
            } else {
                ClashFeatureNavigationContainer {
                    content
                        .toolbar {
                             
                             
                             
                             
                             
                            ToolbarItem(placement: .cancellationAction) {
                                if opening != .adding {
                                    Button { close() } label: { Text(clash: .copy("Close")) }
                                        .accessibilityIdentifier("proxies.group.sheet.close")
                                }
                            }
                        }
                }
            }
        }
        .task { await session.reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch session.page?.form {
        case .composed(let scheme, _)?:
            ConfigurationSchemeRulesPushed(model: model, profileID: profileID, schemeID: scheme.id, focus: .groups,
                                           single: single, opening: opening == .reordering ? .reordering : .list,
                                           changed: { library in changed(library) })
        case .original?:
            original
        case nil:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

     
     
    private var originalNewGroup: some View {
        let list = session.value(at: ["proxy-groups"])
        return ConfigurationOriginalNewEntryForm(section: .proxyGroups, catalog: session.catalog, note: session.linkNote(locale: locale),
                                                 taken: Set(OriginalEntry.all(in: list).map(\.name))) { name, json in
            let insertion = ConfigurationOriginalEntriesView.insertion(of: json, named: name, groups: true, into: list)
            Task {
                if await session.editOriginal(insertion.path, insertion.edit) { close() }
            }
        }
        .configurationPushedAlertHost(session)
    }

     
    private var single: ClashTowerSingleObject? {
        switch opening {
        case .group(let name): return .group(name)
        case .adding: return .newGroup
        case .reordering: return nil
        }
    }

     
     
    @ViewBuilder
    private var original: some View {
        switch opening {
        case .group(let name):
            ConfigurationOriginalEntryView(session: session, section: .proxyGroups, name: name)
                .configurationPushedAlertHost(session)
        case .adding:
            originalNewGroup
        case .reordering:
            ConfigurationOriginalEntriesView(session: session, section: .proxyGroups, startsReordering: true)
                .configurationPushedAlertHost(session)
        }
    }
}

 

extension ConfigurationEditorSession {
     
     
     
     
     
    func linkNote(locale: Locale) -> String? {
        guard let page else { return nil }
        return Self.linkNote(name: page.label, followsLink: page.followsSubscription, locale: locale)
    }

    static func linkNote(name: String, followsLink: Bool, locale: Locale) -> String? {
        ConfigurationRulesEditSnapshot.original(name: name, followsLink: followsLink, opensText: false, locale: locale).note
    }
}

 

 
 
 
 
 
 
@MainActor
enum PolicyGroupUndo {
    static func restore(_ deletion: ConfigurationRuleGroupDeletion, schemeID: String, profileID: String?,
                        model: ProfilesViewModel) async throws -> ConfigurationLibrarySnapshot {
        guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
         
        guard !model.changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        let snapshot = try await Task.detached(priority: .userInitiated) { try store.snapshot() }.value
        let id = profileID.flatMap { profile in snapshot.recipes.first { $0.id == profile }?.ruleSchemeID } ?? schemeID
        guard let scheme = snapshot.rules.first(where: { $0.id == id })
                ?? ConfigurationBuiltins.schemes.first(where: { $0.id == id }) else {
            throw ConfigurationLibraryError.missingDependency(id)
        }
        var draft = try await Task.detached(priority: .userInitiated) {
            try ConfigurationRuleDraft(scheme: scheme, payload: store.ruleSchemePayload(scheme.id))
        }.value
        try draft.restoreGroupDeletion(deletion)
        return try await model.saveConfigurationRuleCustomization(draft, profileID: profileID, generation: snapshot.generation)
    }

     
     
     
     
    static func offer(_ report: ClashTowerGroupDeletionReport, feedback: ClashFeedbackCenter?, model: ProfilesViewModel) {
        ConfigurationLibraryUndo.offer(feedback, title: ClashTowerGroupDeletionCopy.deleted(report.deletion),
                                       restored: ClashFeedbackCopy.restored(report.deletion.name),
                                       operation: "configuration.group.delete", identifier: "feedback.group.delete",
                                       model: model, restore: report.restore)
    }
}

 
 
 
 
 
 
enum ConfigurationOriginalGroupDeletion {
    @MainActor
    static func delete(_ name: String, session: ConfigurationEditorSession, feedback: ClashFeedbackCenter?) async -> Bool {
        guard let document = session.page?.document else { return false }
        let places = OriginalListEdits.uses(ofNode: name, in: document)
        guard places.isEmpty else {
            session.refuseDeleting(name, usedBy: places)
            return false
        }
        guard await !session.keptRulesRefuseDeleting([name]) else { return false }
        let list = session.page?.document.topLevelValue("proxy-groups")
        guard let step = OriginalEntry.step(of: name, in: list), case .index(let index) = step,
              let entry = OriginalEntry.all(in: list).first(where: { $0.name == name }) else { return false }
         
         
         
        let store = session.model.configurationLibraryStore
        let id = session.profileID
        let followedLink = await Task.detached(priority: .userInitiated) {
            (try? store.map { try followsLink(id, in: $0.snapshot()) }) == true
        }.value
        guard await session.editOriginal([.key("proxy-groups"), step], .delete) else { return false }
         
        let textAfter: String?
        if followedLink {
            textAfter = await Task.detached(priority: .userInitiated) { store.flatMap { try? text(of: id, in: $0) } }.value
        } else {
            textAfter = nil
        }
        let json = entry.value.serialized()
        ConfigurationLibraryUndo.offer(feedback, title: ClashFeedbackCopy.deleted(name), restored: ClashFeedbackCopy.restored(name),
                                       operation: "configuration.group.delete", identifier: "feedback.group.delete",
                                       model: session.model) {
            try await undo(json, named: name, at: index, followedLink: followedLink, textAfter: textAfter, session: session)
        }
        return true
    }

     
     
     
     
     
    @MainActor
    static func undo(_ json: String, named name: String, at index: Int, followedLink: Bool, textAfter: String?,
                     session: ConfigurationEditorSession) async throws {
        if followedLink {
            try await rejoinLink(profileID: session.profileID, model: session.model, expecting: textAfter)
            await session.reload()
            return
        }
        guard await restore(json, named: name, at: index, session: session) else {
            throw ConfigurationLibraryError.staleGeneration
        }
    }

     
     
    static func followsLink(_ id: String, in snapshot: ConfigurationLibrarySnapshot) -> Bool {
        snapshot.updateFollowing(ofRecipe: id) == .following
    }

     
    static func text(of id: String, in store: ConfigurationLibraryStore) throws -> String {
        let snapshot = try store.snapshot()
        guard let recipe = snapshot.recipes.first(where: { $0.id == id }) else { throw ConfigurationLibraryError.missingDependency(id) }
        return try store.payload(recipe.ruleSource).documentJSON
    }

     
     
     
     
     
    @MainActor
    static func rejoinLink(profileID: String, model: ProfilesViewModel, expecting expected: String?) async throws {
        guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        let (state, current) = try await Task.detached(priority: .userInitiated) {
            (try store.snapshot().updateFollowing(ofRecipe: profileID), try text(of: profileID, in: store))
        }.value
        guard state == .ownCopy, let expected, current == expected else { throw ConfigurationLibraryError.staleGeneration }
        try await model.setConfigurationSourceUpdates(profileID, enabled: true)
    }

     
     
     
     
     
    static func users(of name: String, in document: OrderedJSON, places: [String]) -> ConfigurationRuleGroupUsers {
        guard !places.isEmpty else { return .init() }
        let groups = OriginalEntry.all(in: document.topLevelValue("proxy-groups")).filter { entry in
            guard entry.name != name else { return false }
            if case .array(let members)? = entry.value.topLevelValue("proxies"), members.contains(.string(name)) { return true }
            return ["default-selected", "dialer-proxy"].contains { entry.value.topLevelValue($0) == .string(name) }
        }.map(\.name)
        var finalRule = false
        if case .array(let rules)? = document.topLevelValue("rules") {
            finalRule = rules.contains { rule in
                guard case .string(let raw) = rule else { return false }
                let kind = raw.split(separator: ",", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces).uppercased()
                return (kind == "MATCH" || kind == "FINAL") && OriginalListEdits.namesTarget(raw, name)
            }
        }
        return .init(groups: groups, finalRule: finalRule, elsewhere: groups.isEmpty && !finalRule)
    }

     
     
     
    @MainActor
    static func restore(_ json: String, named name: String, at index: Int, session: ConfigurationEditorSession) async -> Bool {
        let list = session.page?.document.topLevelValue("proxy-groups")
        let groups = OriginalEntry.all(in: list)
        guard !groups.contains(where: { $0.name == name }) else { return false }
        guard !groups.isEmpty else {
            let insertion = ConfigurationOriginalEntriesView.insertion(of: json, named: name, groups: true, into: list)
            return await session.editOriginal(insertion.path, insertion.edit)
        }
        return await session.editOriginal([.key("proxy-groups"), .index(min(index, groups.count))], .insert(json: json))
    }
}
#endif
