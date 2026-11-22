import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 

 
 
struct ProxyNodeLibraryContext {
     
    let configurationName: String
     
     
    var reprepare: () -> Void = {}
     
     
     
    var openSource: ((String) -> Void)? = nil
     
     
     
    var originalEditor: ((String, String, @escaping () -> Void, @escaping () -> Void) -> AnyView)? = nil
     
     
     
     
     
    var offerUndo: (@MainActor (_ title: ClashDisplayText, _ actionName: ClashDisplayText, _ label: String, _ operation: String,
                                _ restore: @escaping @MainActor () async throws -> Void) -> Void)? = nil
}

 
 
struct ProxyNodeLibraryFacts: Equatable, Sendable {
     
    struct SourceRow: Equatable, Sendable {
        let id: String
        let title: String
         
         
        let subtitle: String
    }

     
    enum Removal: Equatable, Sendable {
         
         
        case composed
         
         
        case original(stopsFollowingLink: Bool)
    }

     
     
     
     
     
    struct SelfBuilt: Equatable, Sendable {
        let source: ConfigurationSourceRecord
         
        let index: Int
         
         
        let nodeJSON: String
         
         
         
        let configurations: [String]
    }

    let profileID: String
    let configurationName: String
     
    let node: String
    var source: SourceRow?
    var removal: Removal?
    var selfBuilt: SelfBuilt?
     
     
     
    var editsOriginalText = false

     
     
    static func editsInPlace(_ source: ConfigurationSourceRecord) -> Bool {
        source.origin == .customNodes && source.nodeChain == nil && source.isRetainedSnapshot != true
    }

     
     
     
     
     
    static func read(node: String, profileID: String, configurationName: String,
                     in store: ConfigurationLibraryStore, configurations: [LibraryUsage.Configuration],
                     locale: Locale, now: Date = Date()) throws -> ProxyNodeLibraryFacts? {
        let snapshot = try store.snapshot()
        guard let recipe = snapshot.recipes.first(where: { $0.id == profileID }) else { return nil }
        let bound = ConfigurationCenterSourceBridge.BoundInputs()
        guard let origin = try store.nodeOrigin(of: node, in: profileID, resolveInput: bound.resolve),
              let record = snapshot.sources.first(where: { $0.id == origin.sourceID }) else { return nil }
        var facts = ProxyNodeLibraryFacts(profileID: profileID, configurationName: configurationName, node: node)
        facts.source = SourceRow(id: record.id, title: record.displayLabel(locale: locale),
                                 subtitle: ProxyNodeLibraryCopy.sourceSubtitle(record, locale: locale, now: now))
        guard recipe.preservesOriginal != true else {
             
             
            let following = snapshot.updateFollowing(ofRecipe: profileID)
            facts.removal = .original(stopsFollowingLink: following == .following || following == .paused)
            facts.editsOriginalText = true
            return facts
        }
        facts.removal = .composed
        guard editsInPlace(record),
              case .array(let nodes)? = try OrderedJSON.parse(try store.payload(.init(record)).documentJSON).topLevelValue("proxies"),
              let index = nodes.firstIndex(where: { $0.topLevelValue("name") == .string(origin.name) }) else { return facts }
         
         
        let using = Set(snapshot.recipes.filter { recipe in
            recipe.sources.contains { $0.id == record.id }
                && (recipe.nodeScopes?[record.id]?.choosesNode(named: origin.name) ?? true)
        }.map(\.id))
        let named = configurations.filter { using.contains($0.id) }
        facts.selfBuilt = SelfBuilt(source: record, index: index, nodeJSON: nodes[index].serialized(),
                                    configurations: (named.filter { $0.id == profileID } + named.filter { $0.id != profileID }).map(\.name))
        return facts
    }
}

 
enum ProxyNodeLibraryCopy {
    static let sourceHeader: ClashDisplayText = .copy("Node Source")

     
    static func remove(from configuration: String) -> ClashDisplayText {
        .format("Remove from “%@”", [configuration])
    }

     
    static func removalStopsFollowingLink(_ configuration: String) -> ClashDisplayText {
        .format("Once removed, “%@” no longer follows its link.", [configuration])
    }

     
    static func removed(_ node: String, from configuration: String) -> ClashDisplayText {
        .format("Removed from “%@”: “%@”", [configuration, node])
    }

     
     
    static func editingAlsoChanges(_ configurations: [String], locale: Locale) -> ClashDisplayText? {
        guard configurations.count > 1 else { return nil }
        return .format("Changes to this node also apply to %@.", [quotedNames(configurations, locale: locale)])
    }

     
    static func deletingTakesItFrom(_ configurations: [String], locale: Locale) -> ClashDisplayText {
        .format("After deletion, %@ no longer has this node.", [quotedNames(configurations, locale: locale)])
    }

     
     
    static func quotedNames(_ names: [String], locale: Locale) -> String {
        let quoted = names.map { ClashCopy.string(for: .format("“%@” (Configuration Name)", [$0]), locale: locale) }
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: quoted) ?? quoted.joined(separator: ", ")
    }

     
    static func sourceSubtitle(_ record: ConfigurationSourceRecord, locale: Locale, now: Date) -> String {
        ClashConfigurationSourceCopy.summary(record, locale: locale) + " · " + lastUpdated(record, locale: locale, now: now)
    }

     
     
     
    static func lastUpdated(_ record: ConfigurationSourceRecord, locale: Locale, now: Date) -> String {
        ClashConfigurationSourceCopy.lastUpdated(record, locale: locale, now: now)
    }

     
     
     
    static func refusal(_ error: Error, locale: Locale) -> String {
        guard case ConfigurationNodeRemovalError.stillInUse(let node, let places) = error else {
            return ClashErrorCopy.message(error, locale: locale)
        }
         
         
        let sentence = ClashCopy.string(for: .format("Can’t remove “%@”: it’s still used in the places below. Change them first.", [node]), locale: locale)
        return ([sentence] + places.prefix(OriginalListEdits.keptPlacesShown)).joined(separator: "\n")
    }
}

 

extension ProfilesViewModel {
     
     
     
     
     
     
     
    func removeNode(_ node: String, fromConfiguration id: String) async throws -> ConfigurationNodeRemoval {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        if let file = try await keptRulesFile(of: id) {
            let places: [String]
            do {
                places = try await Task.detached(priority: .userInitiated) {
                    try OriginalListEdits.keptUses(of: node, keptAt: file)
                }.value
            } catch {
                 
                 
                ClashLogStore.shared.append("kept rules: \(error.localizedDescription)", stream: .app, level: .warning)
                throw PublishedRules.Unreadable()
            }
            if !places.isEmpty { throw ConfigurationNodeRemovalError.stillInUse(node: node, places: places) }
        }
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let (prepared, generation) = try await Task.detached(priority: .userInitiated) {
            () throws -> (PreparedConfigurationSourceUpdate, UInt64) in
            let generation = try library.snapshot().generation
             
            let bound = ConfigurationCenterSourceBridge.BoundInputs()
            let prepared = try library.prepareNodeRemoval(node: node, from: id, expectedGeneration: generation,
                                                          deletingFromText: { try Self.deletingNode(from: $0, bound: bound) },
                                                          resolveInput: bound.resolve)
            return (prepared, generation)
        }.value
        guard let removal = prepared.nodeRemoval else { throw ConfigurationLibraryError.invalidIdentifier }
        try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
                                        compositions: prepared.compositions, generation: generation)
        return removal
    }

     
     
     
    func restoreNodeRemoval(_ removal: ConfigurationNodeRemoval) async throws {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let prepared = try await Task.detached(priority: .userInitiated) {
            let bound = ConfigurationCenterSourceBridge.BoundInputs()
            return try library.prepareRestore(removal, resolveInput: bound.resolve)
        }.value
        try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
                                        compositions: prepared.compositions, generation: prepared.candidate.generation)
    }

     
     
     
     
    nonisolated static func deletingNode(from request: ConfigurationOriginalNodeDeletion,
                                         bound: ConfigurationCenterSourceBridge.BoundInputs) throws -> ConfigurationSourcePayload {
        guard let text = String(data: request.current.original, encoding: .utf8),
              (try? ConfigTransforms.validateSource(text)) != nil else {
            throw OriginalEditingError.notYAMLText
        }
        let edited = try ConfigurationTextEditing.edit(text, steps: OriginalListEdits.deleting([request.index], under: [.key("proxies")]))
        return try ConfigurationCenterSourceBridge.payload(label: request.label, origin: request.origin, original: Data(edited.utf8),
                                                           yaml: edited, id: request.sourceID, bound: bound)
    }
}

 

 
 
@MainActor
final class ProxyNodeLibraryActions: ObservableObject {
    @Published private(set) var facts: ProxyNodeLibraryFacts?
    @Published private(set) var busy = false
     
    @Published private(set) var removalRefusal: String?
     
    @Published private(set) var deletionRefusal: String?
     
     
     
    @Published var showsSource = false
     
     
    @Published var showsEditor = false
     
    @Published var showsOriginalEditor = false
     
    private(set) var library = ConfigurationLibrarySnapshot()
    private(set) var model: ProfilesViewModel?
    private var node = ""
    private var profileID = ""
    private var context = ProxyNodeLibraryContext(configurationName: "")
    private var locale = Locale.current
    private var close: () -> Void = {}
    private var hasRead = false
     
    private var savedEdit = false
     
    private var libraryChanged = false

    func attach(node: String, profileID: String, model: ProfilesViewModel, context: ProxyNodeLibraryContext,
                locale: Locale, close: @escaping () -> Void) {
        self.node = node
        self.profileID = profileID
        self.model = model
        self.context = context
        self.locale = locale
        self.close = close
    }

     
    func read() async {
        guard !hasRead, let model, let store = model.configurationLibraryStore else { return }
        hasRead = true
        let locale = locale
        let configurations = model.profiles.map {
            LibraryUsage.Configuration(id: $0.id, name: ProfileRowPresentation.label(for: $0, locale: locale))
        }
        let node = node, id = profileID, name = context.configurationName
        do {
            let read = try await Task.detached(priority: .userInitiated) {
                () throws -> (ProxyNodeLibraryFacts?, ConfigurationLibrarySnapshot) in
                let facts = try ProxyNodeLibraryFacts.read(node: node, profileID: id, configurationName: name, in: store,
                                                           configurations: configurations, locale: locale)
                return (facts, try store.snapshot())
            }.value
            library = read.1
            facts = read.0
        } catch {
             
             
            ClashLogStore.shared.append("node details: \(error.localizedDescription)", stream: .app, level: .warning)
        }
    }

     
     
    func remove(feedback: ClashFeedbackCenter?, locale: Locale) async {
        guard !busy, let facts, facts.removal != nil, let model else { return }
        busy = true
        removalRefusal = nil
        defer { busy = false }
        do {
            let removal = try await model.removeNode(facts.node, fromConfiguration: facts.profileID)
            let reprepare = context.reprepare
            reprepare()
            close()
            let restore: @MainActor () async throws -> Void = {
                try await model.restoreNodeRemoval(removal)
                reprepare()
            }
            let title = ProxyNodeLibraryCopy.removed(facts.node, from: facts.configurationName)
            if let offerUndo = context.offerUndo {
                 
                offerUndo(title, ClashFeedbackCopy.removeActionName(facts.node), facts.node, "configuration.node.remove", restore)
            } else {
                ConfigurationLibraryUndo.offer(feedback, title: title, restored: ClashFeedbackCopy.restored(facts.node),
                                               operation: "configuration.node.remove", identifier: "feedback.node.remove",
                                               model: model, restore: restore)
            }
        } catch {
            removalRefusal = ProxyNodeLibraryCopy.refusal(error, locale: locale)
        }
    }

     
     
     
    func delete(feedback: ClashFeedbackCenter?, locale: Locale) async {
        guard !busy, let facts, let built = facts.selfBuilt, let model else { return }
        busy = true
        deletionRefusal = nil
        defer { busy = false }
        do {
            let updated = try await model.deleteConfigurationCustomNode(.init(built.source), index: built.index)
            let reprepare = context.reprepare
            reprepare()
            close()
            guard let record = updated.sources.first(where: { $0.id == built.source.id }) else { return }
            let restore: @MainActor () async throws -> Void = {
                _ = try await model.insertConfigurationCustomNode(.init(record), nodeJSON: built.nodeJSON, at: built.index)
                reprepare()
            }
            if let offerUndo = context.offerUndo {
                 
                offerUndo(ClashFeedbackCopy.deleted(facts.node), ClashFeedbackCopy.deleteActionName(facts.node), facts.node,
                          "library.delete.node.\(built.source.id).\(built.index)", restore)
            } else {
                ConfigurationLibraryUndo.offer(feedback, title: ClashFeedbackCopy.deleted(facts.node), restored: ClashFeedbackCopy.restored(facts.node),
                                               operation: "library.delete", identifier: "feedback.library.delete",
                                               model: model, restore: restore)
            }
        } catch {
            deletionRefusal = ClashErrorCopy.message(error, locale: locale)
        }
    }

     
     
    func saveSelfBuilt(_ nodeJSON: String) async throws {
        guard let built = facts?.selfBuilt, let model else { throw ConfigurationLibraryError.unreadable }
        _ = try await model.saveConfigurationCustomNode(.init(built.source), nodeJSON: nodeJSON, index: built.index)
        savedEdit = true
    }

     
    func editorClosed() {
        showsEditor = false
        showsOriginalEditor = false
    }

     
     
    func originalEdited() {
        savedEdit = true
    }

     
     
    func sourceChangedLibrary() {
        libraryChanged = true
    }

     
    func sourceClosed() {
        showsSource = false
    }

     
     
     
     
    func editorDismissed() {
        guard savedEdit else { return }
        savedEdit = false
        context.reprepare()
        close()
    }

     
     
    func sourceDismissed() {
        guard libraryChanged else { return }
        libraryChanged = false
        context.reprepare()
        close()
    }
}

 

 
 
struct ProxyNodeLibrarySections: View {
    @ObservedObject var actions: ProxyNodeLibraryActions
    @Environment(\.clashFeedback) private var feedback
    @Environment(\.locale) private var locale

    var body: some View {
        if let facts = actions.facts {
            if let source = facts.source {
                Section {
                    Button { actions.showsSource = true } label: { sourceRow(source) }
                        .accessibilityIdentifier("proxy-detail.source")
                } header: {
                    Text(clash: ProxyNodeLibraryCopy.sourceHeader)
                }
            }
            if let built = facts.selfBuilt {
                Section {
                    Button { actions.showsEditor = true } label: { Text(clash: .copy("Edit Node")) }
                        .disabled(actions.busy)
                        .accessibilityIdentifier("proxy-detail.edit-node")
                } footer: {
                    if let line = ProxyNodeLibraryCopy.editingAlsoChanges(built.configurations, locale: locale) {
                        Text(clash: line)
                    }
                }
            } else if facts.editsOriginalText {
                 
                 
                Section {
                    Button { actions.showsOriginalEditor = true } label: { Text(clash: .copy("Edit Node")) }
                        .disabled(actions.busy)
                        .accessibilityIdentifier("proxy-detail.edit-original-node")
                } footer: {
                    if facts.removal == .original(stopsFollowingLink: true) {
                        Text(clash: .format("Once changed, “%@” no longer follows its link.", [facts.configurationName]))
                    }
                }
            }
            if let removal = facts.removal {
                Section {
                    Button {
                        Task { await actions.remove(feedback: feedback, locale: locale) }
                    } label: {
                        Text(clash: ProxyNodeLibraryCopy.remove(from: facts.configurationName))
                    }
                    .disabled(actions.busy)
                    .accessibilityIdentifier("proxy-detail.remove")
                    if let refusal = actions.removalRefusal {
                        Text(verbatim: refusal)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("proxy-detail.remove.refusal")
                    }
                } footer: {
                    if removal == .original(stopsFollowingLink: true) {
                        Text(clash: ProxyNodeLibraryCopy.removalStopsFollowingLink(facts.configurationName))
                    }
                }
            }
             
            if let built = facts.selfBuilt {
                Section {
                    Button(role: .destructive) {
                        Task { await actions.delete(feedback: feedback, locale: locale) }
                    } label: {
                        Text(clash: .copy("Delete Node"))
                    }
                    .disabled(actions.busy)
                    .accessibilityIdentifier("proxy-detail.delete-node")
                    if let refusal = actions.deletionRefusal {
                        Text(verbatim: refusal)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("proxy-detail.delete-node.refusal")
                    }
                } footer: {
                    if !built.configurations.isEmpty {
                        Text(clash: ProxyNodeLibraryCopy.deletingTakesItFrom(built.configurations, locale: locale))
                    }
                }
            }
        }
    }

     
    private func sourceRow(_ source: ProxyNodeLibraryFacts.SourceRow) -> some View {
        HStack(spacing: ClashTheme.Spacing.row) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: source.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(verbatim: source.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: ClashSymbol.chevronForward.name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

 
 
 
#if os(iOS)
 
 
 
struct ProxyNodeLibraryPresenters: ViewModifier {
    @ObservedObject var actions: ProxyNodeLibraryActions

    func body(content: Content) -> some View {
        content
            .clashProductModal(isPresented: $actions.showsSource, role: .page, onDismiss: { actions.sourceDismissed() }) {
                if let model = actions.model, let facts = actions.facts, let id = facts.source?.id {
                    ConfigurationNodeSourcePage(model: model, sourceID: id,
                                                configuration: .init(id: facts.profileID, name: facts.configurationName),
                                                changed: { _ in actions.sourceChangedLibrary() },
                                                close: { actions.sourceClosed() })
                }
            }
            .clashProductModal(isPresented: $actions.showsOriginalEditor, role: .page, onDismiss: { actions.editorDismissed() }) {
                if let model = actions.model, let facts = actions.facts {
                    OriginalNodeEditorPage(model: model, profileID: facts.profileID, name: facts.node,
                                           saved: { actions.originalEdited() }, close: { actions.editorClosed() })
                }
            }
            .clashProductModal(isPresented: $actions.showsEditor, role: .page, onDismiss: { actions.editorDismissed() }) {
                if let built = actions.facts?.selfBuilt, let record = CustomNodesView.record(fromNodeJSON: built.nodeJSON) {
                    ClashFeatureNavigationContainer {
                        ProxyNodeDetailsView(record: record, retest: {},
                                             saveNode: { _, json in try await actions.saveSelfBuilt(json) },
                                             showsTesting: false,
                                             onDone: { actions.editorClosed() },
                                             commitTitle: "Save")
                    }
                    .clashModalPresentation(.page)
                }
            }
    }
}
#endif
