import Foundation
import ClashClientKit
import ClashClientUI

 
 
 
 
 
 
public struct ClashMacConfigurationLibraryActions {
     
    public var load: @Sendable () async throws -> ConfigurationLibrarySnapshot
     
    public var renameSource: @MainActor (String, String, UInt64) async throws -> ConfigurationLibrarySnapshot
     
    public var deleteSource: @MainActor (String, UInt64) async throws -> ConfigurationLibrarySnapshot
     
     
    public var updateSource: @MainActor (String) async throws -> Void
     
    public var deleteRuleScheme: @MainActor (String, UInt64) async throws -> ConfigurationLibrarySnapshot
     
     
     
    public var deleteSourceRestorably: (@MainActor (String, UInt64) async throws -> (ConfigurationLibrarySnapshot, ConfigurationLibraryRemoval))? = nil
    public var deleteRuleSchemeRestorably: (@MainActor (String, UInt64) async throws -> (ConfigurationLibrarySnapshot, ConfigurationLibraryRemoval))? = nil
     
     
    public var restoreRemoval: (@MainActor (ConfigurationLibraryRemoval, UInt64) async throws -> ConfigurationLibrarySnapshot)? = nil
     
     
    public var addSource: @MainActor (ConfigurationSourcePayload, UInt64) async throws -> ConfigurationLibrarySnapshot
     
     
    public var addRuleScheme: @MainActor (ConfigurationSourcePayload, UInt64) async throws -> ConfigurationLibrarySnapshot
     
     
    public var copyScheme: @MainActor (String, String, UInt64) async throws -> ConfigurationLibrarySnapshot
     
     
    public var loadCollections: @Sendable (ConfigurationLibrarySnapshot) async throws -> [ConfigurationCollectionEntry] = { _ in [] }
     
     
     
     
    public var runningCounts: (@Sendable ([ConfigurationCollectionEntry]) async -> [ConfigurationCollectionEntry])?
     
     
     
    public var updateSourceReplacingRules: @MainActor (String, String?) async throws -> Void = { _, _ in
        throw ConfigurationLibraryError.unreadable
    }
     
     
     
     
    public var updateAllSources: (@MainActor (_ progress: @escaping @MainActor (String) -> Void) async -> ClashMacBatchOutcome)?
     
     
    public var updateAllRuleSets: (@MainActor (_ progress: @escaping @MainActor (String) -> Void) async -> ClashMacBatchOutcome)?
     
     
     
     
    public var updateCollection: (@MainActor (ConfigurationCollectionEntry) async throws -> ClashMacBatchOutcome)?
     
     
     
    public var saveSourceDetails: @MainActor (String, String, ConfigurationSourceSettingsDraft?, UInt64) async throws -> ConfigurationLibrarySnapshot = { _, _, _, _ in
        throw ConfigurationLibraryError.unreadable
    }
     
     
     
    public var syncLegacyProfiles: (@MainActor (_ progress: @escaping @MainActor (String) -> Void) async -> ClashMacBatchOutcome)?
     
    public var saveSourceSettings: @MainActor (String, ConfigurationSourceSettingsDraft, UInt64) async throws -> ConfigurationLibrarySnapshot = { _, _, _ in
        throw ConfigurationLibraryError.unreadable
    }

    public init(
        load: @escaping @Sendable () async throws -> ConfigurationLibrarySnapshot,
        renameSource: @escaping @MainActor (String, String, UInt64) async throws -> ConfigurationLibrarySnapshot,
        deleteSource: @escaping @MainActor (String, UInt64) async throws -> ConfigurationLibrarySnapshot,
        updateSource: @escaping @MainActor (String) async throws -> Void,
        deleteRuleScheme: @escaping @MainActor (String, UInt64) async throws -> ConfigurationLibrarySnapshot,
        addSource: @escaping @MainActor (ConfigurationSourcePayload, UInt64) async throws -> ConfigurationLibrarySnapshot = { _, _ in
            throw ConfigurationLibraryError.unreadable
        },
        addRuleScheme: @escaping @MainActor (ConfigurationSourcePayload, UInt64) async throws -> ConfigurationLibrarySnapshot = { _, _ in
            throw ConfigurationLibraryError.unreadable
        },
        copyScheme: @escaping @MainActor (String, String, UInt64) async throws -> ConfigurationLibrarySnapshot = { _, _, _ in
            throw ConfigurationLibraryError.unreadable
        }
    ) {
        self.load = load
        self.renameSource = renameSource
        self.deleteSource = deleteSource
        self.updateSource = updateSource
        self.deleteRuleScheme = deleteRuleScheme
        self.addSource = addSource
        self.addRuleScheme = addRuleScheme
        self.copyScheme = copyScheme
    }

     
     
    public static var unavailable: ClashMacConfigurationLibraryActions {
        ClashMacConfigurationLibraryActions(
            load: { ConfigurationLibrarySnapshot() },
            renameSource: { _, _, _ in throw ConfigurationLibraryError.unreadable },
            deleteSource: { _, _ in throw ConfigurationLibraryError.unreadable },
            updateSource: { _ in throw ConfigurationLibraryError.unreadable },
            deleteRuleScheme: { _, _ in throw ConfigurationLibraryError.unreadable }
        )
    }
}

 
public enum ClashMacNodeLibraryGroup: CaseIterable, Sendable {
    case subscriptions, files, customNodes, proxyChains

     
    public var title: String {
        switch self {
        case .subscriptions: "From Profile URLs"
        case .files: "From Files"
        case .customNodes: "Custom Nodes"
        case .proxyChains: "Proxy Chains"
        }
    }

    public var identifier: String {
        switch self {
        case .subscriptions: "config-urls"
        case .files: "files"
        case .customNodes: "custom-nodes"
        case .proxyChains: "proxy-chains"
        }
    }

     
     
    public func contains(_ source: ConfigurationSourceRecord) -> Bool {
        if source.nodeChain != nil { return self == .proxyChains }
        switch source.origin {
        case .subscription: return self == .subscriptions
        case .file: return self == .files
        case .customNodes: return self == .customNodes
        case .bundled: return false
        }
    }
}

public struct ClashMacNodeLibraryShelf: Identifiable, Equatable {
    public let group: ClashMacNodeLibraryGroup
    public let sources: [ConfigurationSourceRecord]
    public var id: String { group.identifier }
}

public struct ClashMacRuleLibraryShelf: Identifiable, Equatable {
    public let section: ClashConfigurationRuleLibrarySection
    public let schemes: [ConfigurationRuleScheme]
    public var id: String { section.title }
}

 
 
public struct ClashMacRuleLibrarySection: Identifiable, Equatable {
    public let section: ClashConfigurationRuleLibrarySection
    public let schemes: [ConfigurationRuleScheme]
    public let ruleSetSources: [ConfigurationSourceRecord]
    public var id: String { section.title }
}

 
 
 
 
 
 
@MainActor
public final class ClashMacConfigurationLibraryModel: ObservableObject {
    public enum Phase: Equatable, Sendable {
        case idle, loading, ready
        case failed(String)
    }

    @Published public private(set) var snapshot = ConfigurationLibrarySnapshot()
     
     
     
     
    public var locale: Locale = .current
     
     
     
     
    @Published public private(set) var nodeShelves: [ClashMacNodeLibraryShelf] = []
    @Published public private(set) var ruleShelves: [ClashMacRuleLibraryShelf] = []
     
    @Published public private(set) var schemeUsage: [String: Int] = [:]
     
    @Published public private(set) var collections: [ConfigurationCollectionEntry] = []
    private var collectionsGeneration: UInt64?
     
     
    private var libraryCollections: [ConfigurationCollectionEntry] = []
     
     
     
     
    private var libraryReadTicket = 0
    private var countTicket = 0
    @Published public private(set) var phase: Phase = .idle
     
    @Published public private(set) var isBusy = false
     
     
     
     
    private var waiting: [CheckedContinuation<Void, Never>] = []
     
    @Published public private(set) var updatingSourceIDs: Set<String> = []
     
    @Published public private(set) var updatingCollectionIDs: Set<ConfigurationCollection.ID> = []
    public var canUpdateCollections: Bool { actions.updateCollection != nil }
     
    @Published public private(set) var lastError: String?
     
    @Published public private(set) var updateProgress: String?
     
    @Published public private(set) var updateStatus: String?
     
    @Published public private(set) var updateError: String?
    public var isUpdatingAll: Bool { updateProgress != nil }
     
     
    @Published public private(set) var updateFailures: [String: String] = [:]
     
     
     
    @Published public private(set) var ruleConflictSourceID: String?

    private let actions: ClashMacConfigurationLibraryActions

    public init(actions: ClashMacConfigurationLibraryActions) {
        self.actions = actions
    }

    public func reload() async {
        if phase != .ready { phase = .loading }
        do {
            let loaded = try await actions.load()
            _ = apply(loaded)
            phase = .ready
        } catch {
            phase = .failed(ClashErrorCopy.message(error, locale: locale))
        }
    }

     
    @discardableResult
    public func apply(_ next: ConfigurationLibrarySnapshot) -> Bool {
        guard next.generation >= snapshot.generation else { return false }
        guard next != snapshot || phase != .ready else { return true }
        snapshot = next
        nodeShelves = Self.nodeShelves(next)
        ruleShelves = Self.ruleShelves(next)
        schemeUsage = Self.schemeUsage(next)
        refreshCollections(next)
        return true
    }

     
     
     
     
     
     
    public func reloadCollections() {
        guard let counts = actions.runningCounts else { return }
        countTicket &+= 1
         
         
        guard !libraryCollections.isEmpty else { return }
        let ticket = countTicket
        let library = libraryCollections
        Task { [weak self] in
            let counted = await counts(library)
            await MainActor.run {
                guard let self, self.countTicket == ticket else { return }
                if self.collections != counted { self.collections = counted }
            }
        }
    }

    private func refreshCollections(_ next: ConfigurationLibrarySnapshot) {
        guard collectionsGeneration != next.generation else { return }
        collectionsGeneration = next.generation
        libraryReadTicket &+= 1
        let ticket = libraryReadTicket
         
         
        let asked = countTicket
        let load = actions.loadCollections
        let counts = actions.runningCounts
        Task { [weak self] in
             
             
             
             
            guard let loaded = try? await load(next) else {
                await MainActor.run {
                    guard let self, self.libraryReadTicket == ticket else { return }
                    self.collectionsGeneration = nil
                }
                return
            }
            let counted = await counts?(loaded) ?? loaded
            await MainActor.run {
                guard let self, self.libraryReadTicket == ticket,
                      self.collectionsGeneration == next.generation else { return }
                let owed = self.countTicket != asked
                self.libraryCollections = loaded
                self.countTicket &+= 1
                if self.collections != counted { self.collections = counted }
                if owed { self.reloadCollections() }
            }
        }
    }

     
    public func collections(for sourceID: String, kind: ConfigurationCollection.Kind = .nodes) -> [ConfigurationCollectionEntry] {
        collections.filter { $0.source.id == sourceID && $0.id.kind == kind }
    }

    @discardableResult
    public func saveSourceSettings(_ id: String, draft: ConfigurationSourceSettingsDraft) async -> Bool {
        await write { [actions] generation in try await actions.saveSourceSettings(id, draft, generation) }
    }

     
     
    @discardableResult
    public func saveSourceDetails(_ id: String, label: String, settings: ConfigurationSourceSettingsDraft?) async -> Bool {
        await write { [actions] generation in try await actions.saveSourceDetails(id, label, settings, generation) }
    }

    public func clearError() { lastError = nil }

     
     
     
    public weak var feedback: ClashFeedbackCenter?
    public static let updateOperation = "library.update"
    private var runningUpdate: Int?

     
     
    @discardableResult
    public func updateSourceSaying(_ id: String, replacingRules: Bool = false, label named: String? = nil) async -> Bool {
         
        let label = named ?? snapshot.sources.first { $0.id == id }?.label ?? id
        let before = snapshot.sources.first { $0.id == id }?.version
        let ok = await updateSource(id, replacingRules: replacingRules)
        let operation = "source.update." + id
        if ok {
            let after = snapshot.sources.first { $0.id == id }?.version
            feedback?.say(after == before
                ? ClashMacFeedbackSentences.upToDate(label, id: "source.update")
                : ClashMacFeedbackSentences.updated(label, id: "source.update"), operation: operation)
        } else if ruleConflictSourceID != id, let reason = lastError {
            feedback?.say(ClashMacFeedbackSentences.couldNotUpdate(label, reason: reason, id: "source.update"),
                           operation: operation)
        }
        return ok
    }

     
     
     
    public func report(_ message: String) { lastError = message }

    @discardableResult
    public func renameSource(_ id: String, label: String) async -> Bool {
        await write { [actions] generation in try await actions.renameSource(id, label, generation) }
    }

    @discardableResult
    public func deleteSource(_ id: String) async -> Bool {
        await write { [actions] generation in try await actions.deleteSource(id, generation) }
    }

    @discardableResult
    public func deleteRuleScheme(_ id: String) async -> Bool {
        await write { [actions] generation in try await actions.deleteRuleScheme(id, generation) }
    }

     
    public var deletesUndoably: Bool {
        actions.deleteSourceRestorably != nil && actions.deleteRuleSchemeRestorably != nil && actions.restoreRemoval != nil
    }

     
     
    public func deleteSourceRestorably(_ id: String) async -> ClashMacLibraryDeletion? {
        guard let delete = actions.deleteSourceRestorably else { return nil }
        return await writeTaking { generation in
            let (next, removal) = try await delete(id, generation)
            return (next, ClashMacLibraryDeletion(removal: removal, generation: next.generation))
        }
    }

    public func deleteRuleSchemeRestorably(_ id: String) async -> ClashMacLibraryDeletion? {
        guard let delete = actions.deleteRuleSchemeRestorably else { return nil }
        return await writeTaking { generation in
            let (next, removal) = try await delete(id, generation)
            return (next, ClashMacLibraryDeletion(removal: removal, generation: next.generation))
        }
    }

     
     
     
     
    public enum RestoreOutcome: Equatable, Sendable { case restored, superseded(String), failed(String) }

    public func restore(_ deletion: ClashMacLibraryDeletion) async -> RestoreOutcome {
        guard let restore = actions.restoreRemoval else { return .failed("") }
        await acquire()
        lastError = nil
        defer { release() }
        do {
            apply(try await restore(deletion.removal, deletion.generation))
            return .restored
        } catch ConfigurationLibraryError.staleGeneration {
            lastError = ClashErrorCopy.message(ConfigurationLibraryError.staleGeneration, locale: locale)
            return .superseded(lastError ?? "")
        } catch {
            lastError = ClashErrorCopy.message(error, locale: locale)
            return .failed(lastError ?? "")
        }
    }

     
     
    public func serialized(_ operation: @MainActor () async throws -> Void) async throws {
        await acquire()
        defer { release() }
        try await operation()
    }

    private func writeTaking<Taken>(_ operation: (UInt64) async throws -> (ConfigurationLibrarySnapshot, Taken)) async -> Taken? {
        await acquire()
        lastError = nil
        defer { release() }
        do {
            let (next, taken) = try await operation(snapshot.generation)
            apply(next)
            return taken
        } catch ConfigurationLibraryError.staleGeneration {
            await reload()
            do {
                let (next, taken) = try await operation(snapshot.generation)
                apply(next)
                return taken
            } catch {
                lastError = ClashErrorCopy.message(error, locale: locale)
                return nil
            }
        } catch {
            lastError = ClashErrorCopy.message(error, locale: locale)
            return nil
        }
    }

     
     
    public func addSource(_ payload: ConfigurationSourcePayload) async throws {
        try await writeOrThrow { [actions] generation in try await actions.addSource(payload, generation) }
    }

    public func addRuleScheme(_ payload: ConfigurationSourcePayload) async throws {
        try await writeOrThrow { [actions] generation in try await actions.addRuleScheme(payload, generation) }
    }

     
     
    public func copyScheme(_ id: String, label: String) async throws -> String {
        let before = Set(snapshot.rules.map(\.id))
        try await writeOrThrow { [actions] generation in try await actions.copyScheme(id, label, generation) }
        guard let made = snapshot.rules.first(where: { !before.contains($0.id) }) else {
            throw ConfigurationLibraryError.unreadable
        }
        return made.id
    }

    private func writeOrThrow(_ operation: (UInt64) async throws -> ConfigurationLibrarySnapshot) async throws {
        await acquire()
        lastError = nil
        defer { release() }
        try await writeOnce(operation)
    }

     
     
     
    public func updateAllSources() async {
        guard updateProgress == nil else { return }
        guard let batch = actions.updateAllSources else {
            for source in snapshot.sources {
                if case .subscription = source.origin { _ = await updateSource(source.id) }
            }
            return
        }
        await runBatch(batch, statusKey: "Resources updated")
    }

     
     
    public func updateAllRuleSets() async {
        guard updateProgress == nil, let batch = actions.updateAllRuleSets else { return }
        await runBatch(batch, statusKey: "Rule sets updated", runningKey: "Updating Rule Sets…")
    }

     
     
     
    public func updateEverything() async {
        guard updateProgress == nil else { return }
        let legacy = actions.syncLegacyProfiles
        let sources = actions.updateAllSources
        let rules = actions.updateAllRuleSets
        guard legacy != nil || sources != nil || rules != nil else { return }
        await runBatch({ progress in
            var total = ClashMacBatchOutcome()
            for stage in [legacy, sources, rules].compactMap({ $0 }) {
                let outcome = await stage(progress)
                total.updated += outcome.updated
                total.notTaken += outcome.notTaken
                total.unconfirmed += outcome.unconfirmed
                total.appliesOnConnect = total.appliesOnConnect || outcome.appliesOnConnect
                total.failures += outcome.failures
            }
            return total
        }, statusKey: "Resources updated")
    }

     
     
    public var hasLinkedNodes: Bool {
        snapshot.availableSources.contains { if case .subscription = $0.origin { return $0.isRetainedSnapshot != true && $0.suppliesNodes }; return false }
            || collections.contains { $0.collection.id.kind == .nodes && $0.collection.type == "http" && $0.source.isRetainedSnapshot != true }
    }

     
     
    public var hasLinkedRuleSets: Bool {
        Self.libraryRuleSets(collections, in: snapshot)
            .contains { $0.collection.id.kind == .rules && $0.collection.type == "http" && $0.source.isRetainedSnapshot != true }
    }

     
     
     
    nonisolated public static func foldedRuleSets(
        of scheme: ConfigurationRuleScheme, _ bySource: [String: [ConfigurationCollectionEntry]]
    ) -> [ConfigurationCollectionEntry]? {
        guard scheme.collectionKey == nil else { return nil }
        return bySource[scheme.sourceID]
    }

     
     
     
     
    nonisolated public static func libraryRuleSets(
        _ entries: [ConfigurationCollectionEntry], in snapshot: ConfigurationLibrarySnapshot
    ) -> [ConfigurationCollectionEntry] {
         
         
         
         
        let read = snapshot.sourcesWhoseRulesAreRead
        return entries.filter { $0.id.kind != .rules || !$0.source.suppliesNodes || read.contains($0.source.id) }
    }

     
     
     
     
     
     
     
    public func hasLinkedContent(legacyProfiles: Bool) -> Bool {
        legacyProfiles || hasLinkedNodes || hasLinkedRuleSets
    }

    private func runBatch(
        _ batch: @MainActor (_ progress: @escaping @MainActor (String) -> Void) async -> ClashMacBatchOutcome, statusKey: String,
        runningKey: String = "Updating Sources…"
    ) async {
        updateProgress = ""
        updateStatus = nil
        updateError = nil
        runningUpdate = feedback?.say(.loading(title: .copy(runningKey), accessibilityIdentifier: "feedback.library.update.running"),
                                       operation: Self.updateOperation)
        let outcome = await batch { [weak self] line in
            self?.updateProgress = line
             
            if let self, let id = self.runningUpdate, !line.isEmpty {
                self.feedback?.update(id, to: .loading(title: .verbatim(line), accessibilityIdentifier: "feedback.library.update.running"))
            }
        }
        await reload()
         
        collectionsGeneration = nil
        refreshCollections(snapshot)
        updateProgress = nil
        updateStatus = Self.summaryLine(ClashCopy.string(statusKey, locale: locale), outcome, locale: locale)
        updateError = outcome.failures.isEmpty ? nil : outcome.failures.joined(separator: "\n")
        sayBatch(outcome)
    }

     
     
    private func sayBatch(_ outcome: ClashMacBatchOutcome) {
         
         
         
        let failed = outcome.notTaken
         
         
         
        let pending = outcome.unconfirmed > 0 ? ClashCopy.format("%d not confirmed", locale: locale, outcome.unconfirmed) : nil
        let onConnect = outcome.appliesOnConnect ? ClashCopy.string("Applied when Clash connects", locale: locale) : nil
         
         
        let pendingOnly = outcome.updated == 0 && failed == 0 && pending != nil
        let title: ClashDisplayText = pendingOnly
            ? .verbatim(pending ?? "")
            : ClashFeedbackCopy.batch(updated: outcome.updated, failed: failed,
                                      unchanged: outcome.updated == 0 && failed == 0 ? 1 : 0)
        let lines = (pendingOnly ? [] : [pending].compactMap { $0 }) + [onConnect].compactMap { $0 } + outcome.failures
        let message: ClashDisplayText? = lines.isEmpty ? nil : .verbatim(lines.joined(separator: "\n"))
        let result: ClashFeedbackPresentation = failed > 0
            ? .warning(title: title, message: message, isBatchSummary: true, accessibilityIdentifier: "feedback.library.update.summary")
            : pendingOnly
            ? .information(title: title, message: message, isBatchSummary: true, accessibilityIdentifier: "feedback.library.update.summary")
            : .success(title: title, message: message, isBatchSummary: true, accessibilityIdentifier: "feedback.library.update.summary")
        if let id = runningUpdate, feedback?.update(id, to: result) == true {} else {
            feedback?.say(result, operation: Self.updateOperation)
        }
        runningUpdate = nil
    }

     
    private func sayCollection(_ entry: ConfigurationCollectionEntry, _ outcome: ClashMacBatchOutcome) {
        let failed = outcome.notTaken
        let result: ClashFeedbackPresentation? = failed > 0
            ? .error(title: ClashFeedbackCopy.couldNotUpdate(entry.collection.name),
                     message: outcome.failures.isEmpty ? nil : .verbatim(outcome.failures.joined(separator: "\n")),
                     accessibilityIdentifier: "feedback.collection.update.failed")
            : outcome.word == "Up to date" ? ClashMacFeedbackSentences.upToDate(entry.collection.name, id: "collection.update")
            : outcome.word == "Updated" ? ClashMacFeedbackSentences.updated(entry.collection.name, id: "collection.update")
             
             
            : nil
        guard let result else { return }
        feedback?.say(result, operation: "collection.update." + entry.collection.name)
    }

     
     
     
     
     
    nonisolated public static func summaryLine(_ head: String, _ outcome: ClashMacBatchOutcome, locale: Locale) -> String {
         
        var parts = [ClashCopy.format("%@: %@", locale: locale, head, ClashCopy.count(outcome.updated, locale: locale))]
        if outcome.notTaken > 0 { parts.append(ClashCopy.format("%d failed", locale: locale, outcome.notTaken)) }
        if outcome.unconfirmed > 0 { parts.append(ClashCopy.format("%d not confirmed", locale: locale, outcome.unconfirmed)) }
        if outcome.appliesOnConnect { parts.append(ClashCopy.string("Applied when Clash connects", locale: locale)) }
        return parts.joined(separator: " · ")
    }

     
     
    public func clearUpdateStatus() { updateStatus = nil; updateError = nil }

     
     
     
     
    public func updateCollection(_ entry: ConfigurationCollectionEntry) async {
        guard let update = actions.updateCollection, updateProgress == nil,
              !updatingCollectionIDs.contains(entry.id) else { return }
        updatingCollectionIDs.insert(entry.id)
        updateStatus = nil
        updateError = nil
        defer { updatingCollectionIDs.remove(entry.id) }
        do {
            let outcome = try await update(entry)
             
             
             
            updateStatus = Self.summaryLine(ClashCopy.string("Rule sets updated", locale: locale), outcome, locale: locale)
            sayCollection(entry, outcome)
        } catch {
            updateError = ClashCopy.format("%@: %@", locale: locale, entry.collection.name, ClashErrorCopy.message(error, locale: locale))
            feedback?.say(ClashMacFeedbackSentences.couldNotUpdate(entry.collection.name, reason: ClashErrorCopy.message(error, locale: locale),
                                                                     id: "collection.update"),
                           operation: "collection.update." + entry.collection.name)
        }
         
        collectionsGeneration = nil
        refreshCollections(snapshot)
    }

     
     
    @discardableResult
    public func updateSource(_ id: String, replacingRules: Bool = false) async -> Bool {
        guard !updatingSourceIDs.contains(id) else { return false }
        updatingSourceIDs.insert(id)
        lastError = nil
        updateFailures[id] = nil
        ruleConflictSourceID = nil
        defer { updatingSourceIDs.remove(id) }
        do {
            if replacingRules {
                let version = snapshot.sources.first { $0.id == id }?.version
                try await actions.updateSourceReplacingRules(id, version)
            } else {
                try await actions.updateSource(id)
            }
            await reload()
            return true
        } catch {
            if error is ConfigurationRuleReplay.Conflict {
                ruleConflictSourceID = id
            } else {
                updateFailures[id] = ClashConfigurationUpdateCopy.message(error, locale: locale)
                lastError = ClashErrorCopy.message(error, locale: locale)
            }
            return false
        }
    }

    public func dismissRuleConflict() { ruleConflictSourceID = nil }

    private func write(_ operation: (UInt64) async throws -> ConfigurationLibrarySnapshot) async -> Bool {
        await acquire()
        lastError = nil
        defer { release() }
        do {
            try await writeOnce(operation)
            return true
        } catch {
            lastError = ClashErrorCopy.message(error, locale: locale)
            return false
        }
    }

     
     
    private func acquire() async {
        if !isBusy { isBusy = true; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty { isBusy = false } else { waiting.removeFirst().resume() }
    }

     
     
     
     
    private func writeOnce(_ operation: (UInt64) async throws -> ConfigurationLibrarySnapshot) async throws {
        do {
            let next = try await operation(snapshot.generation)
            apply(next)
        } catch ConfigurationLibraryError.staleGeneration {
            await reload()
            let next = try await operation(snapshot.generation)
            apply(next)
        }
    }

     

     
    nonisolated public static func nodeShelves(_ snapshot: ConfigurationLibrarySnapshot) -> [ClashMacNodeLibraryShelf] {
        let sources = snapshot.availableSources.filter(\.suppliesNodes)
        return ClashMacNodeLibraryGroup.allCases.compactMap { group in
            let members = sources.filter { group.contains($0) }
            return members.isEmpty ? nil : ClashMacNodeLibraryShelf(group: group, sources: members)
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    nonisolated public static func ruleShelves(
        _ snapshot: ConfigurationLibrarySnapshot, keeping selectedID: String? = nil
    ) -> [ClashMacRuleLibraryShelf] {
        var schemes = snapshot.placingOwnViews(in: snapshot.visibleRuleSchemes, for: nil, running: selectedID)
        if let selectedID, !schemes.contains(where: { $0.id == selectedID }),
           let selected = snapshot.rules.first(where: { $0.id == selectedID }) {
            let family = selected.baseSchemeID ?? selected.id
            if let index = schemes.firstIndex(where: {
                ConfigurationBuiltins.isNative(family) ? $0.id == selected.id : ($0.baseSchemeID ?? $0.id) == family
            }) {
                schemes[index] = selected
            } else {
                schemes.append(selected)
            }
        }
        return ClashConfigurationRuleLibrarySection.allCases.compactMap { section in
            let members = schemes.filter { section.contains($0, library: snapshot) }
            return members.isEmpty ? nil : ClashMacRuleLibraryShelf(section: section, schemes: members)
        }
    }

     
     
     
     
     
     
     
     
    nonisolated public static func ruleLibrarySections(
        _ snapshot: ConfigurationLibrarySnapshot, shelves: [ClashMacRuleLibraryShelf],
        collections: [ConfigurationCollectionEntry]
    ) -> [ClashMacRuleLibrarySection] {
        let withScheme = Set(shelves.flatMap { $0.schemes.map(\.sourceID) })
        let carrying = Set(collections.lazy.filter { $0.id.kind == .rules && $0.source.isListedInLibrary }.map(\.source.id))
         
         
         
         
        let alone = snapshot.availableSources.filter {
            carrying.contains($0.id) && !withScheme.contains($0.id) && !$0.suppliesNodes
        }
        return ClashConfigurationRuleLibrarySection.allCases.compactMap { section in
            let schemes = shelves.first { $0.section == section }?.schemes ?? []
            let sources = alone.filter { section.contains($0) }
            guard !schemes.isEmpty || !sources.isEmpty else { return nil }
            return ClashMacRuleLibrarySection(section: section, schemes: schemes, ruleSetSources: sources)
        }
    }

     
     
     
    nonisolated public static func link(of source: ConfigurationSourceRecord) -> String? {
        guard source.nodeChain == nil, case .subscription(let link) = source.origin else { return nil }
        return link
    }

     
     
     
     
     
    nonisolated public static func canDeleteSource(_ source: ConfigurationSourceRecord) -> Bool {
        if case .bundled = source.origin { return false }
        return source.isRetainedSnapshot != true && !source.suppliesNodes
    }

     
     
     
     
    public func configurations(usingSource id: String) -> [String] {
        snapshot.recipes
            .filter { recipe in recipe.dependencies.contains { $0.id == id } }
            .map(\.id)
    }

     
     
     
     
     
    public func configurations(usingScheme id: String) -> [String] {
        let family = Self.family(of: id, in: snapshot)
        return snapshot.recipes.filter { family.contains($0.ruleSchemeID) }.map(\.id)
    }

     
     
     
     
     
    nonisolated static func family(of id: String, in snapshot: ConfigurationLibrarySnapshot) -> Set<String> {
        let base = snapshot.rules.first { $0.id == id }?.baseSchemeID ?? id
        if ConfigurationBuiltins.isNative(base) { return [id] }
        var members: Set<String> = [id, base]
        for scheme in snapshot.rules where scheme.baseSchemeID == base { members.insert(scheme.id) }
        return members
    }

     
     
    nonisolated static func schemeUsage(_ snapshot: ConfigurationLibrarySnapshot) -> [String: Int] {
        var counts: [String: Int] = [:]
        var families: [String: Set<String>] = [:]
        for recipe in snapshot.recipes {
            let members = families[recipe.ruleSchemeID] ?? {
                let f = family(of: recipe.ruleSchemeID, in: snapshot); families[recipe.ruleSchemeID] = f; return f
            }()
            for member in members { counts[member, default: 0] += 1 }
        }
        return counts
    }

     
     
    public func usageCount(ofScheme id: String) -> Int { schemeUsage[id] ?? 0 }

     
    public func source(of scheme: ConfigurationRuleScheme) -> ConfigurationSourceRecord? {
        snapshot.sources.first { $0.id == scheme.sourceID }
    }
}

 
 
 
 
 
 
public enum ClashMacConfigurationUsageFacts {
    public static func singleLinkUsage(configurationID: String, in snapshot: ConfigurationLibrarySnapshot) -> ConfigurationSubscriptionUsage? {
        guard let recipe = snapshot.recipes.first(where: { $0.id == configurationID }),
              recipe.sources.count == 1, let reference = recipe.sources.first,
              let record = snapshot.sources.first(where: { $0.id == reference.id }),
              case .subscription = record.origin else { return nil }
        return record.subscriptionUsage
    }

     
     
     
     
    public static func usage(configurationID: String, fetched: ClashProfileSubscriptionSnapshot?,
                             in snapshot: ConfigurationLibrarySnapshot) -> ConfigurationSubscriptionUsage? {
        if snapshot.recipes.contains(where: { $0.id == configurationID }) {
            return singleLinkUsage(configurationID: configurationID, in: snapshot)
        }
        return fetched.map {
            ConfigurationSubscriptionUsage(upload: $0.uploadBytes, download: $0.downloadBytes, total: $0.totalBytes,
                                           expire: $0.expiration.map { Int64($0.timeIntervalSince1970) } ?? 0)
        }
    }
}

 
public enum ClashMacSubscriptionUsageCopy {
     
     
    @MainActor private static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter
    }()
    private static let dateFormatters = ClashMacDateFormatterCache(dateStyle: .medium, timeStyle: .none)

     
    @MainActor public static func traffic(_ usage: ConfigurationSubscriptionUsage) -> ClashDisplayText {
        let formatter = bytes
        let used = formatter.string(fromByteCount: usage.used)
        guard usage.total > 0 else { return .format("Used %@", [used]) }
        return .format("%@ of %@ used", [used, formatter.string(fromByteCount: usage.total)])
    }

     
    public static func expiry(_ usage: ConfigurationSubscriptionUsage, locale: Locale) -> ClashDisplayText? {
        guard usage.expire > 0 else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(usage.expire))
        return .format("Expires %@", [dateFormatters.formatter(for: locale).string(from: date)])
    }
}

 
 
public final class ClashMacDateFormatterCache: @unchecked Sendable {
    private let dateStyle: DateFormatter.Style
    private let timeStyle: DateFormatter.Style
    private var formatters: [String: DateFormatter] = [:]
    private let lock = NSLock()

    public init(dateStyle: DateFormatter.Style, timeStyle: DateFormatter.Style) {
        self.dateStyle = dateStyle
        self.timeStyle = timeStyle
    }

    public func formatter(for locale: Locale) -> DateFormatter {
        lock.lock(); defer { lock.unlock() }
        if let cached = formatters[locale.identifier] { return cached }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        formatters[locale.identifier] = formatter
        return formatter
    }
}

 
 
 
public struct ClashMacBatchOutcome: Sendable {
    public var updated: Int
     
     
     
    public var notTaken: Int
     
     
    public var unconfirmed: Int
     
    public var appliesOnConnect: Bool
    public var failures: [String]
     
     
     
     
    public var word: String?
    public init(updated: Int = 0, notTaken: Int = 0, unconfirmed: Int = 0, appliesOnConnect: Bool = false, failures: [String] = []) {
        self.updated = updated; self.notTaken = notTaken; self.unconfirmed = unconfirmed
        self.appliesOnConnect = appliesOnConnect; self.failures = failures
    }
}

extension ConfigurationRuleScheme {
     
     
    var canBeDeleted: Bool {
        !ConfigurationBuiltins.isNative(id) && isRetainedSnapshot != true
            && (kind == .imported || kind == .custom || kind == .supplied)
    }
}

 
public struct ClashMacLibraryDeletion: Sendable {
    public let removal: ConfigurationLibraryRemoval
    public let generation: UInt64
    public init(removal: ConfigurationLibraryRemoval, generation: UInt64) {
        self.removal = removal
        self.generation = generation
    }
}
