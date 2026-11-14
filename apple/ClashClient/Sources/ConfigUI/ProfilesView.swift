import Combine
import ClashClientKit
import ClashClientUI
import SwiftUI
import UniformTypeIdentifiers

 
 
 
private actor LocalProfilePreviewCache {
    static let shared = LocalProfilePreviewCache()

    private var values: [String: String] = [:]

    func text(for profile: Profile, container: URL?) -> String? {
        if let published = activeRevisionSource(for: profile, container: container) {
             
            return text(for: published).map { PublishedPresentation.withModeChosen($0) }
        }
        guard let source = sidecarSource(for: profile, container: container) else { return nil }
        return text(for: source)
    }

     
     
     
    func exportText(for profile: Profile, container: URL?) -> String? {
        guard let source = sidecarSource(for: profile, container: container)
            ?? activeRevisionSource(for: profile, container: container)
        else { return nil }
        return text(for: source)
    }

     
     
     
     
     
    private func text(
        for source: (cacheKey: String, cacheNamespace: String, yaml: String)
    ) -> String? {
        if let cached = values[source.cacheKey] { return cached }
        let staleKeys = values.keys.filter {
            $0 != source.cacheKey && $0.hasPrefix("\(source.cacheNamespace)|")
        }
        staleKeys.forEach { values.removeValue(forKey: $0) }
        values[source.cacheKey] = source.yaml
        return source.yaml
    }

    private func activeRevisionSource(
        for profile: Profile,
        container: URL?
    ) -> (cacheKey: String, cacheNamespace: String, yaml: String)? {
        guard let container else { return nil }

        if let revision = profile.activeRevision,
           let stored = try? ConfigResourceStore(containerURL: container)
               .loadConfiguration(profileID: profile.id, revision: revision),
           let published = stored.text {
             
            let yaml = PublishedRulesAsWritten.restoring(
                published, profileID: profile.id, revision: revision,
                workingDirectory: container.appendingPathComponent("working", isDirectory: true))
            let namespace = "revision|\(profile.id)"
            return ("\(namespace)|\(revision)", namespace, yaml)
        }

        return nil
    }

    private func sidecarSource(
        for profile: Profile,
        container: URL?
    ) -> (cacheKey: String, cacheNamespace: String, yaml: String)? {
        guard let container else { return nil }
        let sidecar = container
            .appendingPathComponent("working/store/\(profile.id)/source.yaml")
        guard let yaml = try? String(contentsOf: sidecar, encoding: .utf8) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: sidecar.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? Int64(yaml.utf8.count)
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let namespace = "source|\(profile.id)"
        return ("\(namespace)|\(sidecar.path)|\(size)|\(modified)", namespace, yaml)
    }
}

 
 
 
 
 
 
 
 
 
@propertyWrapper
struct PublishedWhenChanged<Value: Equatable> {
    private var value: Value
    private let subject: CurrentValueSubject<Value, Never>

    init(wrappedValue: Value) {
        value = wrappedValue
        subject = CurrentValueSubject(wrappedValue)
    }

    var projectedValue: AnyPublisher<Value, Never> { subject.eraseToAnyPublisher() }

    @available(*, unavailable)
    var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }

    static subscript<Object: ObservableObject>(
        _enclosingInstance object: Object,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<Object, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<Object, Self>
    ) -> Value where Object.ObjectWillChangePublisher == ObservableObjectPublisher {
        get { object[keyPath: storageKeyPath].value }
        set {
            guard object[keyPath: storageKeyPath].value != newValue else { return }
            object.objectWillChange.send()
            object[keyPath: storageKeyPath].value = newValue
            object[keyPath: storageKeyPath].subject.send(newValue)
        }
    }
}

 
 
@MainActor
final class ProfilesViewModel: ObservableObject {
     
     
     
    var resourceStoreForHomeTally: ConfigResourceStore? {
        container.flatMap { try? ConfigResourceStore(containerURL: $0) }
    }

     
     
     
    @Published private(set) var profiles: [Profile] = [] {
        didSet { editableSourceCache.removeAll() }
    }
     
     
     
     
    private var editableSourceCache: [String: Bool] = [:]
    private(set) var editableSourceStatsForTesting = 0
    @PublishedWhenChanged private(set) var savedConfigurationGeneration: UInt64 = 0
     
     
     
     
     
     
     
     
     
     
    private(set) var publishedGenerations: [String: UInt64] = [:]
    func publishedGeneration(of profileID: String) -> UInt64 { publishedGenerations[profileID] ?? 0 }
     
     
    private func notePublished<IDs: Sequence>(_ ids: IDs) where IDs.Element == String {
        let next = savedConfigurationGeneration &+ 1
        for id in ids { publishedGenerations[id] = next }
        savedConfigurationGeneration = next
    }
    @PublishedWhenChanged private(set) var activeProfileID: String? = nil
    @PublishedWhenChanged private(set) var busyProfileID: String? = nil {
        didSet {
             
             
             
             
             
             
            if busyProfileID == nil, oldValue != nil, pendingActivation != nil {
                Task { @MainActor [weak self] in self?.drainPendingActivation() }
            } else if busyProfileID == nil, oldValue != nil, builtinUpgradeRestageOwed != nil {
                 
                 
                 
                 
                Task { @MainActor [weak self] in self?.restageOwedBuiltinUpgrade() }
            }
        }
    }
     
     
    private var deletingProfileIDs: Set<String> = []
     
     
     
     
     
     
    @PublishedWhenChanged private(set) var isActivating = false
     
     
     
     
    @PublishedWhenChanged private(set) var hasLoadedProfiles = false
     
     
     
    @PublishedWhenChanged private(set) var activationAppliesToTunnel: Bool? = nil
     
     
     
     
    @PublishedWhenChanged private(set) var isAwaitedActivationInFlight = false
     
     
     
    @PublishedWhenChanged private(set) var statusMessage: ClashDisplayText = .copy("")
     
     
     
     
    struct TunnelApplyRecord: Equatable {
        var sequence: UInt64 = 0
        var profileID: String?
        var outcome: TunnelApplyOutcome?
    }
    private(set) var lastTunnelApply = TunnelApplyRecord()

     
     
     
     
    nonisolated static func restartNotice(profileID: String, since sequence: UInt64,
                                          last: TunnelApplyRecord) -> ClashDisplayText? {
        guard last.sequence != sequence, last.profileID == profileID, last.outcome == .restarted else { return nil }
        return .copy("Applied. The tunnel reconnected to apply it.")
    }


    @PublishedWhenChanged private(set) var notices: [String] = []
    @PublishedWhenChanged private(set) var planErrors: [String] = []
    @PublishedWhenChanged private(set) var lastFailure: ConfigurationFailure? = nil
     
     
     
     
    @Published private(set) var libraryHasFetchableSource = false
    private var hasNotedLibraryFetchability = false
    private var notedProfileIDs: Set<String> = []
    @Published private(set) var batchReport: BatchUpdateReport?
    @Published private(set) var isBatchSyncing = false

     
     
     
     
    private var baseYAMLCache: [String: (key: String, value: String?)] = [:]
    private var projectedYAMLCache: [String: (key: String, value: String?)] = [:]
     
    private var presentedProxiesYAMLCache: [String: (key: String, value: String?)] = [:]
     
     
    private var largeRulesVerdicts: [String: (key: String, large: Bool)] = [:]
     
     
     
    private var effectiveYAMLCache: [String: (key: String, value: String?)] = [:]
     
     
     
     
     
     
    private var sourceYAMLCache: [String: String?] = [:]

    private let vpn: VPNController
    private let credentials: CredentialStore
    private let container: URL?
    private let runtimeDefaults: UserDefaults
    private let sourceWriter: (String, Profile, URL) throws -> Void
    private let makeProfileID: () -> String
    private var activationTask: Task<Void, Never>?
    private var pendingActivation: ActivationRequest? {
        didSet { noteAwaitedActivation() }
    }
    private var batchTask: Task<Void, Never>?
     
     
     
     
     
     
    struct NodeLibraryUpdateRun: Equatable {
        let id: UUID
        var progress: String?
        var finished = false
         
         
        var updated = 0
        var failures: [String] = []
        var finishedAt: Date?
         
        var total = 0
         
         
         
        var unconfirmed = 0
         
        var appliesOnConnect = false

         
         
         
         
         
         
        static func outcome(_ result: ConfigurationCollectionContentBridge.BatchResult, sources: Int,
                            take: CollectionTake) -> (updated: Int, total: Int) {
            let refreshed = result.updated - result.updatedEntries.count
            let asked = result.targets + CollectionUpdateRun.counted(result.coreOwned, take: take)
            let taken = CollectionUpdateRun.tookEffect(asked, downloaded: result.updatedEntries, take: take)
            return (refreshed + taken, sources + asked.count)
        }
    }
    @Published private(set) var nodeLibraryUpdate: NodeLibraryUpdateRun?
     
     
    @Published private(set) var libraryContentEpoch: UInt64 = 0
     
     
    var isUpdatingNodeLibrary: Bool { nodeLibraryUpdate.map { !$0.finished } ?? false }
     
     
     
    func waitForNodeLibraryUpdate() async {
        await nodeLibraryUpdateTask?.value
    }
    private var nodeLibraryUpdateTask: Task<Void, Never>?

     
     
    func updateNodeLibrary(locale: Locale) -> Task<Void, Never> {
        if let running = nodeLibraryUpdateTask { return running }
        let runID = UUID()
         
         
        let waits = !pageLibraryWrites.isEmpty
        nodeLibraryUpdate = NodeLibraryUpdateRun(id: runID, progress: waits
            ? ClashCopy.string("Waiting for the current update to finish…", locale: locale) : nil)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            var updated = 0
            var total = 0
            var unconfirmed = 0
            var appliesOnConnect = false
            var failures: [String] = []
            if let store = self.configurationLibraryStore {
                 
                await self.waitForPageLibraryWrites()
                if waits, self.nodeLibraryUpdate?.id == runID { self.nodeLibraryUpdate?.progress = nil }
                let sources = (try? await Task.detached { try store.snapshot() }.value)?.availableSources ?? []
                 
                var sourceTotal = 0
                 
                 
                 
                let result = await ConfigurationCollectionContentBridge.updateNodeLibrary(sources,
                    updateSource: { source in
                        try await self.refreshConfigurationSource(source.id, restagingConfigurationInUse: false)
                    },
                    collections: {
                        try await Task.detached {
                            try ConfigurationCollectionContentBridge.catalog(store, snapshot: store.snapshot())
                        }.value
                    }, updateCollection: { entry in
                        let source = try await Task.detached { try store.payload(.init(entry.source)) }.value
                        try await ConfigurationCollectionContentBridge.refresh(entry, source: source,
                                                                               inUse: self.providerCatalogInUse())
                    }, progress: { phase, index, total, name in
                        let key = phase == .sources ? "Updating Sources…" : "Updating Node Collections…"
                        if phase == .sources { sourceTotal = max(sourceTotal, total) }
                        if self.nodeLibraryUpdate?.id == runID {
                            self.nodeLibraryUpdate?.progress = ClashCopy.string(key, locale: locale)
                                + " \(index) / \(total) · " + name
                        }
                    }, naming: { $0.displayLabel(locale: locale) }, describe: { Self.failureLine($0, $1, locale: locale) })
                failures = result.failures
                 
                 
                 
                if self.nodeLibraryUpdate?.id == runID {
                    self.nodeLibraryUpdate?.progress = ClashCopy.string("Applying to the configuration in use…", locale: locale)
                }
                 
                 
                 
                 
                let take = await self.takeUpdatedCollections(
                    result.updatedEntries, failed: result.failedEntries, coreOwned: result.coreOwned, scripts: .silent,
                    locale: locale)
                failures = Self.joiningReasons(failures, take.failures)
                (updated, total) = NodeLibraryUpdateRun.outcome(result, sources: sourceTotal, take: take)
                unconfirmed = CollectionUpdateRun.unconfirmed(
                    result.targets + CollectionUpdateRun.counted(result.coreOwned, take: take), take: take)
                appliesOnConnect = take.appliesOnConnect
                await self.restageConfigurationInUseOwedBySourceRefresh()
            } else {
                failures = [ConfigurationLibraryError.unreadable.localizedDescription]
            }
            if self.nodeLibraryUpdate?.id == runID {
                self.nodeLibraryUpdate = NodeLibraryUpdateRun(id: runID, progress: nil, finished: true,
                                                              updated: updated, failures: failures,
                                                              finishedAt: Date(), total: total,
                                                              unconfirmed: unconfirmed, appliesOnConnect: appliesOnConnect)
            }
            self.libraryContentEpoch &+= 1
            self.nodeLibraryUpdateTask = nil
        }
        nodeLibraryUpdateTask = task
        return task
    }

     
    func acknowledgeNodeLibraryUpdate(_ id: UUID) {
        if nodeLibraryUpdate?.id == id, nodeLibraryUpdate?.finished == true { nodeLibraryUpdate = nil }
    }

     
     
     
     
    struct CollectionUpdateRun: Equatable {
        let id: UUID
        var progress: String?
        var finished = false
         
         
         
         
        var updated = 0
         
        var total = 0
        var failures: [String] = []
         
         
        var unconfirmed = 0
         
        var appliesOnConnect = false
         
         
         
         
        var updating: Set<ConfigurationCollection.ID> = []

         
         
         
         
         
         
         
         
         
         
         
         
         
         
        static func tookEffect(_ targets: [ConfigurationCollectionEntry], downloaded: [ConfigurationCollectionEntry],
                               take: CollectionTake) -> Int {
            let downloadedIDs = Set(downloaded.map(\.id))
            return targets.filter { entry in
                if take.notApplied.contains(entry.id) { return false }
                if take.applied.contains(entry.id) { return true }
                if take.pending.contains(entry.id) || take.skipped.contains(entry.id) { return false }
                return downloadedIDs.contains(entry.id)
            }.count
        }

         
         
         
         
        static func counted(_ coreOwned: [ConfigurationCollectionEntry], take: CollectionTake) -> [ConfigurationCollectionEntry] {
            coreOwned.filter { entry in
                [take.applied, take.notApplied, take.pending, take.skipped].contains { $0.contains(entry.id) }
            }
        }

         
         
         
         
        static func unconfirmed(_ targets: [ConfigurationCollectionEntry], take: CollectionTake) -> Int {
            targets.filter { entry in
                !take.notApplied.contains(entry.id) && !take.applied.contains(entry.id)
                    && (take.pending.contains(entry.id) || take.skipped.contains(entry.id))
            }.count
        }
    }
    @Published private(set) var ruleCollectionUpdate: CollectionUpdateRun?
    private var ruleCollectionUpdateTask: Task<Void, Never>?
     
     
     
     
    lazy var downloadRuleCollection: (ConfigurationCollectionEntry, ConfigurationLibraryStore) async throws -> Void = { [weak self] entry, store in
        let source = try await Task.detached { try store.payload(.init(entry.source)) }.value
        try await ConfigurationCollectionContentBridge.refresh(entry, source: source, inUse: self?.providerCatalogInUse())
    }
    var isUpdatingRuleCollections: Bool { ruleCollectionUpdate.map { !$0.finished } ?? false }
     
     
     
    func waitForRuleCollectionUpdate() async {
        await ruleCollectionUpdateTask?.value
    }

     
     
     
     
     
     
     
     
     
    @discardableResult
    func updateRuleCollections(_ entries: [ConfigurationCollectionEntry], scripts: ScriptEngine.Caller = .surfaced,
                               locale: Locale = .current) -> Task<Void, Never> {
        if let running = ruleCollectionUpdateTask { return running }
        let targets = entries.filter {
            $0.id.kind == .rules && $0.collection.type == "http" && $0.source.isRetainedSnapshot != true
        }
        let runID = UUID()
         
         
         
         
        let waits = isUpdatingNodeLibrary || !pageLibraryWrites.isEmpty
        ruleCollectionUpdate = CollectionUpdateRun(id: runID, progress: waits
            ? ClashCopy.string("Waiting for the current update to finish…", locale: locale)
            : Self.ruleSetProgress(0, targets.count, nil, locale: locale), total: targets.count)
        landedRuleCollections = []
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            var updated = 0
            var unconfirmed = 0
             
            var uncounted = 0
            var appliesOnConnect = false
            var failures: [String] = []
            if let store = self.configurationLibraryStore {
                 
                 
                await self.waitForNodeLibraryUpdate()
                await self.waitForPageLibraryWrites()
                if waits, self.ruleCollectionUpdate?.id == runID {
                    self.ruleCollectionUpdate?.progress = Self.ruleSetProgress(0, targets.count, nil, locale: locale)
                }
                let result = await ConfigurationCollectionContentBridge.updateRuleCollections(targets, update: { entry in
                     
                     
                     
                     
                     
                    self.markRuleCollection(entry.id, inFlight: true, run: runID)
                    defer { if self.ruleCollectionUpdate?.id == runID { self.landedRuleCollections.insert(entry.id) } }
                    try await self.downloadRuleCollection(entry, store)
                }, progress: { done, total, name in
                    guard var run = self.ruleCollectionUpdate, run.id == runID else { return }
                    run.updating.subtract(self.landedRuleCollections)
                    self.landedRuleCollections = []
                    run.progress = Self.ruleSetProgress(done, total, name, locale: locale)
                    self.ruleCollectionUpdate = run
                }, naming: { $0.displayLabel(locale: locale) }, describe: { Self.failureLine($0, $1, locale: locale) })
                 
                 
                 
                failures = result.failures + Self.cutShortReasons(result, locale: locale)
                 
                 
                 
                 
                 
                if var run = self.ruleCollectionUpdate, run.id == runID {
                    let running = self.providerCatalogInUse().map(ConfigurationCollectionContentBridge.runningIndex)
                    run.progress = ClashCopy.string("Applying to the configuration in use…", locale: locale)
                    run.updating = Set((result.targets + result.coreOwned).filter { entry in
                        running.map { !$0.providers(of: entry).isEmpty } ?? false
                    }.map(\.id))
                    self.landedRuleCollections = []
                    self.ruleCollectionUpdate = run
                }
                 
                 
                let take = await self.takeUpdatedCollections(
                    result.updatedEntries, failed: result.failedEntries, coreOwned: result.coreOwned, scripts: scripts,
                    locale: locale, step: { step in
                        guard self.ruleCollectionUpdate?.id == runID else { return }
                        self.ruleCollectionUpdate?.progress = Self.takeProgress(step, locale: locale)
                    })
                failures = Self.joiningReasons(failures, take.failures)
                let asked = result.targets + CollectionUpdateRun.counted(result.coreOwned, take: take)
                updated = CollectionUpdateRun.tookEffect(asked, downloaded: result.updatedEntries, take: take)
                unconfirmed = CollectionUpdateRun.unconfirmed(asked, take: take)
                uncounted = result.coreOwned.count - CollectionUpdateRun.counted(result.coreOwned, take: take).count
                appliesOnConnect = take.appliesOnConnect
            } else {
                failures = [ConfigurationLibraryError.unreadable.localizedDescription]
            }
            if self.ruleCollectionUpdate?.id == runID {
                self.ruleCollectionUpdate = CollectionUpdateRun(id: runID, progress: nil, finished: true,
                                                                updated: updated, total: targets.count - uncounted,
                                                                failures: failures,
                                                                unconfirmed: unconfirmed, appliesOnConnect: appliesOnConnect)
            }
            self.libraryContentEpoch &+= 1
            self.ruleCollectionUpdateTask = nil
        }
        ruleCollectionUpdateTask = task
        return task
    }

     
     
     
    func acknowledgeRuleCollectionUpdate(_ id: UUID) {
        if ruleCollectionUpdate?.id == id, ruleCollectionUpdate?.finished == true { ruleCollectionUpdate = nil }
    }

     
    private static func ruleSetProgress(_ done: Int, _ total: Int, _ name: String?, locale: Locale) -> String {
        ClashCopy.string("Updating Rule Sets…", locale: locale) + " \(done) / \(total)" + (name.map { " · " + $0 } ?? "")
    }

    private func markRuleCollection(_ id: ConfigurationCollection.ID, inFlight: Bool, run runID: UUID) {
        guard ruleCollectionUpdate?.id == runID else { return }
        if inFlight { ruleCollectionUpdate?.updating.insert(id) } else { ruleCollectionUpdate?.updating.remove(id) }
    }
     
     
    private var landedRuleCollections: Set<ConfigurationCollection.ID> = []

     
     
     
     
    nonisolated static func joiningReasons(_ first: [String], _ more: [String]) -> [String] {
        var seen = Set(first)
        return first + more.filter { seen.insert($0).inserted }
    }

     
     
     
    nonisolated static func labelled(_ subject: String, _ text: String, locale: Locale) -> String {
        ClashCopy.format("%@: %@", locale: locale, subject, text)
    }

     
     
    nonisolated static func failureLine(_ subject: String?, _ error: Error, locale: Locale) -> String {
        let message = ClashErrorCopy.message(error, locale: locale)
        return subject.map { labelled($0, message, locale: locale) } ?? message
    }

     
     
    nonisolated static func cutShortReasons(_ result: ConfigurationCollectionContentBridge.BatchResult, locale: Locale) -> [String] {
        result.failedEntries.compactMap { entry in
             
             
             
            let subject = entry.source.displayLabel(locale: locale) + " / " + entry.collection.name
            let prefix = labelled(subject, "", locale: locale)
            return result.failures.contains { $0.hasPrefix(prefix) } ? nil
                : labelled(subject, ClashCopy.string("cancelled", locale: locale), locale: locale)
        }
    }

     
     
     
     
     
    private var pageLibraryWrites: [UUID: Task<Void, Never>] = [:]

     
     
     
    func pageLibraryWrite(_ work: @escaping @MainActor () async -> Void) async {
        while isUpdatingNodeLibrary || isUpdatingRuleCollections {
            await waitForNodeLibraryUpdate()
            await waitForRuleCollectionUpdate()
        }
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            await work()
            self?.pageLibraryWrites[id] = nil
        }
        pageLibraryWrites[id] = task
        await task.value
    }

     
     
    func waitForPageLibraryWrites() async {
        for task in Array(pageLibraryWrites.values) { await task.value }
    }

     
     
     
     
    nonisolated func providerCatalogInUse() -> ProviderCatalog? {
        guard let container, let store = try? ConfigResourceStore(containerURL: container),
              store.activeIdentityOrNil() != nil,
              let directory = try? store.activeProvidersDirectory() else { return nil }
        return ProviderCatalog.load(providersDir: directory)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func applyUpdatedCollectionsToConfigurationInUse(_ updated: [ConfigurationCollectionEntry],
                                                     failed: [ConfigurationCollectionEntry] = [],
                                                     coreOwned: [ConfigurationCollectionEntry] = [],
                                                     scripts: ScriptEngine.Caller,
                                                     locale: Locale = .current) async -> [String] {
        await takeUpdatedCollections(updated, failed: failed, coreOwned: coreOwned, scripts: scripts, locale: locale).failures
    }

     
     
     
     
     
     
     
     
    struct CollectionTake: Equatable {
         
        var failures: [String] = []
         
        var applied: Set<ConfigurationCollection.ID> = []
         
        var notApplied: Set<ConfigurationCollection.ID> = []
         
         
        var unchanged: Set<ConfigurationCollection.ID> = []
         
         
         
         
        var pending: Set<ConfigurationCollection.ID> = []
         
         
         
         
        var skipped: Set<ConfigurationCollection.ID> = []
         
         
         
         
         
         
         
        var handover: TunnelApplyOutcome?
         
         
        var appliesOnConnect = false
         
         
         
         
        var checkedOnConnect: Set<ConfigurationCollection.ID> = []

         
         
         
         
        static func refusal(of outcome: TunnelApplyOutcome?, configuration: String, locale: Locale) -> String? {
            switch outcome {
            case .keptRunning?, .failed?:
                return ClashCopy.string(for: ProfilesViewModel.statusLine(label: configuration, outcome: outcome), locale: locale)
            case .applied?, .restarted?, .savedForNext?, .pending?, nil:
                return nil
            }
        }

         
         
         
         
         
         
        static func word(for id: ConfigurationCollection.ID, take: CollectionTake, libraryCopyIn: Bool) -> String? {
            if take.notApplied.contains(id) || take.pending.contains(id) || take.skipped.contains(id) { return nil }
            if take.applied.contains(id) {
                if take.checkedOnConnect.contains(id) { return "Updates when you connect" }
                if take.appliesOnConnect { return "Applied when Clash connects" }
                return take.unchanged.contains(id) ? "Up to date" : "Updated"
            }
            return libraryCopyIn ? "Updated" : nil
        }

         
         
        static func unread(_ entries: [ConfigurationCollectionEntry], reason: String) -> CollectionTake {
            var take = CollectionTake()
            take.skipped = Set(entries.map(\.id))
            take.failures = [reason]
            return take
        }

         
        enum Handover: Equatable {
             
            case applied
             
            case savedForNext
             
            case refused(String)
             
            case switched
             
             
             
             
            case unconfirmed(String)
        }

         
         
         
         
         
        static func handover(wait: PublishedRuntimeHandover.Wait, stillInUse: Bool,
                             configuration: String, locale: Locale) -> Handover? {
            if case .cancelled = wait { return nil }
            return handover(wait.outcome, stillInUse: stillInUse, configuration: configuration, locale: locale)
        }

         
         
        static func handover(_ outcome: TunnelApplyOutcome?, stillInUse: Bool,
                             configuration: String, locale: Locale) -> Handover {
            if let refusal = refusal(of: outcome, configuration: configuration, locale: locale) { return .refused(refusal) }
            guard stillInUse else { return .switched }
            switch outcome {
            case .applied?, .restarted?: return .applied
            case .savedForNext?: return .savedForNext
            case .pending?:
                return .unconfirmed(ClashCopy.string(
                    for: ProfilesViewModel.statusLine(label: configuration, outcome: outcome), locale: locale))
            case nil, .keptRunning?, .failed?:
                return .unconfirmed(ProfilesViewModel.labelled(
                    configuration, ClashCopy.string("The tunnel did not confirm this update.", locale: locale), locale: locale))
            }
        }

         
         
         
         
         
         
         
        static func appliesOnConnect(awaitingConnect: Set<String>, applied: Set<ConfigurationCollection.ID>,
                                     carriedBy entries: [ConfigurationCollectionEntry],
                                     providers: (ConfigurationCollectionEntry) -> Set<String>) -> Bool {
            !awaitingConnect.isEmpty
                && entries.contains { applied.contains($0.id) && !providers($0).isDisjoint(with: awaitingConnect) }
        }

         
         
         
         
        static func movedOn(_ now: ActiveConfigurationPointer?, from active: ActiveConfigurationPointer) -> Bool {
            now.map { $0.profileID != active.profileID } ?? false
        }
    }

     
     
     
    enum CollectionTakeStep: Equatable {
         
         
        case publishing(downloads: Int)
         
        case handingOver
         
         
        case coreUpdating(onlyRuleSets: Bool = true)
    }

     
     
     
    static func coreUpdatingStep(forKinds kinds: [String]) -> CollectionTakeStep {
        .coreUpdating(onlyRuleSets: kinds.allSatisfy { $0 == "rule" })
    }

     
    static func takeProgress(_ step: CollectionTakeStep, locale: Locale) -> String {
        switch step {
        case .publishing(let downloads):
            return ClashCopy.string(downloads > 0 ? "Downloading rule sets for the configuration in use…"
                                                  : "Applying to the configuration in use…", locale: locale)
        case .handingOver:
            return ClashCopy.string("Waiting for the tunnel to load the update…", locale: locale)
        case .coreUpdating(let onlyRuleSets):
            return ClashCopy.string(onlyRuleSets ? "Waiting for the tunnel to download rule sets…"
                                                 : "Downloading…", locale: locale)
        }
    }

     
     
     
     
     
     
    static let handoverWaitLimitNanoseconds = PublishedRuntimeHandover.waitLimitNanoseconds

     
     
    typealias HandoverWait = PublishedRuntimeHandover.Wait

     
    static func boundedHandover(limitNanoseconds: UInt64,
                                _ handOver: @escaping @MainActor () async -> TunnelApplyOutcome?,
                                landedLate: @escaping @MainActor (TunnelApplyOutcome?) -> Void) async -> HandoverWait {
        await PublishedRuntimeHandover.bounded(limitNanoseconds: limitNanoseconds, handOver, landedLate: landedLate)
    }

     
    private func handOverPublished(for profileID: String?) async -> TunnelApplyOutcome? {
        await PublishedRuntimeHandover.apply(vpn: vpn, profileID: profileID)
    }

     
     
    static func logTakeStep(_ name: String, since start: Date, _ detail: String) {
        ClashLogStore.shared.append(
            "rules take step=\(name) took=\(String(format: "%.2f", Date().timeIntervalSince(start)))s \(detail)",
            stream: .app, level: .info)
    }

     
     
     
     
     
     
     
     
     
    func takeUpdatedCollections(_ updated: [ConfigurationCollectionEntry],
                                failed: [ConfigurationCollectionEntry] = [],
                                coreOwned: [ConfigurationCollectionEntry] = [],
                                scripts: ScriptEngine.Caller = .surfaced,
                                locale: Locale = .current,
                                step: (CollectionTakeStep) -> Void = { _ in }) async -> CollectionTake {
        var take = CollectionTake()
        let entries = updated + failed + coreOwned
        guard !entries.isEmpty, let container else { return take }
         
         
         
         
         
        let store: ConfigResourceStore
        let active: ActiveConfigurationPointer
        let profile: Profile
        var catalog: ProviderCatalog
        do {
            store = try ConfigResourceStore(containerURL: container)
            guard let pointer = try store.activeIdentity() else { return take }
            guard let named = profiles.first(where: { $0.id == pointer.profileID }) else {
                return CollectionTake.unread(entries, reason: ClashCopy.string("The tunnel did not confirm this update.", locale: locale))
            }
            guard let directory = try store.activeProvidersDirectory(),
                  let loaded = ProviderCatalog.load(providersDir: directory) else {
                let file = try store.activeProvidersDirectory()?.appendingPathComponent(ProviderCatalog.fileName)
                 
                guard let file, FileManager.default.fileExists(atPath: file.path) else { return take }
                return CollectionTake.unread(entries, reason: Self.labelled(
                    named.label, ClashCopy.string("The tunnel did not confirm this update.", locale: locale), locale: locale))
            }
            active = pointer
            profile = named
            catalog = loaded
        } catch {
            return CollectionTake.unread(entries, reason: ClashErrorCopy.message(error, locale: locale))
        }
        typealias Bridge = ConfigurationCollectionContentBridge
         
         
         
        if restageOwedBySourceRefresh == active.profileID,
           let planned = await ProviderRefreshService.plannedCatalog(
               profile: profile, store: store, container: container, vpn: vpn) {
            catalog = Bridge.runningCatalog(planned: planned, recorded: catalog)
        }
        let coreFetched = await ProviderRefreshService.coreFetchedProviders(
            in: catalog, profile: profile, store: store, container: container, vpn: vpn)
         
         
        let index = Bridge.runningIndex(catalog)
        let running = Bridge.runningTake(updated: updated, failed: failed, coreOwned: coreOwned, catalog: catalog,
                                         coreFetched: coreFetched, index: index)
        guard !running.isEmpty else { return take }
        let configurationName = profile.label
        let notApplied = Self.labelled(configurationName,
            ClashCopy.string("Not applied: the configuration changed while it updated. Update again.", locale: locale),
            locale: locale)
        var failures: [String] = []
         
         
         
        var took: Set<String> = []
        var missed: Set<String> = []
        var pendingNames: Set<String> = []
        var skippedNames: Set<String> = []
        var switched = false
        var savedForNext = false
         
         
        let refusedAsAsked = running.failedAsAsked
        missed.formUnion(refusedAsAsked)
        let appFetched = running.forced.union(running.fromLibrary)
        if !appFetched.isEmpty {
            do {
                step(.publishing(downloads: running.forced.count))
                let publishing = Date()
                 
                let round = ProviderDownloadRound()
                let many = try await ProviderRefreshService.publishMany(
                    names: running.forced.sorted(), republishingAnyway: !running.fromLibrary.isEmpty,
                    profile: profile, store: store, container: container, vpn: vpn, expectedActive: active,
                    downloadRound: round, scripts: scripts)
                for failure in many.failed {
                    failures.append(Self.failureLine(configurationName + " / " + failure.name, failure.error, locale: locale))
                    missed.insert(failure.name)
                }
                if many.superseded { failures.append(notApplied); missed.formUnion(appFetched) }
                switched = many.switched
                if many.switched { skippedNames.formUnion(appFetched.subtracting(missed)) }
                var handedOver = many.pointer
                if let pointer = many.pointer {
                     
                     
                     
                     
                     
                    let published = store.providersDirectory(profileID: pointer.profileID, revision: pointer.revision)
                        .flatMap { ProviderCatalog.load(providersDir: $0) }
                    let notTaken = published.map {
                        Bridge.copiesNotTaken(running.fromLibrary, of: updated, matchedIn: catalog, published: $0,
                                              index: index)
                    } ?? []
                    took.formUnion(appFetched.subtracting(missed).subtracting(notTaken))
                    if !notTaken.isEmpty {
                        let again = try await ProviderRefreshService.publishMany(
                            names: notTaken, profile: profile, store: store, container: container, vpn: vpn,
                            expectedActive: pointer, downloadRound: round, scripts: scripts)
                        for failure in again.failed {
                            failures.append(Self.failureLine(configurationName + " / " + failure.name, failure.error, locale: locale))
                            missed.insert(failure.name)
                        }
                        if again.superseded { failures.append(notApplied); missed.formUnion(notTaken) }
                        if again.switched { switched = true; skippedNames.formUnion(Set(notTaken).subtracting(missed)) }
                        if let newer = again.pointer {
                            handedOver = newer
                            took.formUnion(Set(notTaken).subtracting(missed))
                        }
                    }
                }
                 
                 
                 
                 
                round.forgetBodies()
                Self.logTakeStep("publish", since: publishing,
                                 "downloads=\(running.forced.count) library=\(running.fromLibrary.count) failed=\(missed.count)")
                if let pointer = handedOver {
                     
                     
                     
                     
                    step(.handingOver)
                    let handingOver = Date()
                     
                     
                     
                    let wait = await Self.boundedHandover(limitNanoseconds: Self.handoverWaitLimitNanoseconds, {
                        await self.handOverPublished(for: pointer.profileID)
                    }, landedLate: { [weak self] late in
                        let landing = PublishedRuntimeHandover.lateLanding(since: handingOver) {
                            "rules take step=handover-late took=\($0)s outcome=\($1)"
                        }
                        landing(late)
                        self?.libraryContentEpoch &+= 1
                    })
                    let outcome = wait.outcome
                    Self.logTakeStep("handover", since: handingOver, {
                        switch wait {
                        case .timedOut: return "outcome=timedOut"
                        case .cancelled: return "outcome=cancelled"
                        case .answered(let answer): return "outcome=\(answer.map { String(describing: $0) } ?? "nil")"
                        }
                    }())
                    take.handover = outcome
                    let carried = took.intersection(appFetched)
                    switch CollectionTake.handover(wait: wait,
                                                   stillInUse: !CollectionTake.movedOn(store.activeIdentityOrNil(), from: active),
                                                   configuration: configurationName, locale: locale) {
                    case nil:
                         
                         
                        took.subtract(appFetched)
                    case .refused(let line)?:
                        failures.append(line)
                        missed.formUnion(carried)
                        took.subtract(appFetched)
                    case .switched?:
                        switched = true
                        skippedNames.formUnion(carried)
                        took.subtract(appFetched)
                    case .unconfirmed(let line)?:
                        failures.append(line)
                        pendingNames.formUnion(carried)
                        took.subtract(appFetched)
                    case .savedForNext?:
                        savedForNext = true
                    case .applied?:
                        break
                    }
                }
            } catch is CancellationError {
            } catch {
                 
                 
                failures.append(Self.failureLine(configurationName, error, locale: locale))
                missed.formUnion(appFetched)
                took.subtract(appFetched)
            }
        }
         
         
         
         
         
         
        var coreAwaitingConnect: Set<String> = []
        var coreUnchanged: Set<String> = []
        if !running.byCore.isEmpty, !switched, !CollectionTake.movedOn(store.activeIdentityOrNil(), from: active) {
            let nowCatalog = (try? store.activeProvidersDirectory()).flatMap { ProviderCatalog.load(providersDir: $0) } ?? catalog
            let nowCoreFetched = await ProviderRefreshService.coreFetchedProviders(
                in: nowCatalog, profile: profile, store: store, container: container, vpn: vpn)
            let stillMatched = Bridge.runningProviders(matching: entries, in: nowCatalog).intersection(nowCoreFetched)
            let targetEntries = nowCatalog.entries
                .filter { running.byCore.contains($0.name) && stillMatched.contains($0.name) }
            let targets = targetEntries.map(\.name)
            step(Self.coreUpdatingStep(forKinds: targetEntries.map(\.kind)))
            let coreUpdating = Date()
             
             
             
             
            let report = await ProviderUpdater.update(targets, in: .live(
                profile: profile, store: store, container: container, vpn: vpn, scripts: scripts,
                stillInUse: { !CollectionTake.movedOn(store.activeIdentityOrNil(), from: active) }))
            Self.logTakeStep("core", since: coreUpdating, "sets=\(targets.count) tunnel=\(tunnelIsRunning)")
            for name in targets {
                switch report.outcomes[name] {
                case .updated?:
                    took.insert(name)
                case .unchanged?:
                    took.insert(name)
                    coreUnchanged.insert(name)
                case .awaitingConnection?:
                     
                     
                     
                    took.insert(name)
                    coreAwaitingConnect.insert(name)
                case .failed(let reason)?, .heldByTunnel(let reason)?:
                    failures.append(Self.labelled(configurationName + " / " + name,
                        ClashCopy.string(for: reason.displayText, locale: locale), locale: locale))
                    missed.insert(name)
                case .notConfirmed(let text)?:
                    failures.append(Self.labelled(configurationName + " / " + name,
                        ClashCopy.string(for: text.displayText, locale: locale), locale: locale))
                    pendingNames.insert(name)
                case .notUpdatable?, .skipped?, nil:
                    break
                }
            }
             
             
            if CollectionTake.movedOn(store.activeIdentityOrNil(), from: active) {
                let asked = Set(targets)
                took.subtract(asked)
                missed.subtract(asked)
                pendingNames.subtract(asked)
                coreAwaitingConnect.removeAll()
                coreUnchanged.removeAll()
                switched = true
            }
             
            skippedNames.formUnion(running.byCore.subtracting(took).subtracting(missed).subtracting(pendingNames))
        } else {
            skippedNames.formUnion(running.byCore)
        }
         
         
        if switched || CollectionTake.movedOn(store.activeIdentityOrNil(), from: active),
           !skippedNames.isEmpty, !failures.contains(notApplied) {
            failures.append(notApplied)
        }
        for entry in entries {
            let names = index.providers(of: entry)
            guard !names.isEmpty else { continue }
            if !names.isDisjoint(with: missed) {
                take.notApplied.insert(entry.id)
            } else if names.isSubset(of: took) {
                take.applied.insert(entry.id)
            } else if !names.isDisjoint(with: pendingNames) {
                take.pending.insert(entry.id)
            } else if !names.isDisjoint(with: skippedNames) {
                take.skipped.insert(entry.id)
            }
        }
         
         
        take.unchanged = Set(entries.filter {
            let names = index.providers(of: $0)
            return !names.isEmpty && take.applied.contains($0.id) && names.isSubset(of: coreUnchanged)
        }.map(\.id))
        take.checkedOnConnect = Set(entries.filter {
            let names = index.providers(of: $0)
            return !names.isEmpty && take.applied.contains($0.id) && names.isSubset(of: coreAwaitingConnect)
        }.map(\.id))
        take.appliesOnConnect = CollectionTake.appliesOnConnect(
            awaitingConnect: (savedForNext ? appFetched : []).union(coreAwaitingConnect), applied: take.applied,
            carriedBy: entries, providers: index.providers(of:))
        take.failures = failures
        return take
    }

     
     
    private var batchTaskIsWhole = false
    private var batchRunID: UUID?
    private let downloader: HTTPFetching
    private(set) var storeReplacementObserver: NSObjectProtocol?
    private var selectionObserver: NSObjectProtocol?
    private var scheduledRefreshObserver: NSObjectProtocol?
    private var scriptLibraryObserver: NSObjectProtocol?
    private var modulesObserver: NSObjectProtocol?
    private var modulesReadinessObserver: NSObjectProtocol?
    private var republishedObserver: NSObjectProtocol?
    private var profileEditedObserver: NSObjectProtocol?
    private var providerContentObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
     
     
     
    var appIsInBackground: @MainActor () -> Bool = {
#if os(iOS)
        UIApplication.shared.applicationState == .background
#else
        false
#endif
    }
     
     
     
    private var revisionHandedToTunnel: ActiveConfigurationPointer?
     
     
     
    private static let batchItemLimit: TimeInterval = 45
    private var failedOperation: FailedOperation?
    private var automaticSelectionAttempts: Set<String> = []

    var isActivationInFlight: Bool { activationAppliesToTunnel != nil }

    private struct ActivationRequest {
        let profile: Profile
        let applyToTunnel: Bool
        let preferCachedSource: Bool
         
         
         
         
        let requestedWhileTunnelUp: Bool
         
         
        let runtimeCarriesChange: Bool
         
         
         
        var onlyIfActive: ActiveConfigurationPointer? = nil
         
        var inBackground = false
         
         
        var fetchesRuleSets = false
         
         
         
        var fetchesFresh = false
    }

     
     
    private var activationInFlight: ActivationRequest? {
        didSet { noteAwaitedActivation() }
    }

    private func noteAwaitedActivation() {
        isAwaitedActivationInFlight = activationInFlight.map { !$0.inBackground } == true
            || pendingActivation.map { !$0.inBackground } == true
    }

    private enum FailedOperation {
        case sync(String)
        case activation(String)
    }

    init(
        vpn: VPNController,
        container: URL? = ClashAppIdentifiers.appGroupContainer,
        credentials: CredentialStore = CredentialStore(),
        sourceWriter: ((String, Profile, URL) throws -> Void)? = nil,
         
         
         
        downloader: HTTPFetching = ResourceDownloader(),
        makeProfileID: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.vpn = vpn
        self.container = container
        self.runtimeDefaults = vpn.clientPreferences
        self.credentials = credentials
        self.downloader = downloader
        self.sourceWriter = sourceWriter ?? Self.writeSourceYAML
        self.makeProfileID = makeProfileID
         
         
         
        LeftoverFiles.sweepOnce(workingDirectory: container?.appendingPathComponent("working"))
         
         
         
         
        if let container {
            ModuleChangeTakers.shared.register(
                self, container: container,
                listening: { [weak self] in self?.modulesObserver != nil },
                inFront: { [weak self] in
                    guard let self else { return false }
                    return !self.appIsInBackground()
                },
                restage: { [weak self] in self?.restageForClientRuntimeSetting() },
                busy: { [weak self] in
                    guard let self else { return false }
                    return self.activationInFlight != nil || self.pendingActivation != nil
                },
                 
                 
                 
                reconnect: { [weak self] in await self?.reconnectForModules() })
        }
         
         
         
         
        widgetFactsSubscription = Publishers.CombineLatest($activeProfileID, $profiles)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.publishWidgetFacts()
            }
#if !os(macOS)
         
         
         
        vpn.publicationBarrier = { [weak self] in await self?.waitForPendingActivation() }
         
         
         
         
        vpn.libraryGoneHandler = { [weak self] record, stillWanted in
            guard let self else { return }
             
             
             
             
            guard stillWanted() else {
                await self.republishIfLibraryGone(record: record, stillWanted: stillWanted)
                return
            }
             
            if let last = self.libraryGoneAnsweredAt, Date().timeIntervalSince(last) < 60 {
                LibraryGoneRepublish.markAnswered(record, in: GlobalConfig.appGroupDefaults)
                return
            }
             
             
            if await self.republishIfLibraryGone(record: record, stillWanted: stillWanted) {
                self.libraryGoneAnsweredAt = Date()
            }
        }
#endif
    }

     
     
     
     
     
     
     
     
     
    func publishWidgetFacts() {
        let active = profiles.first { $0.id == activeProfileID }
         
         
         
         
        let mode = active.flatMap { self.cachedOutboundMode(for: $0) }.flatMap { ClashWidgetMode(rawValue: $0.rawValue) }
        let label = active?.label
         
         
         
         
        let storedGlobal = active.map { ClashTunnelOutboundMode.StoredGlobalChoice(
            selectedMap: $0.selectedMap, currentGroupName: $0.currentGroupName,
            globalPickedByReader: $0.globalPickedByReader ?? false) }
         
         
        widgetFactsPublication?.cancel()
        widgetFactsPublication = Task { [weak self] in
            guard let self else { return }
            let document = await self.widgetFactsDocument(for: active)
            guard !Task.isCancelled else { return }
            ClashWidgetFactsPublisher.publish(activeLabel: label, mode: mode, storedGlobal: storedGlobal, effectiveYAML: document)
        }
    }

    private var widgetFactsPublication: Task<Void, Never>?

     
     
     
     
     
     
    func widgetFactsDocument(for profile: Profile?) async -> String? {
        guard let profile else { return nil }
        if let effective = await loadEffectiveYAML(for: profile) { return effective }
        guard let workingDir, !hasLargeSource(profile) else { return nil }
        return await Task.detached(priority: .utility) {
            Self.sidecarYAML(for: profile, workingDir: workingDir)
        }.value
    }

    private var widgetFactsSubscription: AnyCancellable?

    deinit {
         
         
         
         
        if let storeReplacementObserver {
            NotificationCenter.default.removeObserver(storeReplacementObserver)
        }
        if let scheduledRefreshObserver {
            NotificationCenter.default.removeObserver(scheduledRefreshObserver)
        }
        if let selectionObserver {
            NotificationCenter.default.removeObserver(selectionObserver)
        }
        if let republishedObserver {
            NotificationCenter.default.removeObserver(republishedObserver)
        }
        if let profileEditedObserver {
            NotificationCenter.default.removeObserver(profileEditedObserver)
        }
        if let providerContentObserver {
            NotificationCenter.default.removeObserver(providerContentObserver)
        }
        if let scriptLibraryObserver {
            NotificationCenter.default.removeObserver(scriptLibraryObserver)
        }
        if let modulesObserver {
            NotificationCenter.default.removeObserver(modulesObserver)
        }
        if let modulesReadinessObserver {
            NotificationCenter.default.removeObserver(modulesReadinessObserver)
        }
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        if let container {
            ModuleChangeTakers.shared.deregister(ObjectIdentifier(self), container: container)
        }
    }

    var workingDir: URL? { container?.appendingPathComponent("working") }
     
    var appGroupContainer: URL? { container }
    var profileStore: ProfileStore? {
        workingDir.map { ProfileStore(fileURL: $0.appendingPathComponent("store/profiles.json")) }
    }

     
     
     
     
    private func observeStoreReplacement() {
        guard storeReplacementObserver == nil else { return }
        storeReplacementObserver = NotificationCenter.default.addObserver(
            forName: .clashProfileStoreReplaced,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hasAttemptedConfigurationRecovery = false
            self?.hasNotedLibraryFetchability = false
            self?.load()
        }
         
         
         
         
        selectionObserver = NotificationCenter.default.addObserver(
            forName: .clashProfileSelectionDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.load()
        }
         
         
         
         
         
        scheduledRefreshObserver = NotificationCenter.default.addObserver(
            forName: .clashConfigurationSourcesRefreshed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.load()
        }
         
         
         
         
         
        scriptLibraryObserver = NotificationCenter.default.addObserver(
            forName: ScriptLibrary.didChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
             
            guard ScriptLibrary.changesRuntime(note) else { return }
            self?.restageForClientRuntimeSetting()
        }
         
         
         
         
         
         
        modulesObserver = NotificationCenter.default.addObserver(
            forName: ModuleStore.didChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let container = self.container,
                      (note.object as? URL) == ModuleStore.normalized(container) else { return }
                 
                 
                 
                guard ModuleChangeTakers.shared.isElected(self, in: container) else { return }
                 
                 
                 
                 
                 
                 
                 
                if ModuleStore.isScheduledRefresh(note) { return }
                self.restageForClientRuntimeSetting()
            }
        }
         
         
         
         
         
         
         
         
        if let container, ModuleEngineReadinessSource.observesInThisProcess {
            ModuleEngineReadinessSource.shared(container).startObserving()
            modulesReadinessObserver = NotificationCenter.default.addObserver(
                forName: ModuleEngineReadinessSource.didChange,
                object: nil,
                queue: .main
            ) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let container = self.container,
                          (note.object as? URL)?.standardizedFileURL == container.standardizedFileURL,
                          ModuleChangeTakers.shared.isElected(self, in: container) else { return }
                    self.restageForClientRuntimeSetting()
                }
            }
        }
         
         
         
        republishedObserver = NotificationCenter.default.addObserver(
            forName: .clashActiveConfigurationRepublished,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                self?.takeRepublished(BackgroundRefresh.republished(from: note))
            }
        }
         
         
         
        profileEditedObserver = NotificationCenter.default.addObserver(
            forName: .clashProfileEditedOutsideTheModel,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let id = note.userInfo?["profileID"] as? String else { return }
                self.load()
                self.restageIfActive(id)
            }
        }
         
         
         
         
        providerContentObserver = NotificationCenter.default.addObserver(
            forName: .clashProviderContentChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, note.userInfo?["profileID"] != nil,
                      let own = self.workingDir?.standardizedFileURL.path,
                      note.userInfo?["workingDirectory"] as? String == own else { return }
                self.load()
            }
        }
#if os(iOS)
         
         
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                 
                 
                self.recomposeIfModulesMovedSincePublication()
                 
                if self.storageSweepOwed { self.sweepStorageInFront() }
                guard let pending = BackgroundRefresh.pendingHandover() else { return }
                 
                 
                 
                Task { @MainActor in
                    await self.vpn.ensureStatusLoaded()
                    self.takeRepublished(pending)
                }
            }
        }
#endif
    }

     
     
     
     
     
     
     
     
     
     
     
    func recomposeIfModulesMovedSincePublication() {
        guard let container, !appIsInBackground() else { return }
        let locations = ModuleLocations(container: container)
        let generation = staleCompositionCheckGeneration &+ 1
        staleCompositionCheckGeneration = generation
        staleCompositionCheck = Task { @MainActor [weak self] in
            let stale = await Task.detached(priority: .utility) { () -> ModuleStaleComposition? in
                let inUse = (try? ConfigResourceStore(containerURL: container))?.activeIdentityWithoutLock()
                return ModulePublicationRecord.staleComposition(locations: locations, inUse: inUse)
            }.value
            guard let self else { return }
            if let stale, !self.appIsInBackground() {
                ModuleChangeTakers.shared.recompose(stale, in: container) { [weak self] in
                    self?.restageForClientRuntimeSetting()
                }
            }
            if self.staleCompositionCheckGeneration == generation { self.staleCompositionCheck = nil }
        }
    }

     
    private var staleCompositionCheck: Task<Void, Never>?
    private var staleCompositionCheckGeneration = 0

     
    func waitForStaleCompositionCheck() async {
        while let task = staleCompositionCheck { await task.value }
    }

     
     
     
     
     
     
     
     
    func takeRepublished(_ published: ActiveConfigurationPointer?,
                         markers: UserDefaults = GlobalConfig.appGroupDefaults) {
        guard let container, let store = try? ConfigResourceStore(containerURL: container) else { return }
        let current = try? store.activePointer()
        guard let published = published ?? current else { return }
        let asked = StartupOutcomeRecord.read(from: container)?.requested
            .map { ActiveConfigurationPointer(profileID: $0.profileID, revision: $0.revision) }
        let target = pendingActivation?.profile.id ?? activationInFlight?.profile.id ?? activeProfileID
        let handsOver = RepublishedHandover.handsOver(
            published: published, current: current, tunnelRunning: tunnelIsRunning, selectionTarget: target,
            requestPending: pendingActivation != nil, handed: revisionHandedToTunnel, askedOfExtension: asked,
            activationInFlight: activationInFlight != nil)
        guard handsOver, let latest = profiles.first(where: { $0.id == published.profileID }) else {
             
             
             
             
            if current != published || published == revisionHandedToTunnel || published == asked
                || !profiles.contains(where: { $0.id == published.profileID }) {
                BackgroundRefresh.clearPendingHandover(published, in: markers)
            }
            return
        }
         
         
         
         
         
         
         
        if appIsInBackground(), published == current, activationInFlight == nil, pendingActivation == nil,
           busyProfileID == nil {
            handOverAsPublished(published, markers: markers)
            return
        }
        startActivation(latest, applyToTunnel: true, preferCachedSource: true,
                        because: ClashPerf.Reason.profileSync)
    }

     
     
     
     
    private func handOverAsPublished(_ published: ActiveConfigurationPointer, markers: UserDefaults) {
         
         
        revisionHandedToTunnel = published
        BackgroundRefresh.clearPendingHandover(published, in: markers)
        let vpn = self.vpn
        let previous = republishedHandover
        let generation = republishedHandoverGeneration &+ 1
        republishedHandoverGeneration = generation
        republishedHandover = Task { @MainActor [weak self] in
            await previous?.value
            let applied = await vpn.applyPublished(forProfile: published.profileID, startsWhenDown: false)
            guard let self else { return }
            self.lastTunnelApply = TunnelApplyRecord(sequence: self.lastTunnelApply.sequence &+ 1,
                                                     profileID: published.profileID, outcome: applied)
             
             
             
             
            if let applied, Self.handOverWentWrong(applied), self.activationInFlight == nil, self.pendingActivation == nil,
               let label = self.profiles.first(where: { $0.id == published.profileID })?.label {
                self.statusMessage = Self.statusLine(label: label, outcome: applied)
            }
            self.load()
            if self.republishedHandoverGeneration == generation { self.republishedHandover = nil }
        }
    }

     
     
    nonisolated static func handOverWentWrong(_ outcome: TunnelApplyOutcome) -> Bool {
        switch outcome {
        case .keptRunning, .failed: return true
        case .applied, .restarted, .savedForNext, .pending: return false
        }
    }

     
    private var libraryGoneAnsweredAt: Date?

     
     
     
     
     
     
     
    @discardableResult
    func republishIfLibraryGone(record: StartupOutcomeRecord? = nil,
                                markers: UserDefaults = GlobalConfig.appGroupDefaults,
                                stillWanted: @MainActor () -> Bool = { true }) async -> Bool {
        let record = record ?? StartupOutcomeRecord.read(from: container)
        guard LibraryGoneRepublish.owes(record, answered: markers.string(forKey: LibraryGoneRepublish.markerKey)),
              let record else { return false }
        markers.set(LibraryGoneRepublish.identity(of: record), forKey: LibraryGoneRepublish.markerKey)
        let profileID = record.requested?.profileID ?? activeProfileID
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return false }
         
         
         
         
         
        let lastWord = (try? ReaderTunnelIntent.last(in: vpn.intentDirectory())) ?? nil
        let intent = LibraryGoneRepublish.Intent.tracked(lastWord)
        switch LibraryGoneRepublish.action(for: record, tunnelIsRunning: tunnelIsRunning,
                                           readerStillWantsIt: stillWanted(), intent: intent) {
        case .applyToRunningTunnel:
             
             
            startActivation(profile, applyToTunnel: true, preferCachedSource: true,
                            because: ClashPerf.Reason.nodeLibraryGone)
        case .reconnect:
             
             
            _ = await connectFromHome(profile, forceReactivation: true, stillWanted: stillWanted,
                                      asReader: false, standingOn: lastWord)
        case .republishOnly:
             
             
            startActivation(profile, applyToTunnel: false, preferCachedSource: true,
                            because: ClashPerf.Reason.nodeLibraryGone)
        }
        return true
    }

     
    func applyProfileNow(_ profileID: String) {
        guard let profileStore,
              let latest = profileStore.load().first(where: { $0.id == profileID })
        else { return }
        let action = ProfileSettingsRestagePolicy.action(
            profileID: profileID,
            activeProfileID: activeProfileID,
            vpnStatus: vpn.status
        )
        guard action != .persistOnly else { return }
        startActivation(
            latest,
            applyToTunnel: action == .restageAndApply,
            preferCachedSource: true,
            because: ClashPerf.Reason.readerTappedApply
        )
    }

     
     
     
     
    private var replacementRecovery: Task<Result<Void, Error>, Never>?

     
     
     
     
    private func replacementRecoveryTask(library: ConfigurationLibraryStore, workingDir: URL) -> Task<Result<Void, Error>, Never> {
        if let running = replacementRecovery { return running }
        let task = Task { @MainActor [weak self] () -> Result<Void, Error> in
             
             
             
            let recovered = await Task.detached(priority: .userInitiated) { () -> Result<Set<String>, Error> in
                Result { try ConfigurationCenterPublicationBridge.recoverReplacements(
                    library: library, workingDir: workingDir, waitingForPublication: true) }
            }.value
            guard let self else { return recovered.map { _ in () } }
            self.replacementRecovery = nil
            guard case .success = recovered else { return recovered.map { _ in () } }
            self.load()
            return .success(())
        }
        replacementRecovery = task
        return task
    }

     
    func awaitReplacementRecovery() async {
        while let running = replacementRecovery { _ = await running.value }
    }

     
     
     
     
     
    private func unresolvedReplacementRecovery() async -> Error? {
        await awaitReplacementRecovery()
        guard let library = configurationLibraryStore, let workingDir,
              ConfigurationCenterPublicationBridge.hasReplacementRecovery(workingDir: workingDir) else { return nil }
        if case .failure(let error) = await replacementRecoveryTask(library: library, workingDir: workingDir).value {
            return error
        }
        return nil
    }

     
     
     
     
     
     
    private func restageOwedRebuild() {
        guard activationTask == nil, pendingActivation == nil, busyProfileID == nil,
              let workingDir, let active = activeProfileID,
              let token = RecoveryRebuilds.token(for: active, workingDir: workingDir),
              restagedForRecovery[active] != token else { return }
        restagedForRecovery[active] = token
        restageIfActive(active)
    }

    private var restagedForRecovery: [String: String] = [:]

    func load() {
         
         
         
         
         
        if let library = configurationLibraryStore, let workingDir,
           ConfigurationCenterPublicationBridge.hasReplacementRecovery(workingDir: workingDir) {
            guard replacementRecovery == nil else { return }
            let recovery = replacementRecoveryTask(library: library, workingDir: workingDir)
            Task { [weak self] in
                if case .failure(let failure) = await recovery.value {
                    self?.recordFailure(failure, context: .localImport, operation: nil, preservesLastKnownGood: true)
                     
                     
                    self?.hasLoadedProfiles = true
                }
            }
            return
        }
        if !hasAttemptedConfigurationRecovery {
            hasAttemptedConfigurationRecovery = true
             
             
             
             
             
            launchHousekeeping = Task { [weak self] in
                do {
                    try await self?.recoverConfigurationPublications()
                     
                     
                    await self?.reconcilePendingRenames()
                    try await self?.registerLegacyConfigurationSources()
                }
                catch { self?.recordFailure(error,context:.localImport,operation:nil,preservesLastKnownGood:true) }
            }
             
             
            Task { [weak self] in
                await self?.launchHousekeeping?.value
                await self?.linkWrittenSetsPastTheLimit()
                await self?.relinkSetsReadAsClassicalAtLaunch()
            }
        }
         
         
         
         
        forgetCachedSource()
        let loadBegan = DispatchTime.now().uptimeNanoseconds
        defer {
            ClashPerf.span(
                "profiles.load",
                milliseconds: Double(
                    DispatchTime.now().uptimeNanoseconds - loadBegan
                ) / 1_000_000,
                detail: "profiles=\(profiles.count)"
            )
        }
         
         
         
         
         
         
        derivedModeMemo = nil
        derivedModeGeneration &+= 1
        observeStoreReplacement()
        guard let profileStore else {
            hasLoadedProfiles = true
            return
        }
         
         
         
         
         
        if let workingDir {
            PlaintextSourceMigration.run(
                profileStore: profileStore,
                workingDir: workingDir,
                credentials: credentials
            )
        }
        if let container, !false {
            do {
                try LocalDefaultProfileProvisioner.provisionIfNeeded(
                    store: profileStore,
                    workingDirectory: container.appendingPathComponent("working")
                )
                try BundledProfileProvisioner.provisionExistingProfileIfNeeded(
                    container: container
                )
                 
                 
                 
                 
                try CorpusProfileSeeder.seedIfRequested(
                    store: profileStore,
                    workingDirectory: container.appendingPathComponent("working")
                )
                 
                 
                 
                if let documents = try? FileManager.default.url(
                    for: .documentDirectory, in: .userDomainMask,
                    appropriateFor: nil, create: false
                ) {
                    RuleProviderCompileProbe.runIfRequested(documents: documents)
                }
            } catch {
                recordFailure(error, context: .localImport, operation: nil,
                              preservesLastKnownGood: false)
            }
        }
         
         
         
        let loaded = profileStore.load().sorted {
            ($0.order, $0.id) < ($1.order, $1.id)
        }
         
        PublishedSourceLedger.retain(only: Set(loaded.map(\.id)))
        if let container {
             
             
             
            activeProfileID = (
                try? ConfigResourceStore(
                    containerURL: container
                ).activeIdentity()
            )?.profileID
        }
        let preferred = loaded.first {
            $0.id == activeProfileID
        } ?? loaded.first
        _ = FlClashRuntimeConfig.migrateIfNeeded(
            preferredProfile: preferred,
            legacyGlobalOverride: GlobalConfig.load(
                from: runtimeDefaults
            ),
            defaults: runtimeDefaults
        )
         
         
        _ = FlClashRuntimeConfig.promoteNamespacesIfNeeded(
            profiles: loaded,
            activeProfileID: activeProfileID,
            defaults: runtimeDefaults
        )
         
         
         
         
        let moving = profilesMovingAppLayerKeysOntoOwnLayer(loaded)
        func sanitizing(_ profile: Profile) -> Profile {
            FlClashRuntimeConfig.sanitizedProfile(
                moving.contains(profile.id) ? FlClashRuntimeConfig.movingAppLayerKeysOntoOwnLayer(profile) : profile
            )
        }
        let sanitized = loaded.map(sanitizing)
        if sanitized != loaded {
            do {
                 
                 
                 
                try profileStore.updateAll { $0 = $0.map(sanitizing) }
            } catch {
                recordFailure(
                    error,
                    context: .activation,
                    operation: nil,
                    preservesLastKnownGood: true
                )
            }
        }
         
         
        if profiles != sanitized { profiles = sanitized }
        hasLoadedProfiles = true
         
         
         
         
         
         
        let listed = Set(sanitized.map(\.id))
        if !hasNotedLibraryFetchability || listed != notedProfileIDs {
            hasNotedLibraryFetchability = true
            notedProfileIDs = listed
            noteLibraryFetchability((try? configurationLibraryStore?.snapshot()) ?? nil)
        }
        if let workingDir { RecoveryRebuilds.forget(allBut: listed, workingDir: workingDir) }
        restageOwedRebuild()
    }

     
     
     
     
     
     
     
     
     
    private func profilesMovingAppLayerKeysOntoOwnLayer(_ profiles: [Profile]) -> Set<String> {
        let keeps = FlClashRuntimeConfig.appLayerKeysAnOwnLayerKeeps
        let carrying = profiles.filter {
            OverridePatch(patchJSON: $0.override.patchJSON).topLevelKeys.contains(where: keeps.contains)
        }
        guard !carrying.isEmpty else { return [] }
        var own = Set<String>()
        var undecided: [Profile] = []
        for profile in carrying {
            if isScripted(profile) || !(profile.legacyRuntimePatchJSON ?? "").isEmpty {
                own.insert(profile.id)
            } else {
                undecided.append(profile)
            }
        }
        guard !undecided.isEmpty, let library = configurationLibraryStore,
              let snapshot = try? library.snapshot() else { return own }
        for profile in undecided {
            guard let recipe = snapshot.recipes.first(where: { $0.id == profile.id }) else {
                own.insert(profile.id)
                continue
            }
            if recipe.preservesOriginal == true { own.insert(profile.id) }
        }
        return own
    }

     

    var configurationLibraryStore: ConfigurationLibraryStore? {
        guard let workingDir else { return nil }
        let directory = workingDir.appendingPathComponent("configuration-library")
#if canImport(UIKit)
        return ConfigurationLibraryStore(directory:directory,beginAccess:ConfigStoreSuspensionShield.beginLibraryAccess)
#else
        return ConfigurationLibraryStore(directory:directory)
#endif
    }

    private var legacyRegistration: (id: UUID, task: Task<Void, Error>)?

     
     
     
     
     
     
    func settleLibraryHousekeeping() async {
        if let launch = launchHousekeeping { await launch.value }
        if let registration = legacyRegistration { _ = try? await registration.task.value }
    }
     
     
    private var launchHousekeeping: Task<Void, Never>?



     
     
     
     
     
    func registerLegacyConfigurationSources() async throws {
        if let registration = legacyRegistration {
            defer {
                if legacyRegistration?.id == registration.id { legacyRegistration = nil }
                restageOwedBuiltinUpgrade()
            }
            return try await registration.task.value
        }
        let registrationID = UUID()
        let task = Task { @MainActor in
             
             
             
             
            var waited = 0
            while changingConfigurationLibrary, waited < 100 {
                try await Task.sleep(nanoseconds: 50_000_000); waited += 1
            }
            guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
            guard let store = configurationLibraryStore, let workingDir else { throw ConfigurationLibraryError.unreadable }
            changingConfigurationLibrary = true
            defer { changingConfigurationLibrary = false }
            let installed = profiles
            var failures: [String] = []
            func register(_ prepare: @escaping @Sendable (ConfigurationLibrarySnapshot) throws
                -> (snapshot: ConfigurationLibrarySnapshot, payloads: [ConfigurationSourcePayload])?) async throws {
                try await Task.detached(priority: .utility) {
                    let current = try store.snapshot()
                    if let registration = try prepare(current) {
                        _ = try store.commit(registration.snapshot, payloads: registration.payloads,
                            expectedGeneration: current.generation)
                    }
                }.value
            }
            for profile in installed {
                try Task.checkCancellation()
                do {
                    try await register { current in
                        try ConfigurationLegacyRegistration.prepare(profile: profile, snapshot: current,
                            load: { try ConfigurationLegacyRegistration.payload(profile: profile, workingDir: workingDir) })
                    }
                } catch { failures.append(Self.failureLine(profile.label, error, locale: .current)) }
                do {
                    try await register { current in
                        try ConfigurationLegacyRegistration.prepareCustomNodes(profile: profile, snapshot: current,
                            load: { try ConfigurationLegacyRegistration.customNodePayload(profile: profile, workingDir: workingDir) })
                    }
                } catch { failures.append(Self.failureLine(profile.label, error, locale: .current)) }
            }
             
             
             
            do {
                try await register { current in ConfigurationBuiltins.retiringCommunitySchemes(in: current) }
            } catch { failures.append(error.localizedDescription) }
             
             
            do {
                try await register { current in ConfigurationLibraryStore.markingLegacyEditedCopiesPrivate(in: current) }
            } catch { failures.append(error.localizedDescription) }
             
             
             
            do {
                try await register { current in ConfigurationLibraryStore.markingSchemePageViewsPrivate(in: current) }
            } catch { failures.append(error.localizedDescription) }
             
             
             
             
            do { try await upgradeBuiltinSchemes() }
            catch { failures.append(error.localizedDescription) }


             
             
             
             
            do { try await recomposeForCurrentCompositionRevision() }
            catch { failures.append(error.localizedDescription) }
             
             
             
            do { try await moveConfigurationPagesOntoSchemes() }
            catch { failures.append(error.localizedDescription) }
             
             
            do { try await moveAppLayerCompatibilityIntoConfigurations() }
            catch { failures.append(error.localizedDescription) }
            if !failures.isEmpty { throw PipelineError.sourceUnavailable(failures.joined(separator: "\n")) }
             
             
            sweepStorageInFront()
        }
        legacyRegistration = (registrationID, task)
        defer {
            if legacyRegistration?.id == registrationID { legacyRegistration = nil }
             
             
             
             
            restageOwedBuiltinUpgrade()
        }
        try await task.value
    }

     
     
     
     
     
     
     
     
     
     
     
    func sweepStorageInFront() {
        guard let container else { return }
        guard !appIsInBackground() else {
            storageSweepOwed = true
            return
        }
        storageSweepOwed = false
        let running = StorageView.tunnelIsRunning(vpn.status)
        let library = configurationLibraryStore
        storageSweep = Task.detached(priority: .utility) {
             
             
            if let library { ConfigurationCenterPublicationBridge.collectLibraryGarbage(library) }
             
             
             
             
            _ = try? ConfigResourceStore(containerURL: container).adoptProviderPayloads()
            let maintenance = StorageMaintenance(containerURL: container, tunnelIsRunning: { running })
            _ = try? maintenance.reclaim([.configurations, .geodata])
             
             
             
             
        }
    }

     
     
    private(set) var storageSweepOwed = false
    private var storageSweep: Task<Void, Never>?

     
    func waitForStorageSweep() async {
        await storageSweep?.value
    }

     
     
     
     
     
     
     
     
     
     
     
    func recomposeForCurrentCompositionRevision() async throws {
        guard let library = configurationLibraryStore else { return }
        let current = try await Task.detached { try library.snapshot() }.value
        let prepared: PreparedConfigurationSourceUpdate?
        do {
            prepared = try await Task.detached(priority: .utility) {
                try library.prepareRecompositionForCurrentRevision(expectedGeneration: current.generation,
                    resolveInput: ConfigurationCenterSourceBridge.boundInput)
            }.value
        } catch ConfigurationLibraryError.busy, ConfigurationLibraryError.staleGeneration {
             
             
             
             
             
            return
        }
        guard let prepared else { return }
         
         
         
         
         
         
        try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
            compositions: prepared.compositions, generation: current.generation, restagesConfigurationInUse: false)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func linkWrittenSetsPastTheLimit() async {
        #if os(iOS)
        guard !Self.linkedWrittenSetsThisProcess, !appIsInBackground(), let library = configurationLibraryStore else { return }
        Self.linkedWrittenSetsThisProcess = true
        guard let toRead = try? await Task.detached(priority: .utility, operation: { try library.localRuleSetsToLink() }).value
        else { return }
        var judged = UserDefaults.standard.dictionary(forKey: Self.judgedWithoutLinkKey) as? [String: String] ?? [:]
        var read: [ConfigurationLocalRuleSet] = []
        for set in toRead where judged[set.id] != Self.fingerprint(set) {
            guard let content = try? await ConfigurationTowerRuleReader.ruleSet(set.input) else { continue }
            guard let link = content.link else { judged[set.id] = Self.fingerprint(set); continue }
            var found = set
            found.link = link
            read.append(found)
        }
        UserDefaults.standard.set(judged, forKey: Self.judgedWithoutLinkKey)
        guard !toRead.isEmpty else { return }
        ClashLogStore.shared.append(#"rule sets past the written-in limit: \#(toRead.count), links read: \#(read.count)"#, stream: .app)
        guard !read.isEmpty else { return }
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { return }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        do {
            let current = try await Task.detached { try library.snapshot() }.value
            guard let prepared = try await Task.detached(priority: .utility, operation: {
                try library.prepareLinkingWrittenSets(read, expectedGeneration: current.generation,
                    resolveInput: ConfigurationCenterSourceBridge.boundInput)
            }).value else { return }
            try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
                compositions: prepared.compositions, generation: current.generation)
        } catch {
            ClashLogStore.shared.append(#"rule sets past the written-in limit: not linked: \#(error.localizedDescription)"#, stream: .app)
        }
        #endif
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func relinkSetsReadAsClassicalAtLaunch() async {
        guard !Self.relinkedClassicalThisProcess, !appIsInBackground() else { return }
        Self.relinkedClassicalThisProcess = true
        let relinked = await relinkSetsReadAsClassical(judged: .standard)
        if relinked > 0 {
            ClashLogStore.shared.append(#"rule sets saved as classical rules and read again as domains or address ranges: \#(relinked)"#, stream: .app)
        }
    }

     
     
     
    @discardableResult
    func relinkSetsReadAsClassical(judged defaults: UserDefaults,
                                   read: @escaping (String) async throws -> ConfigurationRuleSetContent = {
                                       try await ConfigurationTowerRuleReader.ruleSet($0)
                                   }) async -> Int {
        guard let library = configurationLibraryStore,
              let found = try? await Task.detached(priority: .utility, operation: { () -> [(set: ConfigurationLocalRuleSet, behavior: String)] in
                  Self.setsReadAsClassicalThatAreNot(try library.snapshot().localRuleSets ?? [])
              }).value, !found.isEmpty else { return 0 }
        var judged = defaults.dictionary(forKey: Self.judgedAsClassicalKey) as? [String: String] ?? [:]
        var relinked = 0
        for (set, lines) in found where judged[set.id] != Self.fingerprint(set) {
            let content = try? await read(set.input)
            var saved = set
            if let content, let link = content.link, link.behavior != "classical" {
                saved.rules = content.rules
                saved.link = link
                saved.behavior = content.behavior
            } else if set.link == nil {
                 
                 
                 
                 
                 
                saved.behavior = lines
            } else if content == nil {
                continue
            } else {
                judged[set.id] = Self.fingerprint(set)
                continue
            }
            let outcome = saved.link.map { $0.behavior } ?? #"written in as \#(lines)"#
            do {
                 
                 
                 
                let generation = try await Task.detached { () -> UInt64? in
                    let now = try library.snapshot()
                    return now.localRuleSets?.first(where: { $0.id == set.id }) == set ? now.generation : nil
                }.value
                guard let generation else { continue }
                _ = try await saveConfigurationLocalRuleSet(saved, generation: generation)
                relinked += 1
            } catch {
                ClashLogStore.shared.append(#"rule set \#(set.id) read again as \#(outcome): not saved: \#(error.localizedDescription)"#, stream: .app)
            }
        }
        defaults.set(judged, forKey: Self.judgedAsClassicalKey)
        return relinked
    }

     
     
     
     
    nonisolated static func setsReadAsClassicalThatAreNot(_ sets: [ConfigurationLocalRuleSet])
        -> [(set: ConfigurationLocalRuleSet, behavior: String)] {
        sets.compactMap { set in
            guard !set.rules.isEmpty else { return nil }
            if let link = set.link {
                guard link.behavior == "classical", link.format != "mrs" else { return nil }
            } else {
                let input = set.input.trimmingCharacters(in: .whitespacesAndNewlines)
                guard set.behavior == nil, !input.contains("\n"),
                      input.hasPrefix("http://") || input.hasPrefix("https://") else { return nil }
            }
            guard let behavior = ClashRuleSetSniff.ruleSet(in: Data(set.rules.joined(separator: "\n").utf8))?.behavior,
                  behavior == "domain" || behavior == "ipcidr" else { return nil }
            return (set, behavior)
        }
    }

    nonisolated(unsafe) private static var relinkedClassicalThisProcess = false
    private static let judgedAsClassicalKey = "clash.rules.linkedAsClassicalJudged"

    #if os(iOS)
    nonisolated(unsafe) private static var linkedWrittenSetsThisProcess = false
    private static let judgedWithoutLinkKey = "clash.rules.writtenInJudgedWithoutLink"
    #endif
     
     
    private static func fingerprint(_ set: ConfigurationLocalRuleSet) -> String {
        [set.input, String(set.rules.count), set.rules.first ?? "", set.rules.last ?? ""].joined(separator: "\n")
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    func upgradeBuiltinSchemes() async throws {
        guard let library = configurationLibraryStore else { return }
        let current = try await Task.detached { try library.snapshot() }.value
        let prepared: PreparedConfigurationSourceUpdate?
        do {
            prepared = try await Task.detached(priority: .utility) {
                try library.prepareBuiltinSchemeUpgrade(expectedGeneration: current.generation,
                    resolveInput: ConfigurationCenterSourceBridge.boundInput)
            }.value
        } catch ConfigurationLibraryError.busy, ConfigurationLibraryError.staleGeneration {
             
            return
        }
        guard let prepared else { return }
        try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
            compositions: prepared.compositions, generation: current.generation, restagesConfigurationInUse: false)
        if let active = activeProfileID, prepared.compositions.keys.contains(active) {
            builtinUpgradeRestageOwed = active
        }
    }

     
     
    private var builtinUpgradeRestageOwed: String?

    private func restageOwedBuiltinUpgrade() {
        guard let owed = builtinUpgradeRestageOwed, activationTask == nil, pendingActivation == nil,
              busyProfileID == nil, legacyRegistration == nil else { return }
        builtinUpgradeRestageOwed = nil
        restageIfActive(owed)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func moveConfigurationPagesOntoSchemes() async throws {
        guard let library = configurationLibraryStore, let profileStore, let workingDir else { return }
        let defaults = runtimeDefaults
        let marker = FlClashRuntimeConfig.movedIntoConfigurationsMarkerKey
        let current = try await Task.detached { try library.snapshot() }.value
        let runtime = FlClashRuntimeConfig.load(from: defaults)
        let appLayerMoved = defaults.object(forKey: marker) != nil
         
         
         
         
         
        let needsPages = current.schemePageRevision ?? 0 < ConfigurationLibraryStore.currentSchemePageRevision
        if !needsPages { try clearOverridesThePagesCarry(in: current) }
        guard needsPages || !appLayerMoved else { return }
        let installed = profiles
        let globalScript = ScriptSettings.enabled()
        func scripted(_ profile: Profile) -> Bool {
            globalScript || profile.overwriteMode == .script || profile.postMergeScriptID != nil
        }
        let composed = Set(current.recipes.filter { $0.preservesOriginal != true }.map(\.id))
        var sources: [String: String] = [:]
         
         
        for profile in installed { sources[profile.id] = try? storedSourceYAML(for: profile, preferCachedSource: true) }
        let captured = sources
         
        let moving = FlClashRuntimeConfig.appliedMovedPatch(runtime: runtime)
         
         
         
         
         
         
         
         
        let takes: [String: String] = appLayerMoved ? [:] : Dictionary(uniqueKeysWithValues: installed.map { profile in
            (profile.id, moving.patch.patchJSON)
        })
         
         
         
         
         
        let own: [String: OverridePatch] = needsPages ? Dictionary(uniqueKeysWithValues: installed.compactMap { profile in
            guard composed.contains(profile.id), !scripted(profile), (profile.overwriteMode ?? .standard) == .standard else { return nil }
            let keys = Self.pageKeysOfOwnOverride(profile)
            return keys.topLevelKeys.isEmpty ? nil : (profile.id, keys)
        }) : [:]
         
         
         
        let compared = Set(installed.map(\.id).filter { id in
            !appLayerMoved || own[id] != nil
        })
        let before: [String: (applied: String, output: String)] = compared.isEmpty ? [:] : await Task.detached(priority: .utility) {
            var result: [String: (applied: String, output: String)] = [:]
            for profile in installed where compared.contains(profile.id) {
                let stages = captured[profile.id].flatMap {
                    try? ProfileRuntimeConfigBuilder.buildProductionStages(raw: $0, profile: profile, runtimeOverride: runtime, scripts: .silent)
                }
                result[profile.id] = (takes[profile.id] ?? "", stages?.beforeClientRuntimePolicy ?? "")
            }
            return result
        }.value
         
         
         
         
        var extras: [String: OrderedJSON] = [:]
        for profile in installed where composed.contains(profile.id) && !scripted(profile) {
            let app = OverridePatch(patchJSON: before[profile.id]?.applied ?? "")
            let mine = own[profile.id]
            guard !app.topLevelKeys.isEmpty || mine != nil else { continue }
            let page = try Self.runningPage(of: profile.id, in: current)
            var merged: [(key: String, value: OrderedJSON)] = []
            for key in (mine?.topLevelKeys ?? []) + app.topLevelKeys where !merged.contains(where: { $0.key == key }) {
                var node = page?.topLevelValue(key)
                if let value = mine?.topLevelNode(key) { node = Self.mergedAsTheCoreMerges(node, value) }
                if let value = app.topLevelNode(key) { node = Self.mergedAsTheCoreMerges(node, value) }
                if let node { merged.append((key, node)) }
            }
            if !merged.isEmpty { extras[profile.id] = .object(merged) }
        }
        let label = Self.ownSchemeLabel()
        let after = FlClashRuntimeConfig.withoutMovedKeys(runtime)
        var prepared: PreparedConfigurationSourceUpdate?
        if !needsPages { extras = [:] }
        for _ in 0..<(needsPages ? 2 : 0) {
            let pages = extras
            prepared = try await Task.detached(priority: .utility) {
                try library.prepareSchemePagesForCurrentRevision(expectedGeneration: current.generation,
                    extraPage: { pages[$0.id] }, label: label, resolveInput: ConfigurationCenterSourceBridge.boundInput)
            }.value
            guard let plan = prepared, !pages.isEmpty else { break }
            let replacements = try await Task.detached(priority: .utility) {
                try ConfigurationCenterSourceBridge.prepareReplacements(
                    compositions: plan.compositions.filter { pages[$0.key] != nil }, planned: plan.candidate,
                    payloads: plan.payloads, library: library, originals: installed, workingDir: workingDir)
            }.value
            let differing = await Task.detached(priority: .utility) { () -> [String] in
                replacements.compactMap { replacement in
                    let id = replacement.profile.id
                    var profile = replacement.profile
                    if let moved = own[id] {
                        profile.override.patchJSON = OverridePatch(patchJSON: profile.override.patchJSON)
                            .removingTopLevelKeys(Set(moved.topLevelKeys)).patchJSON
                    }
                    guard let old = before[id]?.output,
                          let new = try? ProfileRuntimeConfigBuilder.buildProductionStages(raw: replacement.yaml,
                              profile: profile, runtimeOverride: after, scripts: .silent).beforeClientRuntimePolicy,
                          Self.sameRuntimeDocument(old, new) else { return id }
                    return nil
                }
            }.value
            if differing.isEmpty { break }
            for id in differing { extras[id] = nil }
        }
        if let plan = prepared {
            try await saveConfigurationPlan(candidate: plan.candidate, payloads: plan.payloads,
                compositions: plan.compositions, generation: current.generation, restagesConfigurationInUse: false)
        }
         
         
         
         
         
         
        var latest = runtime
        if !appLayerMoved {


            latest = FlClashRuntimeConfig.load(from: defaults)
            guard FlClashRuntimeConfig.appliedMovedPatch(runtime: latest).patch.patchJSON == moving.patch.patchJSON,
                  latest.dnsOverridesProfiles == runtime.dnsOverridesProfiles else { return }
        }
         
         
         
         
        var legacy: [String: String] = [:]
        for profile in installed {
            guard let applied = before[profile.id]?.applied, !applied.isEmpty, extras[profile.id] == nil else { continue }
            legacy[profile.id] = applied
        }
         
        let taken: [String: Set<String>] = own.compactMapValues { keys in Set(keys.topLevelKeys) }
            .filter { extras[$0.key] != nil }
        if !legacy.isEmpty || !taken.isEmpty {
            let moved = legacy, gated = moving.dnsGated
            if try profileStore.updateAll({ current in
                for index in current.indices {
                    if let keys = taken[current[index].id] {
                        current[index].override.patchJSON = OverridePatch(patchJSON: current[index].override.patchJSON)
                            .removingTopLevelKeys(keys).patchJSON
                    }
                     
                     
                    if let applied = moved[current[index].id] {
                        let existing = OverridePatch(patchJSON: current[index].legacyRuntimePatchJSON ?? "")
                        current[index].legacyRuntimePatchJSON = OverridePatch(patchJSON: applied).overlaying(existing).patchJSON
                         
                         
                        if !existing.hasDNSOverride, OverridePatch(patchJSON: applied).hasDNSOverride {
                            current[index].legacyRuntimeDNSGated = gated ? true : nil
                        }
                    }
                }
            }) { load() }
        }
        if !appLayerMoved {
             
            if !moving.patch.topLevelKeys.isEmpty {
                defaults.set(true, forKey: FlClashRuntimeConfig.movedIntoConfigurationsNoticeKey)
            }
            FlClashRuntimeConfig.save(FlClashRuntimeConfig.withoutMovedKeys(latest), in: defaults)
            defaults.set(true, forKey: marker)
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func moveAppLayerCompatibilityIntoConfigurations() async throws {
        guard let library = configurationLibraryStore, let profileStore, let workingDir else { return }
        let defaults = runtimeDefaults
        let marker = FlClashRuntimeConfig.compatibilityMovedIntoConfigurationsMarkerKey
        guard defaults.object(forKey: marker) == nil else { return }
        let runtime = FlClashRuntimeConfig.load(from: defaults)
        let moving = FlClashRuntimeConfig.appliedCompatibilityPatch(runtime: runtime)
        guard !moving.topLevelKeys.isEmpty else {
            defaults.set(true, forKey: marker)
            return
        }
        let after = FlClashRuntimeConfig.withoutCompatibilityKeys(runtime)
        let installed = profiles
        var sources: [String: String] = [:]
         
         
        for profile in installed { sources[profile.id] = try? storedSourceYAML(for: profile, preferCachedSource: true) }
        let captured = sources
        let before: [String: String] = await Task.detached(priority: .utility) {
            var result: [String: String] = [:]
            for profile in installed {
                guard let raw = captured[profile.id],
                      let built = try? ProfileRuntimeConfigBuilder.buildProductionStages(
                          raw: raw, profile: profile, runtimeOverride: runtime, scripts: .silent).beforeClientRuntimePolicy else { continue }
                result[profile.id] = built
            }
            return result
        }.value
         
         
        var onPage: Set<String> = []
        for profile in installed where before[profile.id] != nil && !onPage.contains(profile.id) {
            let snapshot = try await Task.detached(priority: .utility) { try library.snapshot() }.value
            guard try Self.settingsPage(of: profile, in: snapshot, scripted: isScripted(profile)) != nil else { continue }
            let current = try Self.runningPage(of: profile.id, in: snapshot)
            var nodes: [String: OrderedJSON] = [:]
            for key in moving.topLevelKeys {
                guard let value = moving.topLevelNode(key) else { continue }
                nodes[key] = Self.mergedAsTheCoreMerges(current?.topLevelValue(key), value)
            }
            if nodes.allSatisfy({ current?.topLevelValue($0.key) == $0.value }) {
                onPage.insert(profile.id)
                continue
            }
            let edits = nodes
            let prepared: PreparedConfigurationSourceUpdate
            do {
                prepared = try await Task.detached(priority: .utility) {
                    try library.prepareSchemePageEdit(profileID: profile.id, expectedGeneration: snapshot.generation,
                                                      resolveInput: ConfigurationCenterSourceBridge.BoundInputs().resolve) { page in
                        for key in edits.keys.sorted() { page = page.setting(path: [key], to: edits[key]) }
                    }
                }.value
            } catch ConfigurationLibraryError.busy, ConfigurationLibraryError.staleGeneration {
                 
                 
                 
                 
                 
                 
                 
                 
                return
            }
            let replacements = try await Task.detached(priority: .utility) {
                try ConfigurationCenterSourceBridge.prepareReplacements(compositions: prepared.compositions,
                    planned: prepared.candidate, payloads: prepared.payloads, library: library,
                    originals: installed, workingDir: workingDir)
            }.value
            let unchanged = await Task.detached(priority: .utility) { () -> Bool in
                replacements.allSatisfy { replacement in
                    guard let old = before[replacement.profile.id] else { return true }
                    guard let new = try? ProfileRuntimeConfigBuilder.buildProductionStages(raw: replacement.yaml,
                              profile: replacement.profile, runtimeOverride: after, scripts: .silent).beforeClientRuntimePolicy else { return false }
                    return Self.sameRuntimeDocument(old, new)
                }
            }.value
            guard unchanged else { continue }
            try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
                                            compositions: prepared.compositions, generation: snapshot.generation,
                                            restagesConfigurationInUse: false)
            for replacement in replacements { onPage.insert(replacement.profile.id) }
        }
         
         
        let latest = FlClashRuntimeConfig.load(from: defaults)
        guard FlClashRuntimeConfig.appliedCompatibilityPatch(runtime: latest).patchJSON == moving.patchJSON else { return }
         
         
        let moved = moving.patchJSON, placed = onPage
        if try profileStore.updateAll({ current in
            for index in current.indices where !placed.contains(current[index].id) {
                let existing = OverridePatch(patchJSON: current[index].legacyRuntimePatchJSON ?? "")
                current[index].legacyRuntimePatchJSON = OverridePatch(patchJSON: moved).overlaying(existing).patchJSON
            }
        }) { load() }
         
        defaults.set(true, forKey: FlClashRuntimeConfig.movedIntoConfigurationsNoticeKey)
        FlClashRuntimeConfig.save(FlClashRuntimeConfig.withoutCompatibilityKeys(latest), in: defaults)
        defaults.set(true, forKey: marker)
    }

     
     
     
     
     
     
     
    private func clearOverridesThePagesCarry(in snapshot: ConfigurationLibrarySnapshot) throws {
        guard let profileStore else { return }
        let globalScript = ScriptSettings.enabled()
        var carried: [String: Set<String>] = [:]
        for profile in profiles where !globalScript && profile.overwriteMode != .script && profile.postMergeScriptID == nil
            && (profile.overwriteMode ?? .standard) == .standard {
            let own = Self.pageKeysOfOwnOverride(profile)
            guard !own.topLevelKeys.isEmpty, let page = try Self.runningPage(of: profile.id, in: snapshot) else { continue }
            let keys = own.topLevelKeys.filter { key in
                guard let value = own.topLevelNode(key), let paged = page.topLevelValue(key) else { return false }
                return paged.mergingAsTheCoreMerges(value) == paged
            }
            if !keys.isEmpty { carried[profile.id] = Set(keys) }
        }
        guard !carried.isEmpty else { return }
        if try profileStore.updateAll({ current in
            for index in current.indices {
                guard let keys = carried[current[index].id] else { continue }
                current[index].override.patchJSON = OverridePatch(patchJSON: current[index].override.patchJSON)
                    .removingTopLevelKeys(keys).patchJSON
            }
        }) { load() }
    }

     
     
     
     
    nonisolated static func pageKeysOfOwnOverride(_ profile: Profile) -> OverridePatch {
        OverridePatch(patchJSON: profile.override.patchJSON).profileOwnedPatch
            .removingTopLevelKeys(ConfigurationRuleDocument.keys.union(["proxies", "proxy-providers"]))
            .removingTopLevelKeys(OverridePatch.listenerKeys)
    }

     
    nonisolated static func runningPage(of id: String, in snapshot: ConfigurationLibrarySnapshot) throws -> OrderedJSON? {
        guard let recipe = snapshot.recipes.first(where: { $0.id == id }), recipe.preservesOriginal != true else { return nil }
        let scheme = snapshot.rules.first { $0.id == recipe.ruleSchemeID }
            ?? ConfigurationBuiltins.schemes.first { $0.id == recipe.ruleSchemeID }
        let running = try ConfigurationSchemePage.effective(of: recipe, scheme: scheme)
        return running.settings.removingTopLevel("dns").settingTopLevel("dns", to: running.dns)
    }

     
     
     
    nonisolated static func mergedAsTheCoreMerges(_ base: OrderedJSON?, _ patch: OrderedJSON) -> OrderedJSON {
        base.map { $0.mergingAsTheCoreMerges(patch) } ?? patch
    }

     
     
     
    nonisolated static func sameRuntimeDocument(_ a: String, _ b: String) -> Bool {
        guard let left = try? OrderedJSON.parse(ConfigTransforms.yamlToJSON(a)),
              let right = try? OrderedJSON.parse(ConfigTransforms.yamlToJSON(b)) else { return a == b }
        return left.canonicalSerialized(preservingOrderForKeys: OverridePatch.orderSensitivePolicyKeys)
            == right.canonicalSerialized(preservingOrderForKeys: OverridePatch.orderSensitivePolicyKeys)
    }

     
    func configurationLegacyNodeSources(in snapshot: ConfigurationLibrarySnapshot) async throws -> [String: ConfigurationSourcePayload] {
        var available: [String: ConfigurationSourcePayload] = [:]
        for profile in profiles where profile.id != LocalDefaultProfileProvisioner.profileID
            && !snapshot.sources.contains(where: { $0.id == "legacy-" + profile.id })
            && !snapshot.recipes.contains(where: { $0.id == profile.id }) {
            if let payload = try? await configurationSourceFromLegacy(profile.id), payload.record.suppliesNodes {
                available[profile.id] = payload
            }
            try Task.checkCancellation()
        }
        return available
    }

    func configurationSourceFromLegacy(_ id: String) async throws -> ConfigurationSourcePayload {
        guard let profile = profiles.first(where: { $0.id == id }), let workingDir else {
            throw PipelineError.sourceUnavailable("The original configuration is unavailable.")
        }
        return try await Task.detached(priority: .userInitiated) {
            try ConfigurationLegacyRegistration.payload(profile: profile, workingDir: workingDir)
        }.value
    }

     
     
     
     
     
    func fetchConfigurationSource(url: String, label: String, nodesOnly: Bool = false) async throws -> ConfigurationSourcePayload {
        try await fetchConfigurationSource(url: url, label: label, nodesOnly: nodesOnly, unreadBody: nil)
    }

     
     
     
     
    func fetchRuleLibrarySource(url: String, label: String) async throws -> ConfigurationSourcePayload {
         
         
        var url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = ConfigurationTowerRuleReader.normalizedURL(url)
        if raw != url {
            let held = try? await Task.detached(priority: .userInitiated) { [configurationLibraryStore, url] in
                try configurationLibraryStore?.snapshot().availableSources.contains { $0.origin == .subscription(url) }
            }.value
            if held != true { url = raw }
        }
        let body = UnreadBody()
        do {
            return try await fetchConfigurationSource(url: url, label: label, nodesOnly: false,
                                                      unreadBody: { body.data = $0 })
        } catch {
            guard let data = body.data, let found = await ConfigurationTowerRuleReader.ruleSet(in: data) else { throw error }
            throw ConfigurationLinkIsARuleSet(found: found, link: url, underlying: error)
        }
    }

    private final class UnreadBody: @unchecked Sendable { var data: Data? }

    private func fetchConfigurationSource(url: String, label: String, nodesOnly: Bool,
                                          unreadBody: ((Data) -> Void)?) async throws -> ConfigurationSourcePayload {
        let fetched = try await ConfigurationCenterSourceBridge.fetch(url: url, label: label, credentials: credentials,
                                                                      downloader: downloader, nodesOnly: nodesOnly,
                                                                      unreadBody: unreadBody)
        guard let library = configurationLibraryStore,
              let existing = try await Task.detached(priority: .userInitiated, operation: {
                  try library.snapshot().availableSources.first { $0.origin == .subscription(url) }
              }).value else { return fetched }
        return ConfigurationCenterSourceBridge.adopting(existing, fetched: fetched)
    }

     
     
     
     
    func quickAddSource(_ input: ProfileQuickAddInput, nodesOnly: Bool = false) async throws -> ConfigurationLibrarySnapshot {
        guard let library = configurationLibraryStore else {
            throw PipelineError.sourceUnavailable("The configuration store is unavailable.")
        }
        let payload: ConfigurationSourcePayload
        switch input {
        case .link(let url, _):
            payload = try await fetchConfigurationSource(url: url, label: "", nodesOnly: nodesOnly)
        case let .document(fileName, data, _):
            payload = try await Task.detached {
                 
                 
                if fileName == ProfileQuickAddInput.pastedDocumentName,
                   let node = try ConfigurationCenterSourceBridge.nodeMaterialPayload(
                       label: "", yaml: ProxyImportBridge.derivedSubscriptionYAML(from: data, nodesOnly: nodesOnly)) {
                    return node
                }
                return try ConfigurationCenterSourceBridge.payload(label: fileName, origin: .file(fileName), original: data,
                                                                   nodesOnly: nodesOnly)
            }.value
        case .nodes(let links):
             
             
             
            payload = try await Task.detached {
                let yaml = try ProxyImportBridge.derivedSubscription(from: Data(links.utf8)).yaml
                let names = ((ConfigTransforms.parsedRoot(forYAML: yaml)?.root["proxies"] as? [[String: Any]]) ?? [])
                    .compactMap { $0["name"] as? String }
                return try ConfigurationCenterSourceBridge.payload(
                    label: names.count == 1 ? names[0] : ConfigurationBuiltins.customNodesName,
                    origin: .customNodes, original: Data(yaml.utf8), yaml: yaml
                )
            }.value
        case .nodeShareLink, .nothing:
            throw ProfileInstallLinkError.unusableSubscription
        }
         
         
         
         
         
        guard payload.record.suppliesNodes,
              payload.record.nodeCount > 0 || payload.record.providerCount > 0 else {
            throw ConfigurationLibraryError.missingNodes
        }
        let generation = try await Task.detached { try library.snapshot().generation }.value
        return try await addConfigurationSource(payload, generation: generation)
    }

     
     
     
     
     
    func quickAddRules(_ input: ProfileQuickAddInput) async throws -> ConfigurationLibrarySnapshot {
        guard let library = configurationLibraryStore else {
            throw PipelineError.sourceUnavailable("The configuration store is unavailable.")
        }
        let payload: ConfigurationSourcePayload
        switch input {
        case .link(let url, _):
            do {
                payload = try await fetchRuleLibrarySource(url: url, label: "")
            } catch let set as ConfigurationLinkIsARuleSet {
                 
                 
                 
                guard let behavior = set.found.behavior else { throw set.underlying }
                let stem = ClashRuleSetSniff.linkStem(set.link)
                return try await addRuleSetSource(name: stem.isEmpty ? (URL(string: set.link)?.host ?? "") : stem,
                                                  behavior: behavior, format: set.found.format, link: set.link)
            }
        case let .document(fileName, data, _):
            if let found = await ConfigurationTowerRuleReader.ruleSet(in: data), let behavior = found.behavior {
                 
                 
                let pasted = fileName == ProfileQuickAddInput.pastedDocumentName
                return try await addRuleSetSource(name: pasted ? "" : (fileName as NSString).deletingPathExtension,
                                                  behavior: behavior, format: found.format,
                                                  fileData: data)
            }
            payload = try await Task.detached {
                try ConfigurationCenterSourceBridge.payload(label: fileName, origin: .file(fileName), original: data)
            }.value
        case .nodeShareLink, .nodes, .nothing:
            throw ProfileInstallLinkError.unusableSubscription
        }
        let current = try await Task.detached { try library.snapshot() }.value
        if let existing = current.availableSources.first(where: { $0.id == payload.record.id }) {
            return try await adoptRulesOfLibrarySource(payload, replacing: existing)
        }
        if payload.record.ruleCount > 0 {
            return try await addConfigurationRuleScheme(payload, generation: current.generation)
        }
        var value = payload
        value.record.suppliesNodes = false
        value.record.registersSuppliedRules = false
        let document = try OrderedJSON.parse(value.documentJSON)
        guard !ConfigurationCollection.read(sourceID: value.record.id, document: document, kind: .rules).isEmpty else {
            throw ConfigurationLibraryError.missingRules
        }
        return try await addConfigurationSource(value, generation: current.generation)
    }

     
     
     
     
    nonisolated static func ruleSetSourcePayload(name: String, behavior: String, format: String, link: String? = nil,
                                                 file: (name: String, data: Data)? = nil) throws -> ConfigurationSourcePayload {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !title.contains(",") else { throw ConfigurationLibraryError.emptyName }
        var definition = OrderedJSON.object([("type", .string(file == nil ? "http" : "file")), ("behavior", .string(behavior)),
                                             ("format", .string(format))])
        if let file { definition = definition.settingTopLevel("path", to: .string(file.name)) }
        else {
            guard let link, let url = URL(string: link), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil
            else { throw ConfigurationLibraryError.unreadable }
            definition = definition.settingTopLevel("url", to: .string(link)).settingTopLevel("interval", to: .scalar("86400"))
        }
        let document = OrderedJSON.object([("rule-providers", .object([(title, definition)]))])
        let serialized = document.serialized()
        try ConfigTransforms.validateSource(serialized)
        var record = ConfigurationSourceRecord(label: title, origin: .file(title + ".yaml"), suppliesNodes: false)
        record.registersSuppliedRules = false; record.ruleProviderCount = 1
        return ConfigurationSourcePayload(record: record, original: Data(serialized.utf8), documentJSON: serialized,
                                          resourceFiles: file.map { [$0.name: $0.data] })
    }

     
     
     
    private func addRuleSetSource(name: String, behavior: String, format: String, link: String? = nil,
                                  fileData: Data? = nil) async throws -> ConfigurationLibrarySnapshot {
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        let current = try await Task.detached { try library.snapshot() }.value
         
         
        if let link {
            let held = try await Task.detached(priority: .userInitiated) {
                current.availableSources.contains { record in
                    guard !record.suppliesNodes, record.ruleProviderCount == 1,
                          let payload = try? library.payload(ConfigurationSourceVersion(record)),
                          case .object(let providers)? = (try? OrderedJSON.parse(payload.documentJSON))?.topLevelValue("rule-providers")
                    else { return false }
                    return providers.contains { $0.value.topLevelValue("url") == .string(link) }
                }
            }.value
            if held { return current }
        }
        let taken = Set(current.availableSources.map(\.label))
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: " ")
         
        let language = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        let stem = base.isEmpty ? ClashCopy.string("Rule Set", locale: language) : base
        var title = stem
        var number = 2
        while taken.contains(title) { title = "\(stem) \(number)"; number += 1 }
        let found = ClashRuleSetSniff.Found(format: format, behavior: behavior)
         
         
        let named: (name: String, data: Data)? = fileData.map { (name: ClashRuleSetSniff.fileName("", found: found), data: $0) }
        let built = try await Task.detached(priority: .userInitiated) { [title] in
            try Self.ruleSetSourcePayload(name: title, behavior: behavior, format: format, link: link, file: named)
        }.value
        return try await addConfigurationSource(built, generation: current.generation)
    }

     
     
     
    private func refreshLibrarySource(_ fetched: ConfigurationSourcePayload,
                                      replacing existing: ConfigurationSourceRecord) async throws {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let current = try await Task.detached { try library.snapshot() }.value
        _ = try await applyFetchedSource(fetched, replacing: existing, in: current, library: library, replaceEditedRules: false)
    }

     
     
     
     
     
     
     
     
     
    private func adoptRulesOfLibrarySource(_ fetched: ConfigurationSourcePayload,
                                           replacing existing: ConfigurationSourceRecord) async throws -> ConfigurationLibrarySnapshot {
        guard fetched.record.hasRules else { throw ConfigurationLibraryError.missingRules }
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let current = try await Task.detached { try library.snapshot() }.value
         
         
         
        if let keeping = current.configurationKeepingRules(of: existing.id) {
            throw ConfigurationRulesKeptByConfiguration(configuration: keeping)
        }
        _ = try await applyFetchedSource(fetched, replacing: existing, in: current, library: library, replaceEditedRules: false)
        let refreshed = try await Task.detached { try library.snapshot() }.value
        return try await Task.detached(priority: .userInitiated) {
            try library.registerSuppliedRules(sourceID: existing.id, expectedGeneration: refreshed.generation)
        }.value
    }

    private var hasAttemptedConfigurationRecovery = false
    private var configurationRecovery: Task<Void, Error>?

    func recoverConfigurationPublications() async throws {
        if let configurationRecovery { return try await configurationRecovery.value }
        let task = Task { @MainActor in try await self.performConfigurationRecovery() }
        configurationRecovery = task
        defer { configurationRecovery = nil }
        try await task.value
    }

    private func performConfigurationRecovery() async throws {
        guard let library = configurationLibraryStore, let workingDir, let profileStore else { return }
        if ConfigurationCenterPublicationBridge.hasReplacementRecovery(workingDir: workingDir) || replacementRecovery != nil {
            try await replacementRecoveryTask(library: library, workingDir: workingDir).value.get()
        }
        let pending = try await Task.detached { try library.snapshot().pendingPublications ?? [] }.value
        for reference in pending {
            let profile = try await Task.detached(priority:.userInitiated) {
                let publication = try library.publication(reference)
                return try ConfigurationCenterPublicationBridge.stage(publication,library:library,workingDir:workingDir)
            }.value
             
            try profileStore.insertIfAbsent(profile)
            try await Task.detached { try library.acknowledgePublication(reference) }.value
        }
        try await Task.detached {
            try ConfigurationCenterPublicationBridge.reconcileDeletedProfiles(library: library, profileStore: profileStore)
        }.value
        if !pending.isEmpty { load() }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    func quickCreate(_ input: ProfileQuickAddInput, nodesOnly: Bool = false) async throws -> ProfileQuickAddOutcome {


         
         
         
         
        let created = try await quickCreateConfiguration(input, nodesOnly: nodesOnly)


         
         
         
         
         
         
         
        if !created.hadUserProfile, let profile = profiles.first(where: { $0.id == created.id }) {
            _ = await selectAndWait(profile)
        }
        if created.originalHadNoRules {
             
             
             
            statusMessage = .copy("This link asked to run as the original configuration, but its content has no rules of its own. Default Rules are used instead.")
        }
        return ProfileQuickAddOutcome(id: created.id, isFirstUserProfile: !created.hadUserProfile,
                                      runsAsOriginal: created.runsAsOriginal)
    }

     
    private struct QuickCreated {
        let id: String
        let runsAsOriginal: Bool
        let hadUserProfile: Bool
         
         
        let originalHadNoRules: Bool
    }

     
    private func quickCreateConfiguration(_ input: ProfileQuickAddInput, nodesOnly: Bool) async throws -> QuickCreated {
        guard let library = configurationLibraryStore else {
            throw PipelineError.sourceUnavailable("The configuration store is unavailable.")
        }
        let payload: ConfigurationSourcePayload
        var buildsOn: String?
        let rules: InstallLinkRuleScheme?
        switch input {
        case let .link(url, named):
            rules = named
            payload = try await fetchConfigurationSource(url: url, label: "", nodesOnly: nodesOnly)
             
             
            if let existing = try await Task.detached(priority: .userInitiated, operation: {
                try library.snapshot().availableSources.first { $0.id == payload.record.id }
            }).value {
                try await refreshLibrarySource(payload, replacing: existing)
                buildsOn = existing.id
            }
        case let .document(fileName, data, named):
            rules = named
            payload = try await Task.detached {
                try ConfigurationCenterSourceBridge.payload(label: fileName, origin: .file(fileName), original: data,
                                                            nodesOnly: nodesOnly)
            }.value
        case .nodeShareLink, .nodes, .nothing:
            throw ProfileInstallLinkError.unusableSubscription
        }


        let (suppliesOwnRouting, resolvesItsNodesItself) = await Task.detached(priority: .userInitiated) {
            payload.routing
        }.value
         
         
         
         
         
         
        let routed: Bool
        switch rules {
        case nil:
            routed = ConfigurationCreationDraft.runsAsWritten(payload, suppliesOwnRouting: suppliesOwnRouting,
                                                              resolvesItsNodesItself: resolvesItsNodesItself)
        case .original?:
            routed = suppliesOwnRouting
        case .defaultRules?, .lazyRules?:
            routed = false
        }
        let ruleID = rules == .lazyRules ? ConfigurationBuiltins.lazyRuleID : ConfigurationBuiltins.basicRuleID
        var draft = ConfigurationCreationDraft()
        if !routed, let buildsOn {
             
             
            draft.selectedSourceIDs = [buildsOn]
            draft.selectedRuleID = ruleID
            draft.connectAfterCreation = false
            draft.step = .rules
        } else if rules == nil {
             
             
            try draft.acceptNewImport(payload, suppliesOwnRouting: suppliesOwnRouting,
                                      resolvesItsNodesItself: resolvesItsNodesItself)
        } else {
             
             
             
             
            draft.selectedRuleID = ruleID
            try draft.acceptInitialNodeImport(payload)
            if routed { draft.useOriginal(payload) }
        }
         
         
        let hadUserProfile = profiles.contains { $0.id != LocalDefaultProfileProvisioner.profileID }
        let generation = try await Task.detached { try library.snapshot().generation }.value
        let id = UUID().uuidString.lowercased()
        _ = try await createConfiguration(draft, generation: generation, id: id)
        return QuickCreated(id: id, runsAsOriginal: draft.originalSourceID != nil, hadUserProfile: hadUserProfile,
                            originalHadNoRules: rules == .original && !routed)
    }

    func createConfiguration(_ draft: ConfigurationCreationDraft, generation: UInt64,
                             id: String) async throws -> (id: String, connected: Bool?) {
         
         
         
        guard id.count == 36, UUID(uuidString: id) != nil, id == id.lowercased() else {
            throw ConfigResourceStoreError.invalidProfileID
        }
        guard let library = configurationLibraryStore, let workingDir, container != nil, let profileStore else {
            throw PipelineError.sourceUnavailable("The configuration store is unavailable.")
        }
        await settleLibraryHousekeeping()
        let current = try await Task.detached { try library.snapshot() }.value
        if current.recipes.contains(where: { $0.id == id }) {
             
             
            try await recoverConfigurationPublications()
            guard profileStore.load().contains(where: { $0.id == id }) else {
                throw PipelineError.sourceUnavailable("The configuration was saved but could not be opened. Try again.")
            }
             
            return (id, nil)
        }
        let prepared = try await Task.detached(priority:.userInitiated) {
            try library.prepare(draft,profileID:id,expectedGeneration:generation,
                resolveInput:ConfigurationCenterSourceBridge.boundInput)
        }.value


        let label = ProfileLabelPolicy.deduplicate(prepared.recipe.label,existing:profileStore.load().map(\.label))
         
         
         
         
         
         
        let profileSource = Self.profileSource(for: prepared)
        let profile = Profile(id:id,label:label,labelIsUserAssigned:true,source:profileSource,autoUpdate:false,
            updateIntervalHours:12,subscriptionInfo:nil,selectedMap:[:],override:OverrideSpec(),
            activeRevision:nil,order:(profiles.map(\.order).min() ?? 0) - 1,lastUpdatedAt:nil)
         
         
         
         
        let yaml = try await Task.detached(priority:.userInitiated) {
             
             
            let yaml = try ConfigurationCenterSourceBridge.publicationYAML(prepared.composition, recipe: prepared.recipe) {
                reference in
                try prepared.payloads.first(where: { ConfigurationSourceVersion($0.record) == reference })
                    ?? library.payload(reference)
            }
            try ConfigTransforms.validateSource(yaml)
            AppCore.returnFreeMemoryNow(after: yaml)
            return yaml
        }.value


        try Task.checkCancellation()
        var candidate = prepared.candidate
        if let index = candidate.recipes.firstIndex(where: { $0.id == id }) { candidate.recipes[index].label = label }
        let publication = ConfigurationPublicationPayload(reference:.init(profileID:id),
            profileMetadata:try JSONEncoder().encode(profile),yaml:yaml)
        _ = try await Task.detached(priority:.userInitiated) {
            try library.commitPublication(candidate,payloads:prepared.payloads,publication:publication,expectedGeneration:generation)
        }.value


         
         
        let staged = try await Task.detached(priority:.userInitiated) {
            try ConfigurationCenterPublicationBridge.stage(publication,library:library,workingDir:workingDir)
        }.value


        try profileStore.insertIfAbsent(staged)
        try await Task.detached { try library.acknowledgePublication(publication.reference) }.value
         
         
         
        noteLibraryFetchability(candidate)
        downloadNeverFetchedNodeCollections()
        load()
         
        return (id,nil)
    }

     
     
     
     
     
     
    func downloadNeverFetchedNodeCollections() {
        guard let library = configurationLibraryStore else { return }
        let downloader = downloader, credentials = credentials
        Task.detached(priority: .utility) { [weak self] in
             
            let inUse = self?.providerCatalogInUse()
            let fetched = await ConfigurationCollectionContentBridge.fetchNeverFetchedNodeCollections(
                library, inUse: inUse, downloader: downloader, credentials: credentials)
            if fetched > 0 { ProviderFirstLoadRetry.kick(trigger: .activation) }
        }
    }

    var changingConfigurationLibrary = false
     
     
     
     
     
     
    var detachingLinkOriginals: Set<String> = []

     
     
     
     
    func editConfiguration(_ draft: ConfigurationCreationDraft, id: String, generation: UInt64,
                           renames: Bool = false) async throws {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        guard let original = profiles.first(where: { $0.id == id }) else { throw ConfigurationLibraryError.missingDependency(id) }
        let prepared = try await Task.detached(priority: .userInitiated) {
            if try library.snapshot().recipes.contains(where: { $0.id == id }) {
                return try library.prepareEditing(draft, profileID: id, expectedGeneration: generation,
                    resolveInput: ConfigurationCenterSourceBridge.boundInput)
            }
            return try library.prepare(draft, profileID: id, expectedGeneration: generation,
                resolveInput: ConfigurationCenterSourceBridge.boundInput)
        }.value
        var candidate = prepared.candidate
        if draft.newSources.contains(where: { $0.record.id == "legacy-" + id }),
           let index = candidate.recipes.firstIndex(where: { $0.id == id }) {
            candidate.recipes[index].followsUpdates = original.autoUpdate
        }
        try await saveConfigurationPlan(candidate: candidate, payloads: prepared.payloads,
            compositions: [id: prepared.composition], generation: generation, rename: renames ? id : nil)
         
         
         
        if !draft.newSources.isEmpty { downloadNeverFetchedNodeCollections() }
    }

    func editConfigurationAdvancedSettings(_ id: String, json: String, generation: UInt64) async throws {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary, let library = configurationLibraryStore else { throw ConfigurationLibraryError.busy }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let prepared = try await Task.detached(priority: .userInitiated) {
            try library.prepareAdvancedSettingsEditing(id, settingsJSON: json, expectedGeneration: generation, includingDNS: true,
                resolveInput: ConfigurationCenterSourceBridge.boundInput)
        }.value
        try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
            compositions: prepared.compositions, generation: generation)
    }

     
     
    func setConfigurationSourceUpdates(_ id: String, enabled: Bool, link: String? = nil) async throws {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
         
         
         
         
        if enabled {
             
             
            for attempt in 1...3 {
                let current = try await Task.detached(priority: .userInitiated) { try library.snapshot() }.value
                let state = current.updateFollowing(ofRecipe: id)
                 
                 
                if state == .copyWithoutOrigin, link == nil { throw ConfigurationLibraryError.missingDependency("link") }
                guard state == .ownCopy || state == .customizedRules || state == .copyWithoutOrigin else { break }
                do {
                    let prepared = try await Task.detached(priority: .userInitiated) {
                        try library.prepareRejoiningSources(id, link: link, expectedGeneration: current.generation,
                                                            resolveInput: ConfigurationCenterSourceBridge.BoundInputs().resolve)
                    }.value
                    try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
                                                    compositions: [id: prepared.composition], generation: current.generation)
                    return
                } catch ConfigurationLibraryError.staleGeneration where attempt < 3 {
                    continue
                }
            }
        }
        _ = try await Task.detached(priority: .userInitiated) {
            var candidate = try library.snapshot()
            guard candidate.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
            guard let index = candidate.recipes.firstIndex(where: { $0.id == id }) else {
                throw ConfigurationLibraryError.missingDependency(id)
            }
            candidate.recipes[index].followsUpdates = enabled
            return try library.commit(candidate, payloads: [], expectedGeneration: candidate.generation)
        }.value
        load()
    }

     
     
     
     
    static func profileSource(for prepared: PreparedConfigurationCreation) -> Profile.Source {
        guard prepared.recipe.sources.count == 1,
              let reference = prepared.recipe.sources.first,
              let record = prepared.candidate.sources.first(where: { $0.id == reference.id }),
              case let .subscription(link) = record.origin,
              !link.isEmpty else { return .clipboard }
        return .url(link)
    }

    func setUsesOriginalConfiguration(_ id: String, enabled: Bool) async throws {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
         
         
         
         
         
         
        let existing = try await Task.detached { try library.snapshot() }.value
        if !existing.recipes.contains(where: { $0.id == id }) {
            guard !enabled else { return }
            try await composeLegacyConfiguration(id)
            return
        }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let generation = existing.generation
        let prepared = try await Task.detached(priority: .userInitiated) {
            let value = try library.prepareOriginalUse(id, uses: enabled, expectedGeneration: generation,
                resolveInput: ConfigurationCenterSourceBridge.boundInput)
            for payload in value.payloads { try ConfigTransforms.validateSource(payload.documentJSON) }
            return value
        }.value
        try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
            compositions: [id: prepared.composition], generation: generation)
    }

     
     
    private func noteLibraryFetchability(_ snapshot: ConfigurationLibrarySnapshot?) {
         
         
         
         
         
         
        guard let snapshot else { libraryHasFetchableSource = false; return }
        let listed = Set(profiles.map(\.id))
        libraryHasFetchableSource = snapshot.recipes.contains {
            listed.contains($0.id) && !Self.fetchableSources(of: $0, in: snapshot).isEmpty
        }
    }

     
     
     
     
     
     
    private func composeLegacyConfiguration(_ id: String) async throws {
        guard let profile = profiles.first(where: { $0.id == id }),
              let library = configurationLibraryStore else {
            throw ConfigurationLibraryError.missingDependency(id)
        }
         
         
         
         
         
         
        try await registerLegacyConfigurationSources()
        try await recoverConfigurationPublications()
        let snapshot = try await Task.detached { try library.snapshot() }.value
        let source = try await configurationSourceFromLegacy(id)
         
         
         
         
         
         
        var draft = ConfigurationCreationDraft()
        draft.add(source, rule: nil)
        draft.selectedRuleID = ConfigurationBuiltins.basicRuleID
        draft.label = profile.label
        draft.dnsMode = .system
        draft.connectAfterCreation = false
        try await editConfiguration(draft, id: id, generation: snapshot.generation)
    }

     
     
    func saveConfigurationRuleCustomization(_ draft: ConfigurationRuleDraft, profileID: String? = nil,
                                            generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary, let store = configurationLibraryStore else { throw ConfigurationLibraryError.busy }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let prepared = try await Task.detached {
            let value = try store.prepareRuleCustomization(draft, profileID: profileID, expectedGeneration: generation,
                resolveInput: ConfigurationCenterSourceBridge.boundInput)
            for payload in value.payloads { try ConfigTransforms.validateSource(payload.documentJSON) }
            return value
        }.value
        try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
            compositions: prepared.compositions, generation: generation)
        return try await Task.detached { try store.snapshot() }.value
    }

     
     
     
     
    func saveConfigurationLocalRuleSet(_ value: ConfigurationLocalRuleSet?, deleting id: String? = nil, generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary, let store = configurationLibraryStore else { throw ConfigurationLibraryError.busy }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let prepared = try await Task.detached {
            let prepared = try store.prepareLocalRuleSet(value, deleting: id, expectedGeneration: generation,
                                                         resolveInput: ConfigurationCenterSourceBridge.boundInput)
            for payload in prepared.payloads { try ConfigTransforms.validateSource(payload.documentJSON) }
            return prepared
        }.value
        try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
            compositions: prepared.compositions, generation: prepared.candidate.generation)
        return try await Task.detached { try store.snapshot() }.value
    }

    func createConfigurationRuleScheme(_ draft: ConfigurationNewRuleDraft, generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        return try await Task.detached(priority: .userInitiated) {
            try library.createRuleScheme(label: draft.label, templateID: draft.templateID, expectedGeneration: generation)
        }.value
    }

    func saveConfigurationRuleDraft(_ draft: ConfigurationRuleDraft, generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let prepared = try await Task.detached(priority: .userInitiated) {
            let plan = try library.prepareRuleEditing(draft, expectedGeneration: generation,
                resolveInput: ConfigurationCenterSourceBridge.boundInput)
            for payload in plan.payloads { try ConfigTransforms.validateSource(payload.documentJSON) }
            return plan
        }.value
        try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
            compositions: prepared.compositions, generation: generation)
        return try await Task.detached { try library.snapshot() }.value
    }

    func addConfigurationRuleScheme(_ source: ConfigurationSourcePayload, generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        let current = try await Task.detached { try library.snapshot() }.value
        if let existing = current.availableSources.first(where: { $0.id == source.record.id }) {
             
             
             
             
             
            guard current.generation == generation else { throw ConfigurationLibraryError.staleGeneration }
            return try await adoptRulesOfLibrarySource(source, replacing: existing)
        }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let (added, refusal) = try await Task.detached(priority: .userInitiated) { () -> (ConfigurationLibrarySnapshot, String?) in
            var refusal: String?
            let added = try library.addRuleScheme(source, expectedGeneration: generation) { refusal = $0 }
            return (added, refusal)
        }.value
         
        if let refusal { ConfigurationSourceRefusals.record(refusal, sourceID: source.record.id, in: runtimeDefaults) }
        return added
    }

    func copyConfigurationRuleScheme(_ id: String, label: String, generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        return try await Task.detached(priority: .userInitiated) {
            try library.copyRuleScheme(id, label: label, expectedGeneration: generation)
        }.value
    }

     
     
     
     
    func copyConfigurationRuleScheme(draft: ConfigurationRuleDraft, label: String, generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        return try await Task.detached(priority: .userInitiated) {
            try library.copyRuleScheme(draft, label: label, expectedGeneration: generation)
        }.value
    }

    func deleteConfigurationRuleScheme(_ id: String, generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        try await deleteConfigurationRuleSchemeRestorably(id, generation: generation).snapshot
    }

     
     
    func deleteConfigurationRuleSchemeRestorably(_ id: String, generation: UInt64) async throws
        -> (snapshot: ConfigurationLibrarySnapshot, removal: ConfigurationLibraryRemoval) {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let (prepared, removal) = try await Task.detached(priority: .userInitiated) {
            let before = try library.snapshot()
            let prepared = try library.prepareRuleRemoval(id, expectedGeneration: generation,
                resolveInput: ConfigurationCenterSourceBridge.boundInput)
            return (prepared, try library.removal(from: before, to: prepared.candidate))
        }.value
        try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
            compositions: prepared.compositions, generation: generation)
        return (try await Task.detached { try library.snapshot() }.value, removal)
    }

     
     
     
     
     
     
     
     
    func restoreConfigurationLibraryRemoval(_ removal: ConfigurationLibraryRemoval,
                                            expectedGeneration: UInt64) async throws -> ConfigurationLibrarySnapshot {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
         
         
         
        var attempt = 0
        while true {
            let prepared = try await Task.detached(priority: .userInitiated) {
                try library.prepareRestore(removal, resolveInput: ConfigurationCenterSourceBridge.boundInput)
            }.value
            do {
                try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
                    compositions: prepared.compositions, generation: prepared.candidate.generation)
                return try await Task.detached { try library.snapshot() }.value
            } catch ConfigurationLibraryError.staleGeneration where attempt < 3 {
                attempt += 1
            }
        }
    }

    func addConfigurationSource(_ source: ConfigurationSourcePayload, generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let current = try await Task.detached { try library.snapshot() }.value
        let result: ConfigurationLibrarySnapshot
        if let existing = current.availableSources.first(where: { $0.id == source.record.id }) {
             
             
            guard current.generation == generation else { throw ConfigurationLibraryError.staleGeneration }
            _ = try await applyFetchedSource(source, replacing: existing, in: current, library: library, replaceEditedRules: false)
            result = try await Task.detached { try library.snapshot() }.value
        } else {
            result = try await Task.detached(priority: .userInitiated) {
                try library.addSource(source, expectedGeneration: generation)
            }.value
        }
         
         
        noteLibraryFetchability(result)
        downloadNeverFetchedNodeCollections()
        return result
    }

    func renameConfigurationSource(_ id: String, label: String, generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let result = try await Task.detached(priority: .userInitiated) {
            try library.renameSource(id, label: label, expectedGeneration: generation)
        }.value
        noteLibraryFetchability(result)
        return result
    }

    func saveConfigurationSourceSettings(_ id: String, draft: ConfigurationSourceSettingsDraft,
                                         label: String? = nil, generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let result = try await Task.detached {
            try library.updateSourceSettings(id, draft: draft, label: label, expectedGeneration: generation)
        }.value
        BackgroundRefresh.schedule(earliest: BackgroundRefresh.nextEligibility())
        noteLibraryFetchability(result)
        return result
    }

     
     
     
     
     
     
     
    func renameConfigurationSource(_ id: String, label: String) async throws -> ConfigurationLibrarySnapshot {
        try await writeFieldsOnLatestLibrary { library, generation in
            try library.renameSource(id, label: label, expectedGeneration: generation)
        }
    }

    func saveConfigurationSourceSettings(_ id: String, draft: ConfigurationSourceSettingsDraft,
                                         label: String?) async throws -> ConfigurationLibrarySnapshot {
        let result = try await writeFieldsOnLatestLibrary { library, generation in
            try library.updateSourceSettings(id, draft: draft, label: label, expectedGeneration: generation)
        }
        BackgroundRefresh.schedule(earliest: BackgroundRefresh.nextEligibility())
        return result
    }

     
     
    func renameConfigurationRuleScheme(_ id: String, label: String) async throws -> ConfigurationLibrarySnapshot {
        try await writeFieldsOnLatestLibrary { library, generation in
            try library.renameRuleScheme(id, label: label, expectedGeneration: generation)
        }
    }

     
     
     
     
    private func writeFieldsOnLatestLibrary(
        _ write: @escaping @Sendable (ConfigurationLibraryStore, UInt64) throws -> ConfigurationLibrarySnapshot
    ) async throws -> ConfigurationLibrarySnapshot {
        await settleLibraryHousekeeping()
        await waitForNodeLibraryUpdate()
        var waited = 0
        while changingConfigurationLibrary, waited < 100 {
            try await Task.sleep(nanoseconds: 50_000_000); waited += 1
        }
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        var attempt = 0
        while true {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try write(library, try library.snapshot().generation)
                }.value
                noteLibraryFetchability(result)
                return result
            } catch ConfigurationLibraryError.staleGeneration where attempt < 3 {
                attempt += 1
            }
        }
    }

    func deleteConfigurationSource(_ id: String, generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        try await deleteConfigurationSourceRestorably(id, generation: generation).snapshot
    }

     
    func deleteConfigurationSourceRestorably(_ id: String, generation: UInt64) async throws
        -> (snapshot: ConfigurationLibrarySnapshot, removal: ConfigurationLibraryRemoval) {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let (prepared, removal) = try await Task.detached(priority: .userInitiated) {
            let before = try library.snapshot()
            let prepared = try library.prepareSourceRemoval(id, expectedGeneration: generation,
                resolveInput: ConfigurationCenterSourceBridge.boundInput)
            return (prepared, try library.removal(from: before, to: prepared.candidate))
        }.value
        try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
            compositions: prepared.compositions, generation: generation)
        return (try await Task.detached { try library.snapshot() }.value, removal)
    }

    func saveConfigurationChain(_ version: ConfigurationSourceVersion, replacement: ConfigurationSourcePayload) async throws -> ConfigurationLibrarySnapshot {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let snapshot = try await Task.detached { try library.snapshot() }.value
        let plan = try await Task.detached(priority: .userInitiated) {
            guard let record = snapshot.sources.first(where: { $0.id == version.id }), record.nodeChain != nil,
                  ConfigurationSourceVersion(record) == version, replacement.record.id == version.id else {
                throw ConfigurationLibraryError.staleGeneration
            }
            try ConfigTransforms.validateSource(ConfigTransforms.jsonToYAML(replacement.documentJSON))
            return try library.prepareSourceUpdate(replacement, expectedGeneration: snapshot.generation,
                updatingPinnedConsumers: true, resolveInput: ConfigurationCenterSourceBridge.boundInput)
        }.value
        try await saveConfigurationPlan(candidate: plan.candidate, payloads: plan.payloads,
            compositions: plan.compositions, generation: snapshot.generation)
        return try await Task.detached { try library.snapshot() }.value
    }

     
    func saveConfigurationNodeSource(_ version: ConfigurationSourceVersion, yaml: String) async throws -> ConfigurationLibrarySnapshot {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let snapshot = try await Task.detached { try library.snapshot() }.value
        let plan = try await Task.detached(priority: .userInitiated) {
            guard var record = snapshot.sources.first(where: { $0.id == version.id }),
                  record.suppliesNodes, record.nodeChain == nil, ConfigurationSourceVersion(record) == version else {
                throw ConfigurationLibraryError.staleGeneration
            }
            let edited = try OrderedJSON.parse(ConfigTransforms.yamlToJSON(yaml))
            let keys: Set<String> = ["proxies", "proxy-providers"]
            guard case .object(let entries) = edited,
                  entries.allSatisfy({ keys.contains($0.key) }) else {
                throw NSError(domain: "ConfigurationNodeEditor", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: ClashCopy.string("Only nodes and proxy providers belong here. Edit rules in Rule Library.", locale: .current)])
            }
            try ConfigTransforms.validateSource(yaml)
            let previous = try library.payload(version)
            var document = try OrderedJSON.parse(previous.documentJSON)
            for key in keys {
                if let value = edited.topLevelValue(key) { document = document.settingTopLevel(key, to: value) }
                else { document = document.removingTopLevel(key) }
            }
            if case .array(let nodes) = edited.topLevelValue("proxies") { record.nodeCount = nodes.count }
            else { record.nodeCount = 0 }
            if case .object(let providers) = edited.topLevelValue("proxy-providers") { record.providerCount = providers.count }
            else { record.providerCount = 0 }
            record.version = UUID().uuidString; record.updatedAt = Date()
            let replacement = ConfigurationSourcePayload(record: record, original: previous.original,
                documentJSON: document.serialized(), resourceFiles: previous.resourceFiles,
                ruleBaselineJSON: previous.ruleBaselineJSON)
            return try library.prepareSourceUpdate(replacement, expectedGeneration: snapshot.generation,
                updatingPinnedConsumers: true, resolveInput: ConfigurationCenterSourceBridge.boundInput)
        }.value
        try await saveConfigurationPlan(candidate: plan.candidate, payloads: plan.payloads,
            compositions: plan.compositions, generation: snapshot.generation)
        return try await Task.detached { try library.snapshot() }.value
    }

    func saveConfigurationCollection(_ entry: ConfigurationCollectionEntry, definitionJSON: String?) async throws -> ConfigurationLibrarySnapshot {
         
         
        guard entry.definitionIsEditable else {
            throw entry.source.isRetainedSnapshot == true ? ConfigurationLibraryError.retainedSnapshot : ConfigurationLibraryError.readOnlySource
        }
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary, let library = configurationLibraryStore else { throw ConfigurationLibraryError.busy }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let snapshot = try await Task.detached { try library.snapshot() }.value
        let plan = try await Task.detached {
            guard var record = snapshot.sources.first(where: { $0.id == entry.source.id }),
                  record.version == entry.source.version else { throw ConfigurationLibraryError.staleGeneration }
            let previous = try library.payload(.init(record))
            var document = try OrderedJSON.parse(previous.documentJSON)
            let field = entry.id.kind.rawValue
            var definitions = document.topLevelValue(field) ?? .object([])
            if let definitionJSON {
                let value = try OrderedJSON.parse(definitionJSON)
                guard case .object = value else { throw ConfigurationLibraryError.unreadable }
                definitions = definitions.settingTopLevel(entry.collection.name, to: value)
            } else { definitions = definitions.removingTopLevel(entry.collection.name) }
            document = document.settingTopLevel(field, to: definitions)
            try ConfigTransforms.validateSource(document.serialized())
            if case .object(let values) = document.topLevelValue("proxy-providers") { record.providerCount = values.count }
            if case .object(let values) = document.topLevelValue("rule-providers") { record.ruleProviderCount = values.count }
            record.version = UUID().uuidString; record.updatedAt = Date()
            let replacement = ConfigurationSourcePayload(record: record, original: previous.original,
                documentJSON: document.serialized(), resourceFiles: previous.resourceFiles, ruleBaselineJSON: previous.ruleBaselineJSON)
            return try library.prepareSourceUpdate(replacement, expectedGeneration: snapshot.generation,
                updatingPinnedConsumers: true, resolveInput: ConfigurationCenterSourceBridge.boundInput)
        }.value
        try await saveConfigurationPlan(candidate: plan.candidate, payloads: plan.payloads,
            compositions: plan.compositions, generation: snapshot.generation)
        return try await Task.detached { try library.snapshot() }.value
    }

    func saveConfigurationCustomNode(_ version: ConfigurationSourceVersion, nodeJSON: String, index: Int? = 0) async throws -> ConfigurationLibrarySnapshot {
        try await changeConfigurationCustomNode(version, nodeJSON: nodeJSON, index: index)
    }

    func deleteConfigurationCustomNode(_ version: ConfigurationSourceVersion, index: Int) async throws -> ConfigurationLibrarySnapshot {
        try await changeConfigurationCustomNode(version, nodeJSON: nil, index: index)
    }

     
     
    func insertConfigurationCustomNode(_ version: ConfigurationSourceVersion, nodeJSON: String, at index: Int) async throws -> ConfigurationLibrarySnapshot {
        try await changeConfigurationCustomNode(version, nodeJSON: nodeJSON, index: index, inserting: true)
    }

     
     
    nonisolated static func editedCustomNodes(_ nodes: [OrderedJSON], nodeJSON: String?, index: Int?,
                                              inserting: Bool) throws -> [OrderedJSON] {
        var nodes = nodes
        if inserting, let nodeJSON {
            nodes.insert(try OrderedJSON.parse(nodeJSON), at: min(max(index ?? nodes.count, 0), nodes.count))
        } else if let index {
            guard nodes.indices.contains(index) else { throw ConfigurationLibraryError.staleGeneration }
            if let nodeJSON { nodes[index] = try OrderedJSON.parse(nodeJSON) }
            else { nodes.remove(at: index) }
        } else if let nodeJSON { nodes.append(try OrderedJSON.parse(nodeJSON)) }
        return nodes
    }

     
     
     
    private func changeConfigurationCustomNode(_ version: ConfigurationSourceVersion, nodeJSON: String?, index: Int?,
                                               inserting: Bool = false) async throws -> ConfigurationLibrarySnapshot {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let snapshot = try await Task.detached { try library.snapshot() }.value
        let plan = try await Task.detached(priority: .userInitiated) {
            guard var record = snapshot.sources.first(where: { $0.id == version.id }),
                  case .customNodes = record.origin, record.nodeChain == nil, ConfigurationSourceVersion(record) == version else {
                throw ConfigurationLibraryError.staleGeneration
            }
            let previous = try library.payload(version)
            let original = try OrderedJSON.parse(previous.documentJSON)
            guard case .array(var nodes) = original.topLevelValue("proxies") else {
                throw ConfigurationLibraryError.invalidIdentifier
            }
            nodes = try Self.editedCustomNodes(nodes, nodeJSON: nodeJSON, index: index, inserting: inserting)
            let document = original.settingTopLevel("proxies", to: .array(nodes))
            record.nodeCount = nodes.count
            let yaml = try ConfigTransforms.jsonToYAML(document.serialized())
            try ConfigTransforms.validateSource(yaml)
            record.version = UUID().uuidString; record.updatedAt = Date()
            let replacement = ConfigurationSourcePayload(record: record, original: Data(yaml.utf8),
                documentJSON: document.serialized(), resourceFiles: previous.resourceFiles)
            return try library.prepareSourceUpdate(replacement, expectedGeneration: snapshot.generation,
                updatingPinnedConsumers: true, resolveInput: ConfigurationCenterSourceBridge.boundInput)
        }.value
        try await saveConfigurationPlan(candidate: plan.candidate, payloads: plan.payloads,
            compositions: plan.compositions, generation: snapshot.generation)
        return try await Task.detached { try library.snapshot() }.value
    }

     
     
     
     
    enum ConfigurationSourceRefreshResult: Equatable { case updated, nothingNew }

     
     
     
     
     
    @discardableResult
    func refreshConfigurationSource(_ id: String, replaceEditedRules: Bool = false,
                                    expectedVersion: String? = nil,
                                    restagingConfigurationInUse: Bool = true) async throws -> ConfigurationSourceRefreshResult {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let current = try await Task.detached { try library.snapshot() }.value
        guard let source = current.availableSources.first(where: { $0.id == id }),
              case .subscription(let url) = source.origin else {
            throw ConfigurationLibraryError.missingDependency(id)
        }
        if let expectedVersion, source.version != expectedVersion { throw ConfigurationLibraryError.staleGeneration }
        let fetched: ConfigurationSourcePayload
        do {
            fetched = try await ConfigurationCenterSourceBridge.fetch(url: url, label: source.label,
                credentials: credentials, downloader: downloader)
        } catch {
            ConfigurationSourceRefusals.note(error, sourceID: id, in: runtimeDefaults)
            throw error
        }
         
         
         
         
        return try await applyFetchedSource(ConfigurationCenterSourceBridge.adopting(source, fetched: fetched),
            replacing: source, in: current, library: library, replaceEditedRules: replaceEditedRules,
            restagingConfigurationInUse: restagingConfigurationInUse)
    }

     
    func sourceRefusals() -> [String: String] { ConfigurationSourceRefusals.all(in: runtimeDefaults) }

     
     
     
    private func applyFetchedSource(_ fetched: ConfigurationSourcePayload, replacing source: ConfigurationSourceRecord,
                                    in current: ConfigurationLibrarySnapshot, library: ConfigurationLibraryStore,
                                    replaceEditedRules: Bool,
                                    restagingConfigurationInUse: Bool = true) async throws -> ConfigurationSourceRefreshResult {
        let refreshedRecord = fetched.record
        let previous = try await Task.detached(priority: .userInitiated) { try library.payload(.init(source)) }.value
        if ConfigurationCenterSourceBridge.refreshBroughtNothingNew(previous: previous, fetched: fetched) {
             
            let noted = ConfigurationCenterSourceBridge.noted(source, refreshedAt: fetched.record)
            try await Task.detached(priority: .userInitiated) {
                try ConfigurationCenterSourceBridge.noteUnchangedRefresh(noted, in: library, expectedGeneration: current.generation)
            }.value
             
             
            ConfigurationSourceRefusals.clearAfterUnchangedRefresh(source.id,
                pageStillTaken: current.hasSchemeTakingPage(fromSource: source.id), in: runtimeDefaults)
             
             
             
            try await backfillImportedPage(of: source.id, library: library,
                                           restagingConfigurationInUse: restagingConfigurationInUse)
            return .nothingNew
        }
        let prepared = try await Task.detached(priority: .userInitiated) {
            let replacement = ConfigurationSourcePayload(record: refreshedRecord, original: fetched.original,
                documentJSON: fetched.documentJSON, resourceFiles: previous.resourceFiles)
            return try library.prepareSourceUpdate(replacement, expectedGeneration: current.generation,
                replaceEditedRules: replaceEditedRules, resolveInput: ConfigurationCenterSourceBridge.boundInput)
        }.value
        try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
            compositions: prepared.compositions, generation: current.generation,
            restagesConfigurationInUse: restagingConfigurationInUse)
        if !restagingConfigurationInUse { noteRestageOwedBySourceRefresh(prepared.compositions) }
        ConfigurationSourceRefusals.clear(source.id, in: runtimeDefaults)
        ConfigurationSourceRefusals.record(prepared.pageRefusals, in: runtimeDefaults)
        return .updated
    }

     
     
     
     
    private func backfillImportedPage(of sourceID: String, library: ConfigurationLibraryStore,
                                      restagingConfigurationInUse: Bool = true) async throws {
        let current = try await Task.detached { try library.snapshot() }.value
        let prepared: PreparedConfigurationSourceUpdate?
        do {
            prepared = try await Task.detached(priority: .userInitiated) {
                try library.prepareImportedPageBackfill(sourceID: sourceID, expectedGeneration: current.generation,
                    resolveInput: ConfigurationCenterSourceBridge.boundInput)
            }.value
        } catch let refusal as ConfigurationSchemePageRefusal {
            ConfigurationSourceRefusals.record(refusal.reason, sourceID: refusal.sourceID, in: runtimeDefaults)
            return
        }
        guard let prepared else { return }
        try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
            compositions: prepared.compositions, generation: current.generation,
            restagesConfigurationInUse: restagingConfigurationInUse)
        if !restagingConfigurationInUse { noteRestageOwedBySourceRefresh(prepared.compositions) }
         
        ConfigurationSourceRefusals.clear(sourceID, in: runtimeDefaults)
    }

     
     
    private var restageOwedBySourceRefresh: String?

    private func noteRestageOwedBySourceRefresh(_ compositions: [String: ConfigurationComposition]) {
        guard let active = activeProfileID, compositions.keys.contains(active) else { return }
        restageOwedBySourceRefresh = active
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    func restageConfigurationInUseOwedBySourceRefresh() async {
        guard let owed = restageOwedBySourceRefresh else { return }
        restageOwedBySourceRefresh = nil
        guard owed == activeProfileID, let container, let workingDir,
              let latest = profiles.first(where: { $0.id == owed }) else { return }
         
         
         
         
         
         
         
         
        guard pendingActivation == nil else { return }
        enum Owed { case settled, restage(ActiveConfigurationPointer), unreadable }
        let verdict = await Task.detached(priority: .userInitiated) { () -> Owed in
            let inUse: ActiveConfigurationPointer?
            do { inUse = try ConfigResourceStore(containerURL: container).activeIdentity() } catch { return .unreadable }
            guard let inUse, inUse.profileID == owed else { return .settled }
            guard let source = try? String(contentsOf: ProfileSourceStore.runnableURL(
                      workingDirectory: workingDir, profileID: owed), encoding: .utf8) else { return .restage(inUse) }
            return PublishedSourceLedger.published(inUse, from: source) ? .settled : .restage(inUse)
        }.value
        let inUse: ActiveConfigurationPointer
        switch verdict {
        case .settled: return
        case .restage(let pointer): inUse = pointer
        case .unreadable:
             
             
             
            if restageOwedBySourceRefresh == nil { restageOwedBySourceRefresh = owed }
            return
        }
        guard owed == activeProfileID, pendingActivation == nil else { return }
        startActivation(
            latest,
            applyToTunnel: ProfileSelectionRuntimePolicy.shouldApplyToTunnel(vpnStatus: vpn.status),
            preferCachedSource: true,
            onlyIfActive: inUse,
            because: ClashPerf.Reason.configurationSaved
        )
        await waitForPendingActivation()
    }

    func saveConfigurationPlan(candidate initial: ConfigurationLibrarySnapshot,
                               payloads: [ConfigurationSourcePayload],
                               compositions: [String: ConfigurationComposition],
                               generation: UInt64, rename: String? = nil,
                               restagesConfigurationInUse: Bool = true) async throws {
        guard let library = configurationLibraryStore, let workingDir, container != nil, let profileStore else {
            throw ConfigurationLibraryError.unreadable
        }
         
         
        if compositions.isEmpty {
            try Task.checkCancellation()
            _ = try await Task.detached {
                try library.commit(initial, payloads: payloads, expectedGeneration: generation)
            }.value
             
             
             
            noteLibraryFetchability(initial)
            return
        }
        let originals = profileStore.load()
        var candidate = initial
         
         
        for index in candidate.recipes.indices where candidate.recipes[index].id != rename {
            if let profile = originals.first(where: { $0.id == candidate.recipes[index].id }) {
                candidate.recipes[index].label = profile.label
            }
        }
        let planned = candidate
        var laps = PerfLedger.Laps()
        let replacements = try await Task.detached(priority: .userInitiated) {
            try ConfigurationCenterSourceBridge.prepareReplacements(compositions: compositions, planned: planned,
                payloads: payloads, library: library, originals: originals, workingDir: workingDir,
                rename: rename)
        }.value
        laps.mark("save.prepareReplacements")
        try Task.checkCancellation()
        try await ConfigurationCenterPublicationBridge.replaceOffMain(replacements, candidate: candidate,
            payloads: payloads, library: library, workingDir: workingDir, expectedGeneration: generation)
        laps.mark("save.replace")
        noteLibraryFetchability(candidate)
        load()
        laps.mark("save.load")
        notePublished(compositions.keys)
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        if restagesConfigurationInUse, let active = activeProfileID, compositions.keys.contains(active),
           let latest = profiles.first(where: { $0.id == active }) {
            startActivation(
                latest,
                applyToTunnel: ProfileSelectionRuntimePolicy.shouldApplyToTunnel(vpnStatus: vpn.status),
                preferCachedSource: true,
                because: ClashPerf.Reason.configurationSaved
            )
            await waitForPendingActivation()
            laps.mark("save.restage")
        }
    }

     

     
     
     
    enum SourceCheck: Sendable {
        case inline
        case accepted
         
        case refused(String)
    }

    func add(
        label: String,
        source: Profile.Source,
        rawYAML: String?,
        resourceFiles: [ExternalResourceImportFile] = [],
        sourceCheck: SourceCheck = .inline
    ) {
        guard let profileStore, let workingDir else { return }
         
         
         
         
         
        let uniqueLabel = ProfileLabelPolicy.deduplicate(
            ProfileLabelPolicy.name(given: label, for: source),
            existing: profiles.map(\.label)
        )
        var profile = Profile(
            id: makeProfileID(), label: uniqueLabel,
             
             
             
            labelIsUserAssigned: !label
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            source: source,
            autoUpdate: { if case .url = source { return true } else { return false } }(),
            updateIntervalHours: 12, subscriptionInfo: nil, selectedMap: [:],
            override: OverrideSpec(), activeRevision: nil,
            order: (profiles.map(\.order).max() ?? -1) + 1,
            lastUpdatedAt: nil)
        do {
            if let rawYAML {
                switch sourceCheck {
                case .inline: try ConfigTransforms.validateSource(rawYAML)
                case .accepted: break
                case .refused(let why): throw ConfigTransformsError.invalidConfiguration(why)
                }
                 
                 
                 
                 
                 
                 
                 
                 
                let prepared = try ProfileExternalResourceImporter.prepare(
                    yaml: rawYAML,
                    profileID: profile.id,
                    source: externalResourceSource(source),
                    files: resourceFiles,
                    requiringAllFiles: { if case .file = source { return false } else { return true } }()
                )
                try ProfileExternalResourceStore.replace(
                    prepared.publicResources,
                    profileID: profile.id,
                    coreHomeDir: workingDir
                )
                profile.externalResources = prepared.references.isEmpty
                    ? nil : prepared.references
                try profileStore.upsert(profile)
                 
                try cacheSourceYAML(prepared.yaml, for: profile)
            } else {
                try profileStore.upsert(profile)
                if case .url = source {
                     
                     
                     
                     
                     
                     
                     
                    load()
                    if let stored = profiles.first(where: { $0.id == profile.id }) {
                        sync(stored)
                    }
                    return
                }
            }
        } catch {
            let failure = ConfigurationFailureClassifier.classify(
                error,
                context: .localImport,
                preservesLastKnownGood: false
            )
            planErrors = failure.map { [$0.localizedDescription] } ?? []
            statusMessage = failure.map { .copy($0.title) } ?? "Profile was not added"
             
             
             
             
            recordFailure(error, context: .localImport, operation: nil, preservesLastKnownGood: false)
            try? profileStore.remove(id: profile.id)
            try? FileManager.default.removeItem(
                at: workingDir.appendingPathComponent("store/\(profile.id)")
            )
            return
        }
        load()
    }

    @discardableResult
    func addDirectProfile() -> Profile? {
        let label = uniqueCopyLabel(base: "Local Profile", suffix: "")
        add(
            label: label,
            source: .clipboard,
            rawYAML: DirectProfileTemplate.yaml
        )
        return profiles.first { $0.label == label }
    }

     
     
     
    func selectSoleProfileIfNeeded() {
        guard let id = ProfileCenterPolicy.automaticSelectionID(
            profiles: profiles,
            activeProfileID: activeProfileID
        ), automaticSelectionAttempts.insert(id).inserted,
              let profile = profiles.first(where: { $0.id == id }) else { return }
        select(profile)
    }

     
     
    func select(_ profile: Profile) {
        guard profile.id != activeProfileID else { return }
         
         
         
         
         
         
         
        startActivation(
            profile,
            applyToTunnel: ProfileSelectionRuntimePolicy.shouldApplyToTunnel(
                vpnStatus: vpn.status
            ),
            preferCachedSource: true
,
            because: ClashPerf.Reason.profileSelected
        )
    }

     
     
     
     
     
     
     
    func largePublicationIsCurrent(_ profile: Profile) async -> Bool {
         
        guard profile.id == activeProfileID, let container, hasLargeSource(profile),
              let url = sidecarURL(for: profile), let working = workingDir else { return false }
         
        return await Task.detached(priority: .userInitiated) {
            guard let store = try? ConfigResourceStore(containerURL: container),
                  let pointer = try? store.activeIdentity(),
                  let prefix = PublishedPresentation.sourcePrefix(fileAt: url),
                  PublishedPresentation.isCurrent(pointer, sourcePrefix: prefix, profile: profile,
                                                  workingDirectory: working),
                  let text = try? store.loadConfiguration(profileID: pointer.profileID, revision: pointer.revision).text
            else { return false }
             
             
             
            return PublishedPresentation.namedFilesArePresent(in: text)
        }.value
    }

    func selectAndWait(
        _ profile: Profile, force: Bool = false, fetchesRuleSets: Bool = false
    ) async -> Bool {
         
         
         
         
         
        guard force || profile.id != activeProfileID else { return true }
        startActivation(
            profile,
            applyToTunnel: ProfileSelectionRuntimePolicy.shouldApplyToTunnel(
                vpnStatus: vpn.status
            ),
            preferCachedSource: true,
            fetchesRuleSets: fetchesRuleSets
        )
        await waitForPendingActivation()
        return activeProfileID == profile.id && lastFailure == nil
    }

    private var activationCancellationGeneration: UInt64 = 0

     
     
     
    private var latestChosenProfile: Profile? {
        for request in [pendingActivation, activationInFlight].compactMap({ $0 })
        where !request.inBackground && request.onlyIfActive == nil {
            return profiles.first { $0.id == request.profile.id } ?? request.profile
        }
        return nil
    }

     
     
     
     
     
     
     
    @discardableResult
    func connectFromHome(
        _ named: Profile, forceReactivation: Bool = true,
        stillWanted: @MainActor () -> Bool = { true },
        asReader: Bool = true,
        standingOn verified: ReaderTunnelIntent.Record? = nil
    ) async -> Bool {
         
         
         
         
        let profile = latestChosenProfile ?? named
        let cancellationGeneration = activationCancellationGeneration
         
         
         
         
         
         
         
         
         
         
         
        func stands(_ selected: Bool) -> Bool {
            selected
                && activeProfileID == profile.id
                && busyProfileID == nil && pendingActivation == nil && !isActivating
                && !Task.isCancelled
                && activationCancellationGeneration == cancellationGeneration
                 
                 
                && stillWanted()
        }
#if os(macOS)
        let republishes = forceReactivation ? !(await largePublicationIsCurrent(profile)) : false
        let selected = await selectAndWait(profile, force: republishes, fetchesRuleSets: true)
        guard stands(selected) else { return false }
         
         
         
         
         
         
         
        if let verified {
            do {
                if let last = try ReaderTunnelIntent.last(in: vpn.intentDirectory()),
                   last.generation != verified.generation, last.intent == .stop { return false }
            } catch {
                return false
            }
            return await VPNController.$standingOnWord.withValue(.init(generation: verified.generation, required: true)) {
                await vpn.start()
            }
        }
        return await vpn.start()
#else
         
         
         
        let ticket = verified.map { vpn.startTicket(continuing: $0) } ?? vpn.startTicket(asReader: asReader)
         
         
         
         
         
         
        return await vpn.preparingToStart {
            let republishes = forceReactivation ? !(await self.largePublicationIsCurrent(profile)) : false
            let selected = await self.selectAndWait(profile, force: republishes, fetchesRuleSets: true)
            guard stands(selected) else { return false }
            return await self.vpn.start(ticket: ticket)
        }
#endif
    }

     
     
     
    func stripSourceCredentials(_ profile: Profile) throws {
        guard let profileStore else {
            throw PipelineError.sourceUnavailable("the shared profile store is unavailable")
        }
         
        guard try profileStore.updateIfPresent(id: profile.id, when: {
            ProfileMetadataUpdate.strippingSourceCredentials(from: $0) != nil
        }, { current in
            if let stripped = ProfileMetadataUpdate.strippingSourceCredentials(from: current) { current = stripped }
        }) != nil else {
            return
        }
        statusMessage = "Stored URL credentials removed"
        load()
    }

     
     
     
     
     
    func saveMemoryTrim(_ profile: Profile) {
        guard let profileStore else { return }
        _ = try? profileStore.updateIfPresent(id: profile.id) { $0.memoryTrim = profile.memoryTrim }
        load()
    }

    func saveDNSBootstrapInsurance(_ profile: Profile) {
        guard let profileStore else { return }
        _ = try? profileStore.updateIfPresent(id: profile.id) {
            $0.dnsBootstrapInsurance = profile.dnsBootstrapInsurance
        }
        load()
    }

    func updateMetadata(
        _ profile: Profile,
        label: String,
        subscriptionURL: String?,
        autoUpdate: Bool,
        updateIntervalHours: Int
    ) throws {
        guard let profileStore else {
            throw PipelineError.sourceUnavailable("the shared profile store is unavailable")
        }
        let builtByTheCentre = ((try? configurationLibraryStore?.snapshot()) ?? nil)?
            .recipes.contains(where: { $0.id == profile.id }) == true
        do {
             
             
             
             
            let updated: Profile = try withProfileLock {
                let stored = profileStore.load()
                guard let current = stored.first(where: { $0.id == profile.id }) else {
                    throw PipelineError.sourceUnavailable("the profile is no longer available")
                }
                var autoUpdate = autoUpdate, subscriptionURL = subscriptionURL, updateIntervalHours = updateIntervalHours
                if builtByTheCentre {
                     
                     
                     
                     
                     
                     
                     
                    autoUpdate = false
                    updateIntervalHours = current.updateIntervalHours
                    if case let .url(link) = current.source { subscriptionURL = link }
                }
                let updated = try ProfileMetadataUpdate.apply(
                    to: current,
                    label: label,
                    subscriptionURL: subscriptionURL,
                    autoUpdate: autoUpdate,
                    updateIntervalHours: updateIntervalHours,
                    existingLabels: Set(stored.filter { $0.id != profile.id }.map(\.label))
                )
                try profileStore.upsert(updated)
                return updated
            }
            statusMessage = .format("%@ saved", [updated.label])
            clearFailure()
            load()
            notePublished([updated.id])

        } catch {
            recordFailure(
                error,
                context: .localImport,
                operation: nil,
                preservesLastKnownGood: true
            )
            throw error
        }
    }

     
     
     
     
     
     
     
     
     
     
    @discardableResult
    func duplicate(_ profile: Profile) async -> Profile? {
        guard let profileStore, let workingDir else { return nil }
        let id = makeProfileID()
        let label = uniqueCopyLabel(base: profile.label, suffix: " Copy")
        let sourceWriter = sourceWriter
        let large = hasLargeSource(profile)
        do {
            let prepared = try await Task.detached(priority: .userInitiated) { () throws -> (yaml: String?, references: [ProfileExternalResourceReference]) in
                 
                 
                 
                 
                if large {
                    return (nil, try Self.duplicatingLargeSource(profile, to: id, workingDir: workingDir))
                }
                guard let hydrated = Self.sidecarYAML(for: profile, workingDir: workingDir) else {
                    throw PipelineError.sourceUnavailable(
                        "the saved source for this profile is unavailable"
                    )
                }
                let resources = try Self.duplicateResourceFiles(
                    sourceYAML: hydrated,
                    profile: profile,
                    dataByKey: Self.externalResourceData(for: profile, workingDir: workingDir)
                )
                let prepared = try ProfileExternalResourceImporter.prepare(
                    yaml: hydrated,
                    profileID: id,
                    source: .localFile,
                    files: resources
                )
                try ProfileExternalResourceStore.replace(
                    prepared.publicResources,
                    profileID: id,
                    coreHomeDir: workingDir
                )
                return (prepared.yaml, prepared.references)
            }.value

            var copy = Profile(
                id: id,
                label: label,
                source: .file(safeProfileFileName(label)),
                autoUpdate: false,
                updateIntervalHours: profile.updateIntervalHours,
                subscriptionInfo: nil,
                selectedMap: profile.selectedMap,
                currentGroupName: profile.currentGroupName,
                unfoldedGroups: profile.unfoldedGroups,
                globalPickedByReader: profile.globalPickedByReader,
                override: profile.override,
                activeRevision: nil,
                order: profile.order + 1,
                lastUpdatedAt: nil,
                subscriptionETag: nil,
                subscriptionLastModified: nil,
                usesLocalSourceOverride: true,
                selectedScriptID: profile.selectedScriptID,
                overwriteMode: profile.overwriteMode,
                customOverwrite: profile.customOverwrite,
                proxyChain: profile.proxyChain,
                legacyRelayMigrations: profile.legacyRelayMigrations,
                proxyCredentials: nil,
                sourceCredentials: nil,
                sourceCredentialsRedacted: nil,
                externalResources: prepared.references.isEmpty ? nil : prepared.references,
                migratedGlobalOverride: profile.migratedGlobalOverride,
                outboundMode: profile.outboundMode
            )
             
             
             
             
             
             
             
            copy.postMergeScriptID = profile.postMergeScriptID
            copy.proxyNodeOverrides = profile.proxyNodeOverrides
             
             
            copy.providerDefinitions = profile.providerDefinitions
             
             
            copy.subscriptionInfo = nil
             
             
             
             
             
             
             
            let sidecarCopy = copy
            if let yaml = prepared.yaml {
                try await Task.detached(priority: .userInitiated) {
                    try sourceWriter(yaml, sidecarCopy, workingDir)
                }.value
            }
             
             
             
            let placed = copy
            try profileStore.updateAll { stored in
                for index in stored.indices where stored[index].id != placed.id && stored[index].order >= placed.order {
                    stored[index].order += 1
                }
                stored.removeAll { $0.id == placed.id }
                stored.append(placed)
            }
            statusMessage = .format("%@ created", [copy.label])
            clearFailure()
            load()
            return profiles.first(where: { $0.id == copy.id }) ?? copy
        } catch {
            try? profileStore.remove(id: id)
            try? FileManager.default.removeItem(
                at: workingDir.appendingPathComponent("store/\(id)")
            )
            recordFailure(
                error,
                context: .localImport,
                operation: nil,
                preservesLastKnownGood: true
            )
            load()
            return nil
        }
    }

     
     
     
     
    func consume(_ request: ProfileImportRequest) {
        switch request {
        case let .subscription(subscription, rules):
            installSubscription(subscription, rules: rules)
        case let .configuration(fileName, yaml, rules):
            importSharedDocument(fileName: fileName, yaml: yaml, rules: rules)
        }
#if os(tvOS)
        selectSoleProfileIfNeeded()
#endif
         
         
         
         
    }

     
     
     
     
    func installSubscription(_ rawURL: String, rules: InstallLinkRuleScheme? = nil) {
        if let existing = profiles.first(where: {
            if case let .url(url) = $0.source { return url == rawURL }
            return false
        }) {
            statusMessage = .format("Profile URL already exists; syncing %@…", [existing.label])
            sync(existing)
            return
        }
         
         
         
         
         
#if os(tvOS)
        add(label: "", source: .url(rawURL), rawYAML: nil)
#else
         
         
         
         
         
        enqueueImport { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.quickCreate(.link(rawURL, rules: rules))
            } catch {
                self.recordFailure(error, context: .subscription, operation: nil)
            }
        }
#endif
    }

     
     
     
     
     
     
     
    private final class HandedText: @unchecked Sendable {
        private var text: String?
        init(_ text: String) { self.text = text }
        func takeBytes() -> Data {
            let text = self.text ?? ""
            self.text = nil
            return ProfilesViewModel.mappedBytes(of: text) ?? Data(text.utf8)
        }
    }

     
     
     
    nonisolated static func mappedBytes(of text: String) -> Data? {
        guard text.utf8.count >= ConfigTransforms.largeTextBytes else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString).yaml")
        defer { try? FileManager.default.removeItem(at: url) }
        guard (try? ConfigTransforms.writeNewFile(text, to: url)) != nil else { return nil }
        return try? Data(contentsOf: url, options: [.alwaysMapped])
    }

    func importSharedDocument(fileName: String, yaml: String, rules: InstallLinkRuleScheme? = nil) {
#if os(tvOS)
        let label = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        add(label: label.isEmpty ? "Imported Profile" : label, source: .file(fileName), rawYAML: yaml)
#else
         
         
         
         
        let handed = HandedText(yaml)
        enqueueImport { [weak self] in
            guard let self else { return }
            let data = await Task.detached(priority: .userInitiated) { handed.takeBytes() }.value
            do {
                _ = try await self.quickCreate(.document(fileName: fileName, data: data, rules: rules))
            } catch {
                self.recordFailure(error, context: .localImport, operation: nil)
            }
        }
#endif
    }

#if !os(tvOS)
     
     
     
     
     
    private var importTail: Task<Void, Never>?

    private func enqueueImport(_ work: @escaping @MainActor () async -> Void) {
        let previous = importTail
        importTail = Task { @MainActor in
            await previous?.value
            await work()
        }
    }
#endif

    func delete(at offsets: IndexSet) {
        let doomed = offsets.map { profiles[$0] }
        Task { @MainActor in
            for profile in doomed { await delete(profile) }
        }
    }

     
     
     
     
     
     
     
    func delete(_ profile: Profile) async {
        guard profileStore != nil else { return }
        guard ProfileCenterPolicy.canDelete(
            profileID: profile.id,
            activeProfileID: activeProfileID,
            profiles: profiles
        ) else {
            statusMessage = refusalMessage(for: profile)
            return
        }
         
         
         
         
         
         
         
         
        guard !deletingProfileIDs.contains(profile.id) else {
            statusMessage = .format("%@ is already being deleted.", [profile.label])
            return
        }
         
         
         
        guard activationInFlight?.profile.id != profile.id else {
            statusMessage = .format("%@ is still updating — try again when it finishes.", [profile.label])
            return
        }
        if pendingActivation?.profile.id == profile.id { pendingActivation = nil }
        deletingProfileIDs.insert(profile.id)
        defer { deletingProfileIDs.remove(profile.id) }
         
         
         
         
         
         
         
        if profile.id == activeProfileID,
           let fallback = profiles.first(where: { $0.id == LocalDefaultProfileProvisioner.profileID }) {
             
             
             
             
             
            guard await selectAndWait(fallback) else {
                statusMessage = .format(
                    "%@ was not deleted: Clash could not switch to its built-in profile.",
                    [profile.label]
                )
                return
            }
        }
        performDelete(profile)
    }

     
     
     
     
     
    private func refusalMessage(for profile: Profile) -> ClashDisplayText {
        if profile.id == LocalDefaultProfileProvisioner.profileID {
            return "Direct is Clash's system fallback and cannot be deleted"
        }
         
         
         
        if profile.id == activeProfileID,
           !profiles.contains(where: { $0.id == LocalDefaultProfileProvisioner.profileID }),
           !profiles.contains(where: { $0.id != profile.id }) {
            return "Clash has no built-in profile to fall back to right now."
        }
        return "Switch to another profile before deleting"
    }

     
     
    private func performDelete(_ profile: Profile) {
        guard let profileStore else { return }
        let clearsOwnedFailure = failureProfile?.id == profile.id
        do {
             
             
             
             
             
             
             
            if let library = configurationLibraryStore {
                try ConfigurationCenterPublicationBridge.removeProfile(profile, library: library, profileStore: profileStore)
                 
                 
                noteLibraryFetchability(try? library.snapshot())
            } else { try profileStore.remove(id: profile.id) }
            if let workingDir {
                try? FileManager.default.removeItem(
                    at: workingDir.appendingPathComponent("store/\(profile.id)")
                )
            }
            try ProxyCredentialVault.remove(
                profile.proxyCredentials ?? [],
                store: credentials
            )
             
             
            try ProxyCredentialVault.remove(
                profile.sourceCredentials ?? [],
                store: credentials
            )
            try ProviderDefinitionCredentialVault.remove(
                profile.providerDefinitionCredentials ?? [],
                store: credentials
            )
             
            SourceEditDrafts.shared.clearAll(owner: profile.id)
            if clearsOwnedFailure {
                clearFailure()
            }
            statusMessage = .format("%@ deleted", [profile.label])
        } catch {
            statusMessage = .format("%@ could not be deleted", [profile.label])
            planErrors = [error.localizedDescription]
        }
        load()
    }

     

     
     
     
     
     
     
    func updateOverrideSettings(from draft: Profile) throws {
        try withProfileLock {
            guard let profileStore,
                  let latest = profileStore.load().first(where: { $0.id == draft.id }) else { return }
            let settings = ProfileSettingsFacade()
            try updateConfiguration(settings.applying(settings.snapshot(for: draft), to: latest))
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func updateRestagingIfActive(profileID: String, _ change: (inout Profile) -> Void) {
        guard let profileStore else { return }
        _ = try? profileStore.updateIfPresent(id: profileID, change)
        load()
        restageIfActive(profileID)
    }

     
     
     
     
     
    func restageActiveRuntime() {
        guard let activeProfileID else { return }
        restageIfActive(activeProfileID)
    }

     
     
     
    private func restageIfActive(_ profileID: String) {
        guard profileID == activeProfileID,
              let latest = profiles.first(where: { $0.id == profileID }) else { return }
        startActivation(
            latest,
            applyToTunnel: ProfileSelectionRuntimePolicy.shouldApplyToTunnel(vpnStatus: vpn.status),
            preferCachedSource: true,
            because: ClashPerf.Reason.profileEdited
        )
    }

     
     
     
     
     
     
     
     
     
    func renameProxyNode(profileID: String, from old: String, to new: String) throws {
        guard let profileStore,
              try profileStore.updateIfPresent(id: profileID, { latest in
                  var unusedPayload: [[String: Any]] = []
                  ProxyNodeRename.apply(
                      from: old, to: new, profile: &latest, customPayload: &unusedPayload
                  )
              }) != nil
        else {
            throw PipelineError.sourceUnavailable("the profile is no longer available")
        }
        load()
    }

     
     
    func updateRules(_ draft: ProfileRulesDraft) throws {
        try withProfileLock {
            guard let profileStore,
                  let latest = profileStore.load().first(where: { $0.id == draft.profileID }) else {
                throw PipelineError.sourceUnavailable("the profile is no longer available")
            }
            try updateConfiguration(draft.applying(to: latest))
        }
    }

     

     
     
     
    static func ownSchemeLabel(locale: Locale = AppPreferences.language().locale)
        -> @Sendable (ConfigurationRuleScheme, ConfigurationRecipe) -> String {
        let format = ClashCopy.string("%@ (%@)", locale: locale)
        return { scheme, recipe in String(format: format, scheme.displayLabel, recipe.label) }
    }

     
     
     
     
    struct CurrentConfigurationSettings: Equatable {
        enum Target: Equatable {
             
             
            case appLayer
             
             
             
            case ownLayer
             
             
             
             
             
            case page(ConfigurationSchemePageOwnership)
        }
         
         
         
        let profile: Profile
        let target: Target
    }

     
     
     
    nonisolated static func settingsPage(of profile: Profile, in snapshot: ConfigurationLibrarySnapshot, scripted: Bool) throws
        -> (ownership: ConfigurationSchemePageOwnership, values: OverridePatch)? {
        guard !scripted, (profile.legacyRuntimePatchJSON ?? "").isEmpty,
              let recipe = snapshot.recipes.first(where: { $0.id == profile.id }), recipe.preservesOriginal != true else { return nil }
        let scheme = snapshot.rules.first { $0.id == recipe.ruleSchemeID }
            ?? ConfigurationBuiltins.schemes.first { $0.id == recipe.ruleSchemeID }
        let running = try ConfigurationSchemePage.effective(of: recipe, scheme: scheme)
        let page = running.settings.removingTopLevel("dns").settingTopLevel("dns", to: running.dns)
        return (snapshot.schemePageOwnership(profileID: profile.id),
                OverridePatch(patchJSON: page.serialized()).retainingTopLevelKeys(FlClashRuntimeConfig.keysMovedIntoConfigurations))
    }

    func isScripted(_ profile: Profile) -> Bool {
        ScriptSettings.enabled() || profile.overwriteMode == .script || profile.postMergeScriptID != nil
    }

    private var appLayerKeysMoved: Bool {
        runtimeDefaults.object(forKey: FlClashRuntimeConfig.movedIntoConfigurationsMarkerKey) != nil
    }

     
    private func currentConfigurationSettings(of profile: Profile, in snapshot: ConfigurationLibrarySnapshot?) throws
        -> (settings: CurrentConfigurationSettings, page: OverridePatch?) {
         
         
         
        guard appLayerKeysMoved else {
            let target: CurrentConfigurationSettings.Target = (profile.legacyRuntimePatchJSON ?? "").isEmpty ? .appLayer : .ownLayer
            return (CurrentConfigurationSettings(profile: settingsProfile(for: profile), target: target), nil)
        }
        guard let snapshot, let page = try Self.settingsPage(of: profile, in: snapshot, scripted: isScripted(profile)) else {
            return (CurrentConfigurationSettings(profile: settingsProfile(for: profile), target: .ownLayer), nil)
        }
        return (CurrentConfigurationSettings(profile: settingsProfile(for: profile, page: page.values),
                                             target: .page(page.ownership)), page.values)
    }

    private var currentSettingsCache: [String: (key: String, value: CurrentConfigurationSettings)] = [:]



    private func currentSettingsKey(for profile: Profile) -> String {
        [projectionKey(for: profile), profile.legacyRuntimePatchJSON ?? "-",
         FlClashRuntimeConfig.load(from: runtimeDefaults).patchJSON, appLayerKeysMoved ? "moved" : "-"].joined(separator: "|")
    }

     
     
     
     
    func loadCurrentConfigurationSettings(for profile: Profile, reloading: Bool = false) async throws -> CurrentConfigurationSettings {
        if !reloading, let cached = currentSettingsCache[profile.id], cached.key == currentSettingsKey(for: profile) {
            return cached.value
        }
        await settleLibraryHousekeeping()
        guard let latest = profileStore?.load().first(where: { $0.id == profile.id }) else {
            throw PipelineError.sourceUnavailable("the profile is no longer available")
        }
        let library = configurationLibraryStore
        let snapshot = appLayerKeysMoved ? try await Task.detached(priority: .userInitiated) { try library?.snapshot() }.value : nil
        let value = try currentConfigurationSettings(of: latest, in: snapshot).settings
        currentSettingsCache[latest.id] = (currentSettingsKey(for: latest), value)
        return value
    }

     
     
     
     
     
     
     
    private func saveSettingsPage(profileID: String, keys: Set<String>, readAs settings: CurrentConfigurationSettings?,
                                  dnsSwitch: Bool? = nil, build: @escaping (Profile) throws -> Profile) async throws {
        guard let profileStore, let library = configurationLibraryStore else {
            throw PipelineError.sourceUnavailable("the shared profile store is unavailable")
        }
        await settleLibraryHousekeeping()
        var target = settings?.target
         
        for attempt in 1...3 {
            let latest = try latestProfile(profileID)
            let snapshot = try await Task.detached(priority: .userInitiated) { try library.snapshot() }.value
            let now = try currentConfigurationSettings(of: latest, in: snapshot)
            let lands = target ?? now.settings.target
            target = lands
            switch lands {
            case .appLayer:
                try updateAppLayer(keys, from: OverridePatch(patchJSON: try build(settingsProfile(for: latest)).override.patchJSON),
                                   dnsSwitch: dnsSwitch)
                return
            case .ownLayer:
                let candidate = OverridePatch(patchJSON: try build(settingsProfile(for: latest)).override.patchJSON)
                try updateAppLayer(keys.subtracting(FlClashRuntimeConfig.keysMovedIntoConfigurations), from: candidate)
                let moved = keys.intersection(FlClashRuntimeConfig.keysMovedIntoConfigurations)
                guard !moved.isEmpty else { return }
                try withProfileLock {
                    guard try profileStore.updateIfPresent(id: profileID, { profile in
                        var layer = OverridePatch(patchJSON: profile.legacyRuntimePatchJSON ?? "")
                        for key in moved.sorted() {
                            layer.setTopLevelNode(key, key == "dns"
                                ? Self.keepingUnwritableEmptyLists(candidate.topLevelNode(key), from: layer.topLevelNode(key))
                                : candidate.topLevelNode(key))
                        }
                        profile.legacyRuntimePatchJSON = layer.topLevelKeys.isEmpty ? nil : layer.patchJSON
                         
                         
                        if let dnsSwitch, moved.contains("dns") {
                            profile.legacyRuntimeDNSGated = layer.hasDNSOverride && !dnsSwitch ? true : nil
                        }
                    }) != nil else {
                        throw PipelineError.sourceUnavailable("the profile is no longer available")
                    }
                    afterTheHold { [weak self] in
                        self?.load()
                        self?.restageIfActive(profileID)
                    }
                }
                return
            case .page(let read):
                 
                 
                guard let page = now.page, case .page(let current) = now.settings.target,
                      current.schemeID == read.schemeID else {
                    throw PipelineError.sourceUnavailable("This configuration changed while its settings were open. Reopen them and try again.")
                }
                let candidate = OverridePatch(patchJSON: try build(now.settings.profile).override.patchJSON)
                try updateAppLayer(keys.subtracting(FlClashRuntimeConfig.keysMovedIntoConfigurations), from: candidate)
                let moved = keys.intersection(FlClashRuntimeConfig.keysMovedIntoConfigurations)
                guard !moved.isEmpty else { return }
                let nodes = Dictionary(uniqueKeysWithValues: moved.map { key in
                    (key, candidate.topLevelNode(key).map { Self.pageNode($0, for: key, replacing: page.topLevelNode(key)) })
                })
                do {
                    let prepared = try await Task.detached(priority: .userInitiated) {
                        try library.prepareSchemePageEdit(profileID: profileID, expectedGeneration: snapshot.generation,
                                                          resolveInput: ConfigurationCenterSourceBridge.BoundInputs().resolve) { page in
                            for key in nodes.keys.sorted() { page = page.setting(path: [key], to: nodes[key] ?? nil) }
                        }
                    }.value
                    try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
                                                    compositions: prepared.compositions, generation: snapshot.generation)
                    return
                } catch ConfigurationLibraryError.staleGeneration where attempt < 3 {
                    continue
                }
            }
        }
    }

     
     
     
     
    nonisolated static func pageNode(_ node: OrderedJSON, for key: String, replacing previous: OrderedJSON?) -> OrderedJSON {
        var node = key == "dns" ? keepingUnwritableEmptyLists(node, from: previous) ?? node : node
        if key == "dns", case .object = node, case .object(let before)? = previous {
            for entry in before where DNSConfigurationFieldCatalog.iOSManagedKeys.contains(entry.key) && node.node(at: [entry.key]) == nil {
                node = node.setting(path: [entry.key], to: entry.value)
            }
        }
        return ordered(node, like: previous)
    }

     
     
     
     
     
     
     
    nonisolated static func keepingUnwritableEmptyLists(_ node: OrderedJSON?, from previous: OrderedJSON?) -> OrderedJSON? {
        guard case .object? = previous else { return node }
        var result = node ?? .object([])
        for keyPath in ClashDNSInheritedBases.listKeyPaths {
            let path = keyPath.split(separator: ".").dropFirst().map(String.init)
            guard case .array(let items)? = previous?.node(at: path), items.isEmpty, result.node(at: path) == nil else { continue }
            result = result.setting(path: path, to: .array([]))
        }
        if case .object(let entries) = result, entries.isEmpty { return nil }
        return result
    }

    private nonisolated static func ordered(_ node: OrderedJSON, like previous: OrderedJSON?) -> OrderedJSON {
        guard case .object(let entries) = node, case .object(let before)? = previous else { return node }
        var result: [(key: String, value: OrderedJSON)] = []
        for old in before {
            guard let entry = entries.first(where: { $0.key == old.key }) else { continue }
            result.append((entry.key, OverridePatch.orderSensitivePolicyKeys.contains(entry.key)
                ? entry.value : ordered(entry.value, like: old.value)))
        }
        for entry in entries where !before.contains(where: { $0.key == entry.key }) { result.append(entry) }
        return .object(result)
    }

     
     
     
    private func updateAppLayer(_ keys: Set<String>, from candidate: OverridePatch, dnsSwitch: Bool? = nil) throws {
        guard !keys.isEmpty else { return }
        try withProfileLock {
            let previous = FlClashRuntimeConfig.load(from: runtimeDefaults)
            var updated = FlClashRuntimeConfig.replacingGlobalFields(in: previous, with: candidate.patchJSON, keys: keys)
            if let dnsSwitch { updated.dnsOverridesProfiles = dnsSwitch }
            guard updated != FlClashRuntimeConfig.replacingGlobalFields(in: previous, with: "", keys: []) else { return }
            FlClashRuntimeConfig.save(updated, in: runtimeDefaults)
            guard FlClashRuntimeConfig.load(from: runtimeDefaults) == updated else {
                FlClashRuntimeConfig.save(previous, in: runtimeDefaults)
                throw PipelineError.preflightFailed("the app-wide runtime preference could not be persisted")
            }
            afterTheHold { [weak self] in
                self?.restageAfterGlobalSave(runtimeAlreadyCarriesChange: false)
            }
        }
    }

    func latestProfile(_ id: String) throws -> Profile {
        guard let profileStore, let latest = profileStore.load().first(where: { $0.id == id }) else {
            throw PipelineError.sourceUnavailable("the profile is no longer available")
        }
        return latest
    }

     
    func updateDNS(_ draft: ProfileDNSDraft, readAs settings: CurrentConfigurationSettings? = nil) async throws {
        try await saveSettingsPage(profileID: draft.profileID, keys: ["dns"], readAs: settings,
                                   dnsSwitch: draft.dnsOverridesProfiles) { try draft.applying(to: $0) }
    }

     
    func updateHosts(_ draft: ProfileHostsDraft, readAs settings: CurrentConfigurationSettings? = nil) async throws {
        try await saveSettingsPage(profileID: draft.profileID, keys: ["hosts"], readAs: settings) { try draft.applying(to: $0) }
    }

     
     
    func updateNetwork(_ draft: ProfileNetworkDraft) throws {
        try withProfileLock {
            guard let profileStore,
                  let latest = profileStore.load().first(where: { $0.id == draft.profileID }) else {
                throw PipelineError.sourceUnavailable("the profile is no longer available")
            }
            let updated = FlClashRuntimeConfig.sanitizedProfile(
                try draft.applying(to: latest)
            )
            try updateConfiguration(updated)
        }
    }

     
     
    func updateGlobalNetwork(_ draft: ProfileNetworkDraft, readAs settings: CurrentConfigurationSettings? = nil) async throws {
        try await saveSettingsPage(profileID: draft.profileID, keys: OverridePatch.networkRuntimeKeys, readAs: settings) {
            try draft.applyingGlobalRuntime(to: $0)
        }
    }

     
     
     
    func updateGlobalRuntimeTrust(_ draft: ProfileRuntimeTrustDraft, readAs settings: CurrentConfigurationSettings? = nil) async throws {
        try await saveSettingsPage(profileID: draft.profileID, keys: OverridePatch.runtimeTrustKeys, readAs: settings) {
            try draft.applyingGlobalRuntime(to: $0)
        }
    }

     
     
     
     
     
     
     
     
     
    func updateLANShare(
        _ override: KernelLANShareOverride, profileID: String
    ) throws {
        try withProfileLock {
            guard let profileStore,
                  let latest = profileStore.load().first(where: { $0.id == profileID })
            else {
                throw PipelineError.sourceUnavailable(
                    "the profile is no longer available"
                )
            }
            var patch = OverridePatch(patchJSON: latest.override.patchJSON)
            let read = KernelLANShareOverride(patch: patch)
            patch.setValue(override.allowLAN, at: ["allow-lan"])
            patch.setValue(override.mixedPort.map { Int($0) }, at: ["mixed-port"])
            if override.httpPort != read.httpPort { patch.setValue(override.httpPort.map { Int($0) }, at: ["port"]) }
            if override.socksPort != read.socksPort { patch.setValue(override.socksPort.map { Int($0) }, at: ["socks-port"]) }
            var candidate = latest
            candidate.override.patchJSON = patch.patchJSON
            try updateConfiguration(candidate)
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func updateOwnSettings(profileID: String, edits: [ConfigurationPageEdit]) throws {
        try withProfileLock {
            guard let profileStore,
                  let latest = profileStore.load().first(where: { $0.id == profileID }) else {
                throw PipelineError.sourceUnavailable("the profile is no longer available")
            }
            var override = latest.override.patchJSON.isEmpty ? .object([]) : try OrderedJSON.parse(latest.override.patchJSON)
            let layerJSON = latest.legacyRuntimePatchJSON ?? ""
            var layer = layerJSON.isEmpty ? .object([]) : try OrderedJSON.parse(layerJSON)
             
             
             
            func holdsDNS() -> Bool {
                if case .object(let entries)? = layer.node(at: ["dns"]) { return !entries.isEmpty }
                return false
            }
            var dnsRanOut = !holdsDNS()
            for edit in edits {
                defer { if !holdsDNS() { dnsRanOut = true } }
                guard let key = Self.topLevelKey(of: edit) else {
                    override = try override.applying(edit)
                    continue
                }
                guard !OverridePatch.listenerKeys.contains(key) else {
                    override = try override.applying(edit)
                    continue
                }
                 
                 
                 
                 
                let taken = OverridePatch.globalRuntimeKeys.contains(key) ? nil : override.node(at: [key])
                let running = layer.node(at: [key]).map { Self.mergedAsTheCoreMerges(taken, $0) } ?? taken
                let edited = try OrderedJSON.object(running.map { [(key: key, value: $0)] } ?? []).applying(edit).node(at: [key])
                layer = layer.setting(path: [key], to: edited)
                override = override.setting(path: [key], to: nil)
            }
            var candidate = latest
            candidate.override.patchJSON = OverridePatch(patchJSON: override.serialized()).patchJSON
            let written = OverridePatch(patchJSON: layer.serialized())
            candidate.legacyRuntimePatchJSON = written.topLevelKeys.isEmpty ? nil : written.patchJSON
             
             
             
             
            if dnsRanOut || !written.hasDNSOverride { candidate.legacyRuntimeDNSGated = nil }
            guard candidate != latest else { return }
            try updateConfiguration(candidate)
        }
    }

     
     
     
     
    func updateOwnDNSSwitch(profileID: String, on: Bool) throws {
        try withProfileLock {
            guard let profileStore,
                  let latest = profileStore.load().first(where: { $0.id == profileID }) else {
                throw PipelineError.sourceUnavailable("the profile is no longer available")
            }
            guard OverridePatch(patchJSON: latest.legacyRuntimePatchJSON ?? "").hasDNSOverride else { return }
            var candidate = latest
            candidate.legacyRuntimeDNSGated = on ? nil : true
            guard candidate != latest else { return }
            try updateConfiguration(candidate)
        }
    }

     
     
    private static func topLevelKey(of edit: ConfigurationPageEdit) -> String? {
        switch edit {
        case .set(let path, _), .remove(let path): return path.first
        case .insert(let path, _, _), .replace(let path, _, _), .delete(let path, _), .move(let path, _, _): return path.first
        case .insertKey(let path, let key, _, _): return path.first ?? key
        case .renameKey(let path, _, _), .moveKeys(let path, _, _): return path.first
        }
    }

     
     
     
     
     
    func kernelLANShareBinding() -> KernelLANShareBinding {
        kernelLANShareBinding(profile: { [weak self] in self?.activeProfileID })
    }

     
     
     
    func scriptedSettings(profileID: String) async -> ScriptedSettings? {
        guard let profile = profiles.first(where: { $0.id == profileID }), ScriptedSettings.runs(on: profile),
              !hasLargeSource(profile), let workingDir else { return nil }
        return await Task.detached(priority: .utility) {
            Self.sidecarYAML(for: profile, workingDir: workingDir).flatMap { ScriptedSettings.make(raw: $0, profile: profile) }
        }.value
    }

     
     
     
    func publishedModules() async -> ModuleGlobalManifest? {
        guard let container else { return nil }
        return await Task.detached(priority: .userInitiated) {
            ModuleStore.publishedGlobalManifest(ModuleLocations(container: container))
        }.value
    }

     
     
     
     
     
     
    func kernelLANShareBinding(for profileID: String) -> KernelLANShareBinding {
        kernelLANShareBinding(profile: { profileID })
    }

    private func kernelLANShareBinding(profile id: @escaping @MainActor () -> String?) -> KernelLANShareBinding {
        KernelLANShareBinding(
            profileSourceYAML: { [weak self] in
                guard let self, let id = id(),
                      let profile = self.profiles.first(where: { $0.id == id })
                else { return nil }
                return self.sourceYAML(for: profile)
            },
            override: { [weak self] in
                guard let self, let id = id(),
                      let profile = self.profiles.first(where: { $0.id == id })
                else { return KernelLANShareOverride() }
                return KernelLANShareOverride(patch: OverridePatch(patchJSON: profile.override.patchJSON))
            },
            writeOverride: { [weak self] override in
                guard let self, let id = id() else {
                    throw PipelineError.sourceUnavailable("the profile is no longer available")
                }
                try self.updateLANShare(override, profileID: id)
            },
            profileID: id,
            applySequence: { [weak self] in self?.lastTunnelApply.sequence ?? 0 },
            restartedSince: { [weak self] since in
                guard let self, let id = id() else { return false }
                await self.waitForPendingActivation()
                return Self.restartNotice(profileID: id, since: since, last: self.lastTunnelApply) != nil
            },
            settled: { [weak self] in await self?.waitForPendingActivation() },
             
            modulesListenerKeys: { [weak self] in
                self?.container.flatMap { ModuleStore.publishedGlobalManifest(ModuleLocations(container: $0)) }?
                    .listenerKeys ?? KernelLANShareOverride()
            }
        )
    }

     
     
     
     
     
    func adoptHeldBackUpdate(_ profile: Profile, keyPath: String) throws {
        try withProfileLock {
            guard let profileStore,
                  let latest = profileStore.load().first(where: { $0.id == profile.id }),
                  let item = latest.suppressedUpdates?.first(where: { $0.keyPath == keyPath })
            else { return }
            var patch = OverridePatch(patchJSON: settingsProfile(for: latest).override.patchJSON)
            switch item.change {
            case .removed:
                patch.setValue(nil, at: item.components)
            case .added, .changed:
                guard let text = item.newValue,
                      let value = try? JSONSerialization.jsonObject(
                          with: Data(text.utf8), options: [.fragmentsAllowed]
                      )
                else { return }
                patch.setValue(value, at: item.components)
            }
             
             
            if appLayerKeysMoved, FlClashRuntimeConfig.keysMovedIntoConfigurations.contains(item.topLevelKey) {
                let adopted = patch
                guard try profileStore.updateIfPresent(id: latest.id, { current in
                    var layer = OverridePatch(patchJSON: current.legacyRuntimePatchJSON ?? "")
                    layer.replaceTopLevelKeys([item.topLevelKey], with: adopted)
                    current.legacyRuntimePatchJSON = layer.topLevelKeys.isEmpty ? nil : layer.patchJSON
                    current.suppressedUpdates = current.suppressedUpdates?.filter { $0.keyPath != keyPath }
                    if current.suppressedUpdates?.isEmpty == true { current.suppressedUpdates = nil }
                }) != nil else { return }
                afterTheHold { [weak self] in
                    self?.load()
                    self?.restageIfActive(latest.id)
                }
                return
            }
            var candidate = latest
            candidate.override.patchJSON = patch.patchJSON
            candidate.suppressedUpdates = latest.suppressedUpdates?.filter { $0.keyPath != keyPath }
            if candidate.suppressedUpdates?.isEmpty == true { candidate.suppressedUpdates = nil }
            try updateGlobalConfiguration(candidate, replacing: [item.topLevelKey])
        }
    }

     
    func dismissHeldBackUpdates(_ profile: Profile) throws {
        guard let profileStore,
              try profileStore.updateIfPresent(id: profile.id, { $0.suppressedUpdates = nil }) != nil
        else { return }
        load()
    }

     
    func updateRoutePreset(_ draft: ProfileRoutePresetDraft, readAs settings: CurrentConfigurationSettings? = nil) async throws {
        try await saveSettingsPage(profileID: draft.profileID, keys: ["tun"], readAs: settings) { try draft.applying(to: $0) }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func updateOutboundMode(
        profileID: String,
        mode: Profile.OutboundMode,
        kernelCarriesTheChange: Bool = true
    ) throws {
        try withProfileLock {
            guard let profileStore,
                  let latest = profileStore.load().first(where: { $0.id == profileID }) else {
                throw PipelineError.sourceUnavailable("the profile is no longer available")
            }
            var projected = settingsProfile(for: latest)
            var patch = OverridePatch(
                patchJSON: projected.override.patchJSON
            )
            patch.mode = mode.rawValue
            projected.override.patchJSON = patch.patchJSON
             
             
             
             
             
             
             
            let modeWasChosen = ClashTunnelOutboundMode.chosen(
                inPatchJSON: FlClashRuntimeConfig.load(from: runtimeDefaults).patchJSON
            ) != nil
            try updateGlobalConfiguration(
                projected,
                replacing: ["mode"],
                runtimeAlreadyCarriesChange: kernelCarriesTheChange,
                publicationStands: modeWasChosen
            )
            ClashWidgetFactsPublisher.appChoseMode()
        }
    }

     

     
     
     
    func outboundModeSetOnHome() -> Profile.OutboundMode? { patchedOutboundMode() }

     
     
     
     
    func keysHeldOverModules(profileID: String) -> Set<String> {
        var held: Set<String> = []
        if logLevelForcedByLogSettings() != nil { held.insert("log-level") }
        if outboundModeSetOnHome() != nil { held.insert("mode") }
        if let profile = profiles.first(where: { $0.id == profileID }) {
            if profile.outboundMode != nil { held.insert("mode") }
            held.formUnion(ProfileRuntimeConfigBuilder.lanSharingListener(of: profile).topLevelKeys)
        }
        return held
    }

     
     
     
    func followConfigurationOutboundMode() throws {
        try withProfileLock {
            guard let profileStore else {
                throw PipelineError.sourceUnavailable("the shared profile store is unavailable")
            }
            let stored = profileStore.load()
            guard let latest = stored.first(where: { $0.id == activeProfileID }) ?? stored.first else {
                throw PipelineError.sourceUnavailable("the profile is no longer available")
            }
            var projected = settingsProfile(for: latest)
            var patch = OverridePatch(patchJSON: projected.override.patchJSON)
            patch.mode = nil
            projected.override.patchJSON = patch.patchJSON
            try updateGlobalConfiguration(projected, replacing: ["mode"])
            ClashWidgetFactsPublisher.appChoseMode()
        }
    }

     
     
    func logLevelForcedByLogSettings() -> String? {
        guard case .forced(let level) = ClashLogSettings.levelDirective(from: runtimeDefaults) else { return nil }
        return level.rawValue
    }

     
     
     
    func platformConditionsHolding() -> Set<String> {
         
         
        vpn.tunnelSettings.overlaid(by: ModuleDeviceSettingOverlay.load()).includeAllNetworks ? ["includeAllNetworks"] : []
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func reconnectForModules() async {


        if activeProfileID.flatMap({ id in profiles.first { $0.id == id } }) == nil,
           let named = HomeProfileResolution.workingProfile(in: self) {
             
             
             
             
            startActivation(named, applyToTunnel: ProfileSelectionRuntimePolicy.shouldApplyToTunnel(vpnStatus: vpn.status),
                            preferCachedSource: true)
        } else {
            restageForClientRuntimeSetting()
        }
         
         
         
         
        await waitForPendingActivation()
        guard vpn.status == "connected" || vpn.status == "reasserting" else { return }
        await vpn.forceRestart()
    }



     
     
     
     
     
     
     
     
     
     
     
     
    func publishWhatOnlyAPublicationTakes(container: URL, handedOn: [PendingProviderCompile.Held] = []) {
        for item in handedOn where !compileHandedOn.contains(where: { $0.key == item.key }) { compileHandedOn.append(item) }
        guard pendingPublication == nil else { return }
        let working = container.appendingPathComponent("working", isDirectory: true)
        let state = ProviderRefreshState.read(workingDirectory: working)
        let stillHeld = PendingProviderCompile.heldKeys(in: state)
        compileHandedOn.removeAll { !stillHeld.contains($0.key) }
        var held = PendingProviderCompile.waitingForAPublication(in: state)
        for item in compileHandedOn where !held.contains(where: { $0.key == item.key }) { held.append(item) }
        held.removeAll { publishedPendings.contains($0.key) }
         
         
         
        guard !held.isEmpty, let store = try? ConfigResourceStore(containerURL: container),
              let id = store.activeIdentityOrNil()?.profileID,
              let profile = profiles.first(where: { $0.id == id })
                ?? ProfileStore(fileURL: working.appendingPathComponent("store/profiles.json")).load().first(where: { $0.id == id })
        else { return }
        publishedPendings.formUnion(held.map(\.key))
        let names = held.map(\.name)
        ClashLogStore.shared.append(#"pending publish  sets=\#(names.joined(separator: ","))"#, stream: .app)
        let vpn = self.vpn
        pendingPublication = Task { @MainActor [weak self] in
            let report = await ProviderUpdater.update(names, in: .live(
                profile: profile, store: store, container: container, vpn: vpn, scripts: .silent,
                stillInUse: { store.activeIdentityOrNil()?.profileID == id }))
            for item in held {
                let outcome = report.outcomes[item.name] ?? .skipped
                ClashLogStore.shared.append(#"pending publish  \#(item.name)  outcome=\#(outcome)"#, stream: .app)
                 
                 
                switch outcome {
                case .failed, .notConfirmed, .skipped: self?.publishedPendings.remove(item.key)
                default: break
                }
            }
            self?.pendingPublication = nil
             
             
             
            guard let self else { return }
            let started = Set(held.map(\.key))
            if self.compileHandedOn.contains(where: { !started.contains($0.key) && !self.publishedPendings.contains($0.key) }) {
                self.publishWhatOnlyAPublicationTakes(container: container)
            }
        }
    }

     
    private var pendingPublication: Task<Void, Never>?
     
    private var publishedPendings: Set<String> = []
     
    private var compileHandedOn: [PendingProviderCompile.Held] = []

    func restageForClientRuntimeSetting() {
         
         
         
         
         
         
         
         
         
         
         
        if let chosen = latestChosenProfile, chosen.id != activeProfileID {
            guard pendingActivation == nil else { return }
            if activationTask?.isCancelled != true {
                restage(chosen, inUse: chosen.id)
                return
            }
        }
        guard let id = activeProfileID,
              let profile = profiles.first(where: { $0.id == id })
        else { return }
        restage(profile, inUse: id)
    }

     
     
    private func restage(_ profile: Profile, inUse id: String) {
        switch ProfileSettingsRestagePolicy.action(
            profileID: profile.id,
            activeProfileID: id,
            vpnStatus: vpn.status
        ) {
        case .persistOnly:
            break
        case .restageOnly:
            startActivation(profile, applyToTunnel: false, preferCachedSource: true, inBackground: true,
                            because: ClashPerf.Reason.clientRuntimeSetting)
        case .restageAndApply:
            startActivation(profile, applyToTunnel: true, preferCachedSource: true)
        }
    }

     
     
     
     
     
     
     
     
     
     
    func updateProxySelection(
        profileID: String,
        group: String,
        member: String,
        catalog: ProxiesOverviewModel? = nil
    ) throws {
        guard let profileStore,
              let latest = profileStore.load().first(where: { $0.id == profileID }) else {
            throw PipelineError.sourceUnavailable("the profile is no longer available")
        }
         
         
         
         
        let catalog = try catalog ?? {
            let projected = cachedUIProjectedYAML(for: latest)
                ?? CustomNodesGroupMaterializer.projectForUI(sourceYAML: sourceYAML(for: latest), profile: latest)
                ?? sourceYAML(for: latest)
            return ProxiesOverviewModel.make(
                sourceYAML: projected,
                selectedMap: latest.selectedMap
            )
        }()
        let isGlobal = group == GlobalProxySelectionPolicy.groupName
        if isGlobal {
             
             
             
            let known = catalog.proxies.contains { $0.name == member }
                || catalog.groups.contains { $0.name == member }
            guard known else {
                throw PipelineError.sourceUnavailable("the selected proxy is no longer available")
            }
        } else {
            guard let targetGroup = catalog.groups.first(where: { $0.name == group }),
                  ProxyGroupControlKind(rawType: targetGroup.type).acceptsMemberChoice,
                  targetGroup.members.contains(where: { $0.name == member }) else {
                throw PipelineError.sourceUnavailable("the selected proxy is no longer available")
            }
        }
         
         
         
        guard let updated = try profileStore.updateIfPresent(id: profileID, {
            $0.noteReaderPick(group: group, member: member)
        }) else {
            throw PipelineError.sourceUnavailable("the profile is no longer available")
        }
         
         
         
         
         
        if let index = profiles.firstIndex(where: { $0.id == updated.id }) {
            profiles[index] = updated
        } else {
            load()
        }
    }

     
     
     
     
     
     
    private var derivedModeMemo: (key: DerivedModeKey, mode: Profile.OutboundMode)?

     
     
     
     
    struct DerivedModeKey: Equatable {
        let profileID: String
        let patchJSON: String
        let generation: Int
    }
    private var derivedModeGeneration = 0

     
     
    private(set) var derivedModeTask: (key: DerivedModeKey, task: Task<Profile.OutboundMode, Never>)?

    private func derivedModeKey(for profile: Profile) -> DerivedModeKey {
        DerivedModeKey(profileID: profile.id, patchJSON: profile.override.patchJSON, generation: derivedModeGeneration)
    }

     
     
    private func patchedOutboundMode() -> Profile.OutboundMode? {
        let runtime = FlClashRuntimeConfig.load(from: runtimeDefaults)
        guard let raw = OverridePatch(patchJSON: runtime.patchJSON).mode else { return nil }
        return Profile.OutboundMode(rawValue: raw.lowercased())
    }

    private func memoizedOutboundMode(for profile: Profile) -> Profile.OutboundMode? {
        guard let memo = derivedModeMemo, memo.key == derivedModeKey(for: profile) else { return nil }
        return memo.mode
    }

     
     
     
     
     
    func cachedOutboundMode(for profile: Profile) -> Profile.OutboundMode? {
        if let patched = patchedOutboundMode() { return patched }
        if let memo = memoizedOutboundMode(for: profile) { return memo }
        _ = derivation(for: profile)
        return memoizedOutboundMode(for: profile)
    }

     
     
     
     
    func outboundMode(for profile: Profile) async -> Profile.OutboundMode {
        if let patched = patchedOutboundMode() { return patched }
        var mode = Profile.OutboundMode.rule
        for _ in 0..<3 {
            if let memo = memoizedOutboundMode(for: profile) { return memo }
            let generation = derivedModeGeneration
            guard let task = derivation(for: profile) else { return memoizedOutboundMode(for: profile) ?? .rule }
            mode = await task.value
            if generation == derivedModeGeneration { return mode }
        }
        return mode
    }

     
     
     
    private var lastDerivedModeByProfile: [String: Profile.OutboundMode] = [:]

    func lastKnownOutboundMode(for profile: Profile) -> Profile.OutboundMode? {
        lastDerivedModeByProfile[profile.id]
    }

     
     
     
     
    private func derivation(for asked: Profile) -> Task<Profile.OutboundMode, Never>? {
         
         
         
         
        let profile = profiles.first(where: { $0.id == asked.id }) ?? asked
        let key = derivedModeKey(for: profile)
        if let running = derivedModeTask, running.key == key { return running.task }
         
         
         
        guard let source = sidecarURL(for: profile), FileManager.default.fileExists(atPath: source.path) else {
            derivedModeMemo = (key, .rule)
            return nil
        }
        let large = hasLargeSource(profile)
        let runtime = FlClashRuntimeConfig.load(from: runtimeDefaults)
        let container = container
        let task = Task { [weak self] () -> Profile.OutboundMode in
            let mode = await Task.detached(priority: .utility) { () -> Profile.OutboundMode in
                if large { return Self.largeSourceOutboundMode(sourceAt: source, profile: profile, container: container) }
                guard let raw = try? String(contentsOf: source, encoding: .utf8) else { return .rule }
                return PerfLedger.asJob("mode-build") {
                    Self.quickOutboundMode(raw: raw, profile: profile, runtime: runtime, container: container)
                        ?? Self.derivedOutboundMode(raw: raw, profile: profile, runtime: runtime)
                }
            }.value
            guard let self else { return mode }
            if self.derivedModeTask?.key == key { self.derivedModeTask = nil }
            guard key.generation == self.derivedModeGeneration else { return mode }
            self.derivedModeMemo = (key, mode)
            self.lastDerivedModeByProfile[key.profileID] = mode
            self.objectWillChange.send()
            self.publishWidgetFacts()
            return mode
        }
        derivedModeTask = (key, task)
        return task
    }

     
     
     
     
     
     
     
     
     
     
     
     
    nonisolated static func quickOutboundMode(
        raw: String, profile: Profile, runtime: OverrideSpec, container: URL?,
        global: OverrideSpec = GlobalConfig.load(),
        configScriptEnabled: Bool = ScriptSettings.enabled()
    ) -> Profile.OutboundMode? {
        guard readsModeWithoutTheBuild else { return nil }
        if let container,
           let store = try? ConfigResourceStore(containerURL: container),
           let pointer = try? store.activeIdentity(), pointer.profileID == profile.id,
           let published = PublishedPresentation.currentText(
               of: pointer, store: store, source: raw, profile: profile,
               workingDirectory: container.appendingPathComponent("working", isDirectory: true)),
           let mode = topLevelOutboundMode(in: published) {
            return mode
        }
        let layers = [profile.override.patchJSON, runtime.patchJSON, global.patchJSON, profile.legacyRuntimePatchJSON ?? ""]
         
         
        guard profile.selectedScriptID == nil, profile.postMergeScriptID == nil, !configScriptEnabled,
              profile.outboundMode == nil,
              layers.allSatisfy({ OverridePatch(patchJSON: $0).mode == nil })
        else { return nil }
        return topLevelOutboundMode(in: raw)
    }

     
    nonisolated(unsafe) static var readsModeWithoutTheBuild = true

     
     
     
     
    nonisolated static func largeSourceOutboundMode(sourceAt url: URL, profile: Profile, container: URL?) -> Profile.OutboundMode {
        if let container, let store = try? ConfigResourceStore(containerURL: container),
           let pointer = try? store.activeIdentity(), pointer.profileID == profile.id,
           let prefix = PublishedPresentation.sourcePrefix(fileAt: url),
           let published = PublishedPresentation.currentText(
               of: pointer, store: store, sourcePrefix: prefix, profile: profile,
               workingDirectory: container.appendingPathComponent("working", isDirectory: true)),
           let mode = topLevelOutboundMode(in: published) {
            return mode
        }
        guard let data = try? Data(contentsOf: url, options: [.alwaysMapped]),
              let section = data.withUnsafeBytes({ TopLevelYAMLSections.section("mode", inBytes: $0.bindMemory(to: UInt8.self)) })
        else { return .rule }
        return topLevelOutboundMode(in: section) ?? .rule
    }

     
     
     
    nonisolated static func topLevelOutboundMode(in text: String) -> Profile.OutboundMode? {
        guard let lines = TopLevelYAMLSections.keyLines(of: text) else { return nil }
        guard let line = lines.first(where: { $0.key == "mode" }) else { return .rule }
        let utf8 = text.utf8
        let start = utf8.index(utf8.startIndex, offsetBy: line.offset)
        let rest = text[start...]
        let firstLine = rest.prefix { $0 != "\n" && $0 != "\r" }
        guard let colon = firstLine.firstIndex(of: ":") else { return nil }
        var value = firstLine[firstLine.index(after: colon)...]
        if let comment = value.range(of: " #") { value = value[..<comment.lowerBound] }
        let word = value.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return Profile.OutboundMode(rawValue: word.lowercased())
    }

    nonisolated static func derivedOutboundMode(
        raw: String, profile: Profile, runtime: OverrideSpec
    ) -> Profile.OutboundMode {
        guard let stages = try? ProfileRuntimeConfigBuilder.buildProductionStages(
                raw: raw,
                profile: profile,
                runtimeOverride: runtime, scripts: .silent
              ),
              let json = try? stages.beforeClientRuntimePolicyJSON
                ?? ConfigTransforms.yamlToJSON(stages.beforeClientRuntimePolicy),
              let decoded = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
              let object = decoded as? [String: Any],
              let rawMode = object["mode"] as? String,
              let mode = Profile.OutboundMode(rawValue: rawMode.lowercased()) else {
            return .rule
        }
        return mode
    }

     
     
     
     
    func settingsProfile(for profile: Profile, page: OverridePatch? = nil) -> Profile {
        var projected = FlClashRuntimeConfig.sanitizedProfile(
            profile
        )
        var patch = OverridePatch(
            patchJSON: projected.override.patchJSON
        )
        let runtime = FlClashRuntimeConfig.load(
            from: runtimeDefaults
        )
        patch.overlayTopLevelKeys(
            OverridePatch.globalRuntimeKeys,
            from: OverridePatch(patchJSON: runtime.patchJSON)
        )
         
         
        let legacy = OverridePatch(patchJSON: profile.legacyRuntimePatchJSON ?? "")
        patch = patch.overlaying(legacy)
         
         
        if let page { patch.replaceTopLevelKeys(FlClashRuntimeConfig.keysMovedIntoConfigurations, with: page) }
        projected.override.patchJSON = patch.patchJSON
        projected.override.dnsOverridesProfiles = page != nil ? true
            : legacy.hasDNSOverride ? profile.legacyRuntimeDNSGated != true : runtime.dnsOverridesProfiles
        projected.outboundMode = OverridePatch(
            patchJSON: runtime.patchJSON
        ).mode.flatMap(Profile.OutboundMode.init(rawValue:))
        return projected
    }

     
     
    func updateProxyChains(_ draft: ProfileProxyChainDraft) async throws {
        try await saveValidated(profileID: draft.profileID,
                                gone: PipelineError.sourceUnavailable("the profile is no longer available")) { latest in
            let updated = try draft.applying(to: latest)
            if let rawYAML = self.runtimeSourceYAML(for: latest) {
                 
                try await Task.detached(priority: .userInitiated) {
                    do {
                         
                         
                        _ = try ProfileRuntimeConfigBuilder.runtimePreview(
                            raw: rawYAML,
                            profile: updated, scripts: .surfaced
                        )
                    } catch let error as LegacyRelayMigrationError {
                         
                         
                         
                         
                        guard draft.removesLegacyRelayConfirmation(
                            requiredBy: error,
                            from: latest
                        ) else {
                            throw error
                        }
                    }
                }.value
            } else if !draft.proxyChain.isEmpty || !draft.legacyRelayMigrations.isEmpty {
                throw PipelineError.sourceUnavailable(
                    "Sync or prepare this profile before configuring proxy chains."
                )
            }
            return updated
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    nonisolated static func statusLine(label: String, outcome: TunnelApplyOutcome?) -> ClashDisplayText {
        switch outcome {
        case .applied(let warning?)?: return .format("%@ is active (%@)", [label, warning])
        case .applied?: return .format("%@ is active", [label])
         
        case .restarted?: return .format("%@ is active; the tunnel reconnected to apply it", [label])
        case .keptRunning(let reason)?:
            return .format("%@ saved; the tunnel kept the previous version: %@", [label, reason])
        case .failed(let reason)?: return .format("%@ saved; the tunnel did not start: %@", [label, reason])
        case .pending?: return .format("%@ saved; the tunnel is still starting", [label])
        case .savedForNext?, nil: return .format("%@ saved for the next connection", [label])
        }
    }

     
     
    nonisolated(unsafe) var runtimePreviewValidator: @Sendable (String, Profile) throws -> Void = {
        raw, profile in
        _ = try ProfileRuntimeConfigBuilder.runtimePreview(raw: raw, profile: profile, scripts: .surfaced)
    }

     
     
     
     
    nonisolated(unsafe) var nodeOverrideBaseBuilder: @Sendable (String, Profile) throws -> String = {
        raw, profile in
        try ProfileRuntimeConfigBuilder.buildProductionStages(
            raw: raw, profile: profile, applyProxyChain: false, applyLegacyRelayMigration: false, scripts: .silent
        ).afterClientTransforms
    }


     
     
     
     
     
     
     
    func updateProxyNode(profileID: Profile.ID, originalJSON: String, editedJSON: String) async throws {
         
         
         
        guard let profileStore,
              profileStore.load().contains(where: { $0.id == profileID }) else {
            throw PipelineError.sourceUnavailable("there is no selected profile to edit")
        }

        let original = try Self.proxyMapping(from: originalJSON)
        let edited = try Self.proxyMapping(from: editedJSON)
        guard let name = original["name"] as? String,
              !name.isEmpty,
              edited["name"] as? String == name,
              edited["type"] as? String == original["type"] as? String else {
            throw ProxyNodeOverrideError.invalidConfiguration
        }

         
         
         
         
        let originalMapping = try Self.onlyProxy(in: Self.singleProxyYAML(original))
        let editedMapping = try Self.onlyProxy(in: Self.singleProxyYAML(edited))
        var delta = Self.mergePatch(from: originalMapping, to: editedMapping)
        delta.removeValue(forKey: "name")
        delta.removeValue(forKey: "type")

         
         
         
         
        let validate = runtimePreviewValidator
        try await saveValidated(profileID: profileID,
                                gone: PipelineError.sourceUnavailable("there is no selected profile to edit")) { latest in
            let storedSource = self.sidecarYAML(for: latest)
            guard ProxyNodeEditPolicy.isEditable(hasStoredSource: storedSource != nil),
                  let sourceYAML = storedSource else {
                throw PipelineError.sourceUnavailable(
                    ProxyNodeEditPolicy.unavailableReason
                )
            }
             
             
             
             
             
            let unpatched = latest
            let nodes = await Task.detached(priority: .userInitiated) {
                Self.nodesBeforeOverrides(sourceYAML: sourceYAML, profile: unpatched)
            }.value
            var node: [String: Any]?
            if let nodes {
                let matching = nodes.filter { $0["name"] as? String == name }
                guard !matching.isEmpty else { throw ProxyNodeOverrideError.nodeRenamed }
                guard matching.count == 1 else { throw ProxyNodeOverrideError.duplicateProxyName(name) }
                node = matching[0]
            }
            var updated = latest
            var nodeOverrides = updated.proxyNodeOverrides ?? ProxyNodeOverrideSpec()
             
             
             
            let adopted = node.flatMap { node in nodes.flatMap { nodeOverrides.adoptable(for: node, among: $0) } }
            if let adopted { nodeOverrides.removePatch(for: adopted.proxy) }
             
             
             
             
             
             
             
             
             
            let existingPatch = nodeOverrides.patch(for: name) ?? adopted?.patchJSON
            let sourceNode: [String: Any]?
            if Self.patchRestoresReplacedObject(existing: existingPatch, delta: delta) {
                var bare = latest
                bare.proxyNodeOverrides = nodeOverrides.isEmpty ? nil : nodeOverrides
                let build = self.nodeOverrideBaseBuilder
                sourceNode = await Task.detached(priority: .userInitiated) {
                    Self.nodeBeforeItsOverride(named: name, sourceYAML: sourceYAML, profile: bare, build: build)
                }.value
            } else {
                sourceNode = nil
            }
            nodeOverrides.setPatch(try Self.composedNodePatch(existing: existingPatch, delta: delta,
                                                              sourceNode: sourceNode),
                                   for: name, anchor: node.flatMap(ProxyNodeOverride.anchor(of:)))
            updated.proxyNodeOverrides = nodeOverrides.isEmpty ? nil : nodeOverrides
             
            let candidate = updated
            try await Task.detached(priority: .userInitiated) {
                try validate(sourceYAML, candidate)
            }.value
            return updated
        }
    }

     
     
     
    nonisolated static func composedNodePatch(existing: String?, delta: [String: Any],
                                              sourceNode: [String: Any]? = nil) throws -> String {
        var base: [String: Any] = [:]
        if let existing, !existing.isEmpty,
           let object = try JSONSerialization.jsonObject(with: Data(existing.utf8)) as? [String: Any] {
            base = object
        }
        let composed = composeMergePatch(base, delta, source: sourceNode)
        let data = try JSONSerialization.data(withJSONObject: composed, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated static func composeMergePatch(_ first: [String: Any], _ second: [String: Any],
                                              source: [String: Any]? = nil) -> [String: Any] {
        var result = first
        for (key, value) in second {
            guard let nested = value as? [String: Any] else {
                result[key] = value
                continue
            }
            if let prior = first[key] as? [String: Any] {
                result[key] = composeMergePatch(prior, nested, source: source?[key] as? [String: Any])
            } else if first[key] != nil, let original = source?[key] as? [String: Any] {
                 
                 
                 
                 
                result[key] = replacing(original, with: nested)
            } else {
                result[key] = nested
            }
        }
        return result
    }

     
     
    nonisolated static func replacing(_ original: [String: Any], with value: [String: Any]) -> [String: Any] {
        var result = value
        for (key, old) in original {
            guard let new = value[key] else {
                result[key] = NSNull()
                continue
            }
            if let oldObject = old as? [String: Any], let newObject = new as? [String: Any] {
                result[key] = replacing(oldObject, with: newObject)
            }
        }
        return result
    }

     
     
     
    nonisolated static func patchRestoresReplacedObject(existing: String?, delta: [String: Any]) -> Bool {
        guard let existing, !existing.isEmpty,
              let first = (try? JSONSerialization.jsonObject(with: Data(existing.utf8))) as? [String: Any]
        else { return false }
        func meets(_ first: [String: Any], _ second: [String: Any]) -> Bool {
            second.contains { key, value in
                guard let nested = value as? [String: Any] else { return false }
                if let prior = first[key] as? [String: Any] { return meets(prior, nested) }
                return first[key] != nil
            }
        }
        return meets(first, delta)
    }

     
     
     
     
     
    nonisolated static func nodeBeforeItsOverride(named name: String, sourceYAML: String, profile: Profile,
                                                  build: (String, Profile) throws -> String) -> [String: Any]? {
        var bare = profile
        var overrides = bare.proxyNodeOverrides ?? ProxyNodeOverrideSpec()
        overrides.removePatch(for: name)
        bare.proxyNodeOverrides = overrides.isEmpty ? nil : overrides
         
        bare.proxyChain = nil
        bare.legacyRelayMigrations = nil
        bare.memoryTrim = nil
        guard let document = try? build(sourceYAML, bare),
              let node = sourceProxy(named: name, in: document) else {
            return sourceProxy(named: name, in: sourceYAML)
        }
        return node
    }

     
     
     
     
     
    nonisolated static func nodesBeforeOverrides(sourceYAML: String, profile: Profile) -> [[String: Any]]? {
        var bare = profile
        bare.proxyNodeOverrides = nil
        bare.proxyChain = nil
        guard let projected = CustomNodesGroupMaterializer.projectForUI(sourceYAML: sourceYAML, profile: bare),
              let json = try? ConfigTransforms.yamlToJSON(projected),
              let root = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else {
            return nil
        }
        return root["proxies"] as? [[String: Any]] ?? []
    }

     
    nonisolated static func sourceProxy(named name: String, in sourceYAML: String) -> [String: Any]? {
        guard let json = try? ConfigTransforms.yamlToJSON(sourceYAML),
              let root = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let node = (root["proxies"] as? [[String: Any]])?.first(where: { $0["name"] as? String == name })
        else { return nil }
        return (try? onlyProxy(in: singleProxyYAML(node))) ?? node
    }

     
     
     
    func proxyNodeOverrideKey(named name: String, profileID: Profile.ID) async -> String? {
        guard let profileStore,
              let latest = profileStore.load().first(where: { $0.id == profileID }),
              let spec = latest.proxyNodeOverrides else { return nil }
        if spec.patch(for: name) != nil { return name }
        guard spec.overrides.contains(where: { $0.anchor != nil }),
              let source = sidecarYAML(for: latest) else { return nil }
        return await Task.detached(priority: .userInitiated) {
            guard let nodes = Self.nodesBeforeOverrides(sourceYAML: source, profile: latest),
                  let node = nodes.first(where: { $0["name"] as? String == name }) else { return nil }
            return spec.adoptable(for: node, among: nodes)?.proxy
        }.value
    }

     
     
    func proxyNodeOverridePatch(named name: String, profileID: Profile.ID) -> String? {
        guard let profileStore,
              let latest = profileStore.load().first(where: { $0.id == profileID }) else {
            return nil
        }
        return latest.proxyNodeOverrides?.patch(for: name)
    }

     
     
    func removeProxyNodeOverride(named name: String, profileID: Profile.ID) throws {
        try withProfileLock {
            guard let profileStore,
                  let latest = profileStore.load().first(where: { $0.id == profileID }) else {
                throw PipelineError.sourceUnavailable("there is no selected profile to edit")
            }
            var updated = latest
            var nodeOverrides = updated.proxyNodeOverrides ?? ProxyNodeOverrideSpec()
            nodeOverrides.removePatch(for: name)
            updated.proxyNodeOverrides = nodeOverrides.isEmpty ? nil : nodeOverrides
            try updateConfiguration(updated)
        }
    }

    private static func proxyMapping(from json: String) throws -> [String: Any] {
        guard let mapping = try JSONSerialization.jsonObject(with: Data(json.utf8))
                as? [String: Any] else {
            throw ProxyNodeOverrideError.invalidConfiguration
        }
        return mapping
    }

    nonisolated private static func singleProxyYAML(_ mapping: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: ["proxies": [mapping]],
            options: [.sortedKeys]
        )
        return try ConfigTransforms.jsonToYAML(String(decoding: data, as: UTF8.self))
    }

    nonisolated private static func onlyProxy(in yaml: String) throws -> [String: Any] {
        let json = try ConfigTransforms.yamlToJSON(yaml)
        guard let root = try JSONSerialization.jsonObject(with: Data(json.utf8))
                as? [String: Any],
              let mapping = (root["proxies"] as? [[String: Any]])?.first else {
            throw ProxyNodeOverrideError.invalidConfiguration
        }
        return mapping
    }

    private static func mergePatch(
        from original: [String: Any],
        to edited: [String: Any]
    ) -> [String: Any] {
        var patch: [String: Any] = [:]
        for key in Set(original.keys).union(edited.keys) {
            guard let editedValue = edited[key] else {
                patch[key] = NSNull()
                continue
            }
            guard let originalValue = original[key] else {
                 
                 
                 
                 
                if editedValue is NSNull { continue }
                patch[key] = editedValue
                continue
            }
            if let oldObject = originalValue as? [String: Any],
               let newObject = editedValue as? [String: Any] {
                let nested = mergePatch(from: oldObject, to: newObject)
                if !nested.isEmpty { patch[key] = nested }
            } else if !jsonValuesEqual(originalValue, editedValue) {
                patch[key] = editedValue
            }
        }
        return patch
    }

    private static func jsonValuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        guard JSONSerialization.isValidJSONObject([lhs]),
              JSONSerialization.isValidJSONObject([rhs]),
              let left = try? JSONSerialization.data(withJSONObject: [lhs], options: [.sortedKeys]),
              let right = try? JSONSerialization.data(withJSONObject: [rhs], options: [.sortedKeys])
        else { return false }
        return left == right
    }

     
     
     
     
    func updateAdvancedOverrides(_ draft: ProfileAdvancedOverridesDraft) async throws {
        try await saveValidated(profileID: draft.profileID, gone: ProfileAdvancedOverridesError.profileChanged) { latest in
            let availableScriptIDs = Set(ScriptLibrary.load().map(\.id))
            let updated = try draft.applying(
                to: latest,
                availableScriptIDs: availableScriptIDs
            )
            let profileOwned = FlClashRuntimeConfig.sanitizedProfile(updated)
            if let rawYAML = self.runtimeSourceYAML(for: latest) {
                let runtime = FlClashRuntimeConfig.load(from: self.runtimeDefaults)
                do {
                     
                     
                    _ = try await Task.detached(priority: .userInitiated) {
                        try ProfileRuntimeConfigBuilder.runtimePreview(
                            raw: rawYAML,
                            profile: profileOwned,
                            runtimeOverride: runtime, scripts: .surfaced
                        )
                    }.value
                } catch {
                     
                     
                     
                     
                     
                    throw ProfileAdvancedOverridesError.validationFailed(
                        reason: (error as NSError).localizedDescription
                    )
                }
            }
            return profileOwned
        }
    }

     
     
     
     
     
     
    func saveValidated(
        profileID: String,
        gone: @autoclosure () -> Error,
        _ prepare: (Profile) async throws -> Profile
    ) async throws {
        guard let profileStore else { throw gone() }
        for _ in 0..<3 {
            guard let latest = profileStore.load().first(where: { $0.id == profileID }) else { throw gone() }
            let updated = try await prepare(latest)
             
             
             
            let wrote: Bool = try withProfileLock {
                guard let now = profileStore.load().first(where: { $0.id == profileID }) else { throw gone() }
                guard now == latest else { return false }
                try updateConfiguration(updated)
                return true
            }
            if wrote { return }
        }
        throw gone()
    }

     
     
     
     
    func providerDefinitionsDraft(for profile: Profile) throws -> ProfileProviderDefinitionsDraft {
        guard let profileStore,
              let latest = profileStore.load().first(where: { $0.id == profile.id }) else {
            throw ProfileProviderDefinitionError.profileChanged
        }
        let baseline = try providerDefinitionsBaseline(for: latest)
        return try ProfileProviderDefinitionsDraft(
            profile: latest,
            baselineYAML: baseline
        )
    }

     
     
     
     
     
    func providerDefinitionsDraftAsync(
        for profile: Profile
    ) async throws -> ProfileProviderDefinitionsDraft {
        guard let latest = profiles.first(where: { $0.id == profile.id }),
              let raw = runtimeSourceYAML(for: latest) else {
            throw ProfileResourceSummaryError.sourceUnavailable
        }
        return try await Self.providerDraft(profile: latest, raw: raw)
    }

    struct ProviderDraftKey: Equatable {
        let profile: Profile
        let raw: String
    }

     
     
     
     
     
     
    @MainActor
    static let lastProviderDraft = ClashLastPreparation<
        ProviderDraftKey, Result<ProfileProviderDefinitionsDraft, ProfileProviderDefinitionError>
    >()

    @MainActor
    static func prewarmProviderDraft(profile: Profile, raw: String) async {
        _ = try? await providerDraft(profile: profile, raw: raw)
    }

    @MainActor
    static func providerDraft(
        profile latest: Profile, raw: String
    ) async throws -> ProfileProviderDefinitionsDraft {
        let key = ProviderDraftKey(profile: latest, raw: raw)
        let outcome = await lastProviderDraft.value(for: key) {
            let began = DispatchTime.now().uptimeNanoseconds
            let made: Result<ProfileProviderDefinitionsDraft, ProfileProviderDefinitionError> =
                await Task.detached(priority: .userInitiated) {
                    do {
                        let baseline = try ProfileRuntimeConfigBuilder.buildProduction(
                            raw: raw,
                            profile: latest,
                            applyProviderDefinitions: false, scripts: .silent
                        )
                        return .success(
                            try ProfileProviderDefinitionsDraft(
                                profile: latest,
                                baselineYAML: baseline
                            )
                        )
                    } catch {
                        return .failure(.invalidConfiguration)
                    }
                }.value
            ClashPerf.span(
                "providers.draft.prepare",
                milliseconds: Double(
                    DispatchTime.now().uptimeNanoseconds - began
                ) / 1_000_000,
                detail: "yamlBytes=\(raw.utf8.count)"
            )
            return made
        }
        return try outcome.get()
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func updateCustomNodePayload(
        _ definitionJSON: String?, for profileID: String
    ) throws {
        try withProfileLock {
            guard let profileStore,
                  let latest = profileStore.load().first(where: { $0.id == profileID })
            else { throw ProfileProviderDefinitionError.profileChanged }

            var spec = latest.providerDefinitions ?? ProfileProviderDefinitionSpec()
            let name = CustomNodePayload.providerName
            if let json = definitionJSON {
                if let at = spec.proxyProviders.firstIndex(where: { $0.name == name }) {
                    spec.proxyProviders[at].definitionJSON = json
                } else {
                    spec.proxyProviders.append(
                        ProfileProviderDefinitionMutation(name: name, definitionJSON: json)
                    )
                }
            } else {
                spec.proxyProviders.removeAll { $0.name == name }
            }

            var updated = latest
            updated.providerDefinitions = spec.isEmpty ? nil : spec

             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            let began = DispatchTime.now().uptimeNanoseconds
            defer {
                ClashPerf.span(
                    "save.customNodePayload",
                    milliseconds: Double(
                        DispatchTime.now().uptimeNanoseconds - began
                    ) / 1_000_000,
                    detail: "providers=\(spec.proxyProviders.count)"
                )
            }
             
             
             
             
            try updateConfiguration(updated)
        }
    }

    func updateProviderDefinitions(_ draft: ProfileProviderDefinitionsDraft) async throws {
        guard let profileStore, let workingDir else {
            throw ProfileProviderDefinitionError.profileChanged
        }
         
         
         
         
         
        for _ in 0..<3 {
            guard let latest = profileStore.load().first(where: { $0.id == draft.profileID }) else {
                throw ProfileProviderDefinitionError.profileChanged
            }
            guard let raw = runtimeSourceYAML(for: latest) else {
                throw ProfileResourceSummaryError.sourceUnavailable
            }
             
             
            let baseline = try await Task.detached(priority: .userInitiated) {
                try Self.providerDefinitionsBaseline(raw: raw, profile: latest)
            }.value
            var updated = try draft.applying(
                to: latest,
                currentBaselineYAML: baseline
            )
            let root: [String: Any]
            do {
                 
                 
                let building = updated
                let json = try await Task.detached(priority: .userInitiated) {
                    try ConfigTransforms.yamlToJSON(
                        try ProfileRuntimeConfigBuilder.buildProduction(raw: raw, profile: building, scripts: .surfaced)
                    )
                }.value
                guard let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
                        as? [String: Any] else {
                    throw ProfileProviderDefinitionError.invalidConfiguration
                }
                root = object
            } catch let bounded as ProfileProviderDefinitionError {
                throw bounded
            } catch {
                throw Self.providerSaveRefusal(error)
            }
             
             
             
            let committed: Bool = try withProfileLock {
                guard profileStore.load().first(where: { $0.id == draft.profileID }) == latest else { return false }
                let previousResources = externalResourceData(for: latest)
                do {
                    try replaceProviderResources(
                        draft: draft,
                        latest: latest,
                        updated: &updated,
                        runtimeRoot: root,
                        previousResources: previousResources,
                        workingDir: workingDir
                    )
                    try updateConfiguration(updated)
                    return true
                } catch let bounded as ProfileProviderDefinitionError {
                    try? ProfileExternalResourceStore.replace(
                        previousResources,
                        profileID: latest.id,
                        coreHomeDir: workingDir
                    )
                    throw bounded
                } catch {
                    try? ProfileExternalResourceStore.replace(
                        previousResources,
                        profileID: latest.id,
                        coreHomeDir: workingDir
                    )
                    throw Self.providerSaveRefusal(error)
                }
            }
            if committed { return }
        }
        throw ProfileProviderDefinitionError.profileChanged
    }

     
     
     
     
     
     
     
     
     
     
    nonisolated private static func providerSaveRefusal(_ error: Error) -> ProfileProviderDefinitionError {
        .buildRefused(error.localizedDescription)
    }

    private func replaceProviderResources(
        draft: ProfileProviderDefinitionsDraft,
        latest: Profile,
        updated: inout Profile,
        runtimeRoot root: [String: Any],
        previousResources: [String: Data],
        workingDir: URL
    ) throws {
        let providerCapabilityPrefixes = ["proxy-provider.", "rule-provider."]
        var references = (latest.externalResources ?? []).filter { reference in
            !providerCapabilityPrefixes.contains(where: reference.capabilityID.hasPrefix)
        }
        var resources: [String: Data] = [:]
        for reference in references {
            guard let data = previousResources[reference.storageKey] else {
                throw ProfileExternalResourceError.storedResourceMissing(
                    field: reference.fieldPath.joined(separator: ".")
                )
            }
            resources[reference.storageKey] = data
        }

        let requirements = IOSExternalResourceCatalog.requirements(root: root).filter {
            $0.capability.section == .proxyProvider
                || $0.capability.section == .ruleProvider
        }
        for requirement in requirements {
            let kind: ProfileProviderKind = requirement.capability.section == .proxyProvider
                ? .proxy : .rule
            let reference = ProfileExternalResourceImporter.reference(
                profileID: latest.id,
                requirement: requirement
            )
            let data: Data
            if let selected = draft.managedFile(for: requirement.proxyName, kind: kind) {
                let selectedName = selected.fileName.lowercased()
                let requiredName = requirement.rawValue
                    .replacingOccurrences(of: "\\", with: "/")
                    .split(separator: "/")
                    .last
                    .map(String.init)?.lowercased() ?? ""
                guard selectedName == requiredName else {
                    throw ProfileProviderDefinitionError.missingManagedFile
                }
                data = selected.data
            } else if (latest.externalResources ?? []).contains(reference),
                      let existing = previousResources[reference.storageKey] {
                data = existing
            } else {
                throw ProfileProviderDefinitionError.missingManagedFile
            }
            references.append(reference)
            resources[reference.storageKey] = data
        }
        updated.externalResources = references.isEmpty
            ? nil : Array(Set(references)).sorted { $0.storageKey < $1.storageKey }

        try ProfileExternalResourceStore.replace(
            resources,
            profileID: latest.id,
            coreHomeDir: workingDir
        )
    }

    private func providerDefinitionsBaseline(for profile: Profile) throws -> String {
        guard let raw = runtimeSourceYAML(for: profile) else {
            throw ProfileResourceSummaryError.sourceUnavailable
        }
        return try Self.providerDefinitionsBaseline(raw: raw, profile: profile)
    }

     
     
    nonisolated private static func providerDefinitionsBaseline(raw: String, profile: Profile) throws -> String {
        do {
            return try ProfileRuntimeConfigBuilder.buildProduction(
                raw: raw,
                profile: profile,
                applyProviderDefinitions: false, scripts: .surfaced
            )
        } catch {
             
             
             
             
             
            throw ProfileProviderDefinitionError.buildRefused(
                error.localizedDescription
            )
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func updateGlobalConfiguration(
        _ candidate: Profile,
        replacing keys: Set<String>,
        configureSpec: ((inout OverrideSpec) -> Void)? = nil,
        runtimeAlreadyCarriesChange: Bool = false,
        publicationStands: Bool = false
    ) throws {
        try withProfileLock {
            guard let profileStore else {
                throw PipelineError.sourceUnavailable(
                    "the shared profile store is unavailable"
                )
            }
            let previousProfiles = profileStore.load()
            guard let candidateIndex = previousProfiles.firstIndex(
                where: { $0.id == candidate.id }
            ) else {
                throw PipelineError.sourceUnavailable(
                    "the profile is no longer available"
                )
            }

            let previousRuntime = FlClashRuntimeConfig.load(
                from: runtimeDefaults
            )
            var updatedRuntime = FlClashRuntimeConfig.replacingGlobalFields(
                in: previousRuntime,
                with: candidate.override.patchJSON,
                keys: keys
            )
            configureSpec?(&updatedRuntime)
            let sanitizedCandidate = FlClashRuntimeConfig.sanitizedProfile(
                candidate
            )
            var updatedProfiles = previousProfiles
            updatedProfiles[candidateIndex] = sanitizedCandidate

            do {
                try profileStore.save(updatedProfiles)
                FlClashRuntimeConfig.save(
                    updatedRuntime,
                    in: runtimeDefaults
                )
                guard FlClashRuntimeConfig.load(
                    from: runtimeDefaults
                ) == updatedRuntime else {
                    throw PipelineError.preflightFailed(
                        "the app-wide runtime preference could not be persisted"
                    )
                }
            } catch {
                try? profileStore.save(previousProfiles)
                FlClashRuntimeConfig.save(
                    previousRuntime,
                    in: runtimeDefaults
                )
                recordFailure(
                    error,
                    context: .activation,
                    operation: .activation(candidate.id),
                    preservesLastKnownGood: true
                )
                throw error
            }

            statusMessage = "Runtime settings saved for all profiles"
            clearFailure()
             
             
            afterTheHold { [weak self] in
                self?.restageAfterGlobalSave(runtimeAlreadyCarriesChange: runtimeAlreadyCarriesChange,
                                             publicationStands: publicationStands)
            }
        }
    }

     
     
     
    private func restageAfterGlobalSave(runtimeAlreadyCarriesChange: Bool, publicationStands: Bool = false) {
        load()

        guard let activeProfileID,
              let active = profiles.first(
                  where: { $0.id == activeProfileID }
              ) else {
            return
        }
        switch ProfileSettingsRestagePolicy.action(
            profileID: active.id,
            activeProfileID: activeProfileID,
            vpnStatus: vpn.status,
            runtimeAlreadyCarriesChange: runtimeAlreadyCarriesChange
        ) {
        case .persistOnly:
            break
        case .restageOnly where publicationStands
            && vpn.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "connecting":
             
             
             
             
             
            ClashLogStore.shared.append(#"mode changed  publication kept"#, stream: .app)
        case .restageOnly:
             
             
             
             
            let carried = runtimeAlreadyCarriesChange && ProfileSettingsRestagePolicy.action(
                profileID: active.id, activeProfileID: activeProfileID, vpnStatus: vpn.status
            ) == .restageAndApply
            startActivation(
                active,
                applyToTunnel: false,
                preferCachedSource: true,
                runtimeCarriesChange: carried,
                inBackground: true,
                because: ClashPerf.Reason.globalConfiguration
            )
        case .restageAndApply:
            startActivation(
                active,
                applyToTunnel: true,
                preferCachedSource: true
            )
        }
    }

     
     
     
     
    private var profileLockDepth = 0
    private var afterProfileLock: [() -> Void] = []

     
     
     
     
     
    private func withProfileLock<T>(_ body: () throws -> T) rethrows -> T {
        profileLockDepth += 1
        defer {
            profileLockDepth -= 1
            if profileLockDepth == 0, !afterProfileLock.isEmpty {
                let pending = afterProfileLock
                afterProfileLock = []
                pending.forEach { $0() }
            }
        }
        return try ProfileStore.withWriteLock(body)
    }

     
    private func afterTheHold(_ work: @escaping () -> Void) {
        if profileLockDepth > 0 { afterProfileLock.append(work) } else { work() }
    }

    private func updateConfiguration(_ profile: Profile) throws {
        let funnelBegan = DispatchTime.now().uptimeNanoseconds
        defer {
            ClashPerf.span(
                "save.updateConfiguration",
                milliseconds: Double(
                    DispatchTime.now().uptimeNanoseconds - funnelBegan
                ) / 1_000_000,
                detail: "profile=\(profile.id)"
            )
        }
        guard let profileStore else {
            throw PipelineError.sourceUnavailable("the shared profile store is unavailable")
        }
        do {
            try profileStore.upsert(profile)
            statusMessage = .format("%@ saved", [profile.label])
            clearFailure()
        } catch {
            recordFailure(
                error,
                context: .localImport,
                operation: nil,
                preservesLastKnownGood: true
            )
            throw error
        }
        afterTheHold { [weak self] in
            guard let self else { return }
            self.load()
            self.notePublished([profile.id])
             
             
             
             
             
             
            self.restageIfActive(profile.id)
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func updateEdited(
        _ profile: Profile,
        sourceYAML: String?,
        resourceFiles: [ExternalResourceImportFile] = [],
        disablingAutoUpdate: Bool = false
    ) async throws {
        guard let profileStore, let workingDir else { return }
        if let sourceYAML, let library = configurationLibraryStore {
            let snapshot = try await Task.detached { try library.snapshot() }.value
            if let recipe = snapshot.recipes.first(where: { $0.id == profile.id }), recipe.preservesOriginal != true {
                await settleLibraryHousekeeping()
                guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
                changingConfigurationLibrary = true
                defer { changingConfigurationLibrary = false }
                 
                 
                 
                 
                 
                let running = ProfileSourceStore.runnableURL(workingDirectory: workingDir, profileID: profile.id)
                if resourceFiles.isEmpty, let settingsOnly = try await Task.detached(priority: .userInitiated, operation: {
                    () throws -> PreparedConfigurationSourceUpdate? in
                    guard let text = try? String(contentsOf: running, encoding: .utf8),
                          let loaded = try? OrderedJSON.parse(ConfigTransforms.validatedJSON(text)),
                          let edited = try? OrderedJSON.parse(ConfigTransforms.validatedJSON(sourceYAML)) else { return nil }
                     
                     
                     
                    do {
                        return try library.prepareComposedSourceSettingsEditing(profile.id, running: loaded, edited: edited,
                            expectedGeneration: snapshot.generation, resolveInput: ConfigurationCenterSourceBridge.boundInput)
                    } catch ConfigurationLibraryError.staleGeneration {
                        throw ConfigurationLibraryError.staleGeneration
                    } catch ConfigurationLibraryError.busy {
                        throw ConfigurationLibraryError.busy
                    } catch {
                        return nil
                    }
                }).value {
                    try await saveConfigurationPlan(candidate: settingsOnly.candidate, payloads: settingsOnly.payloads,
                        compositions: settingsOnly.compositions, generation: snapshot.generation)
                    return
                }
                 
                 
                 
                let prepared = try await Task.detached(priority: .userInitiated) {
                    let files = try ConfigurationCenterSourceBridge.capturedFiles(profile: profile, yaml: sourceYAML, workingDir: workingDir)
                    let replacement = try ConfigurationCenterSourceBridge.payload(label: profile.label,
                        origin: .file(profile.label + ".yaml"), original: Data(sourceYAML.utf8), yaml: sourceYAML,
                        resources: files + resourceFiles, id: "edited-" + UUID().uuidString)
                    return try library.prepareWholeSourceEditing(profile.id, replacement: replacement,
                        expectedGeneration: snapshot.generation, resolveInput: ConfigurationCenterSourceBridge.boundInput)
                }.value
                try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
                    compositions: [profile.id: prepared.composition], generation: snapshot.generation)
                return
            }
            if let recipe = snapshot.recipes.first(where: { $0.id == profile.id }), recipe.preservesOriginal == true {
                await settleLibraryHousekeeping()
                guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
                changingConfigurationLibrary = true
                defer { changingConfigurationLibrary = false }
                let prepared = try await Task.detached {
                    () throws -> (candidate: ConfigurationLibrarySnapshot, payloads: [ConfigurationSourcePayload],
                                  compositions: [String: ConfigurationComposition]) in
                    let previous = try library.payload(recipe.ruleSource)
                    if case .subscription = previous.record.origin {
                         
                         
                         
                         
                         
                         
                         
                        let copied = try ConfigurationCenterSourceBridge.payload(label: profile.label,
                            origin: .file(profile.label + ".yaml"), original: Data(sourceYAML.utf8), yaml: sourceYAML,
                            resources: resourceFiles, id: "edited-" + UUID().uuidString)
                        let copy = resourceFiles.isEmpty
                            ? ConfigurationSourcePayload(record: copied.record, original: copied.original,
                                                         documentJSON: copied.documentJSON, resourceFiles: previous.resourceFiles)
                            : copied
                        let made = try library.prepareOwnSourceCopy(profile.id, replacement: copy,
                            expectedGeneration: snapshot.generation, resolveInput: ConfigurationCenterSourceBridge.boundInput)
                        return (made.candidate, made.payloads, [profile.id: made.composition])
                    }
                    var replacement = try ConfigurationCenterSourceBridge.payload(label: profile.label,
                        origin: previous.record.origin, original: Data(sourceYAML.utf8), yaml: sourceYAML,
                        resources: resourceFiles, id: previous.record.id)
                    replacement.record.registersSuppliedRules = true
                    replacement.record.updateIntervalHours = previous.record.updateIntervalHours
                    replacement.record.userAgent = previous.record.userAgent
                    replacement.record.dnsOverHTTPS = previous.record.dnsOverHTTPS
                    if resourceFiles.isEmpty {
                        replacement = .init(record: replacement.record, original: replacement.original,
                            documentJSON: replacement.documentJSON, resourceFiles: previous.resourceFiles)
                    }
                    let updated = try library.prepareSourceUpdate(replacement, expectedGeneration: snapshot.generation,
                        updatingPinnedConsumers: true, resolveInput: ConfigurationCenterSourceBridge.boundInput)
                    return (updated.candidate, updated.payloads, updated.compositions)
                }.value
                try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
                    compositions: prepared.compositions, generation: snapshot.generation)
                return
            }
        }
         
         
         
         
         
         
        let gone = PipelineError.sourceUnavailable("the profile is no longer available")
        guard let sourceYAML else {
            if disablingAutoUpdate {
                try profileStore.updateIfPresent(id: profile.id) { current in
                    if case .url = current.source { current.autoUpdate = false }
                }
            }
            load()
            notePublished([profile.id])
            return
        }
         
         
         
        for _ in 0..<3 {
            guard let latest = profileStore.load().first(where: { $0.id == profile.id }) else { throw gone }
            let latestResources = externalResourceData(for: latest)
             
             
             
             
             
             
             
            let hydrated = sourceYAML
            let resourceSource = externalResourceSource(latest.source)
            let prepared = try await Task
                .detached(priority: .userInitiated) {
                     
                     
                    try ConfigTransforms.validateSource(hydrated)
                    let prepared = try ProfileExternalResourceImporter.prepare(
                        yaml: hydrated,
                        profileID: latest.id,
                        source: resourceSource,
                        files: resourceFiles,
                        existingReferences: latest.externalResources ?? [],
                        existingPublicResources: latestResources
                    )
                     
                     
                     
                     
                     
                    _ = try ProfileRuntimeConfigBuilder.runtimePreview(
                        raw: prepared.yaml,
                        profile: latest, scripts: .surfaced
                    )
                    return prepared
                }.value
             
             
             
             
             
            let wrote: Bool = try withProfileLock {
                guard let now = profileStore.load().first(where: { $0.id == latest.id }) else { throw gone }
                guard now == latest else { return false }
                 
                 
                let previousSource = sidecarYAML(for: now)
                let previousResources = externalResourceData(for: now)
                var updated = now
                do {
                    try ProfileExternalResourceStore.replace(
                        prepared.publicResources,
                        profileID: now.id,
                        coreHomeDir: workingDir
                    )
                    updated.externalResources = prepared.references.isEmpty
                        ? nil : prepared.references
                    updated.usesLocalSourceOverride = true
                    if disablingAutoUpdate, case .url = updated.source {
                        updated.autoUpdate = false
                    }
                     
                     
                     
                     
                     
                     
                     
                     
                    try profileStore.upsert(updated)
                     
                    try cacheSourceYAML(prepared.yaml, for: updated)
                } catch {
                    try? profileStore.upsert(now)
                    try? ProfileExternalResourceStore.replace(
                        previousResources,
                        profileID: now.id,
                        coreHomeDir: workingDir
                    )
                    restoreSourceYAML(previousSource, for: now)
                    throw error
                }
                return true
            }
            if wrote {
                load()
                notePublished([profile.id])
                 
                 
                 
                 
                 
                restageIfActive(latest.id)
                return
            }
        }
        throw gone

    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func baseYAML(for profile: Profile) -> String? {
        let key = projectionKey(for: profile)
        if let cached = baseYAMLCache[profile.id], cached.key == key {
            return cached.value
        }
        let value = RunningCoreDeviations.baseDocument(
            profile: profile,
            sidecarYAML: sourceYAML(for: profile)
        ) ?? uiProjectedYAML(for: profile)
        baseYAMLCache[profile.id] = (key, value)
        return value
    }

     
     
    struct CachedDocument: Equatable {
        let value: String?
    }

     
     
    func cachedBaseYAML(for profile: Profile) -> CachedDocument? {
        guard let cached = baseYAMLCache[profile.id], cached.key == projectionKey(for: profile) else { return nil }
        return CachedDocument(value: cached.value)
    }

     
     
     
     
    func loadBaseYAML(for profile: Profile) async -> String? {
        if let cached = cachedBaseYAML(for: profile) { return cached.value }
        let key = projectionKey(for: profile)
        let source = await loadSourceYAML(for: profile)
        let value = await Task.detached(priority: .userInitiated) {
            RunningCoreDeviations.baseDocument(profile: profile, sidecarYAML: source)
                ?? CustomNodesGroupMaterializer.projectForUI(sourceYAML: source, profile: profile)
        }.value
        if projectionKey(for: profile) == key { baseYAMLCache[profile.id] = (key, value) }
        return value
    }

     
     
     
    func cachedUIProjectedYAML(for profile: Profile) -> String? {
        let key = projectionKey(for: profile)
        if let cached = projectedYAMLCache[profile.id], cached.key == key {
            return cached.value
        }
        return nil
    }

     
     
     
     
    func uiProjectionInputs(for profile: Profile) -> (key: String, sourceYAML: String?) {
        (projectionKey(for: profile), sourceYAML(for: profile))
    }

     
     
    func rememberUIProjectedYAML(_ value: String?, key: String, for profile: Profile) {
        projectedYAMLCache[profile.id] = (key, value)
    }

     
     
     
     
     
     
     
     
    func loadUIProjectedYAML(for profile: Profile) async -> String? {
        if let cached = cachedUIProjectedYAML(for: profile) { return cached }
        let key = projectionKey(for: profile)
        let source = await loadSourceYAML(for: profile)
        let value = await Task.detached(priority: .userInitiated) {
            CustomNodesGroupMaterializer.projectForUI(
                sourceYAML: source,
                profile: profile
            )
        }.value
        rememberUIProjectedYAML(value, key: key, for: profile)
        return value
    }

     
     
     
     
    func loadPresentedProxiesYAML(for profile: Profile) async -> String? {
         
         
         
         
        if hasLargeSource(profile), let url = sidecarURL(for: profile), await sourceHasLargeRules(profile, at: url),
           let leaving = await loadPresentedDocumentLeavingRules(for: profile, sourceAt: url) {
            return leaving
        }
        let scriptBody = ScriptLibrary.load().first { $0.id == profile.selectedScriptID }?.body
        let key = ProxiesPresentedDocument.key(projectionKey: projectionKey(for: profile), profile: profile, scriptBody: scriptBody)
        if let cached = presentedProxiesYAMLCache[profile.id], cached.key == key { return cached.value }
        let source = await loadSourceYAML(for: profile)
        let fallback = await loadUIProjectedYAML(for: profile)
        let value = await Task.detached(priority: .userInitiated) {
            ProxiesPresentedDocument.make(source: source, profile: profile, fallback: fallback)
        }.value
        presentedProxiesYAMLCache[profile.id] = (key, value)
        return value
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    nonisolated static func sourceIsTooLargeToReadWhole(_ profile: Profile, workingDir: URL?) -> Bool {
        guard let workingDir else { return false }
        return ConfigTransforms.isTooLargeToReadWhole(fileAt: workingDir.appendingPathComponent("store/\(profile.id)/source.yaml"))
    }

    func hasLargeSource(_ profile: Profile) -> Bool {
        if let cached = sourceYAMLCache[profile.id] {
            return (cached?.utf8.count ?? 0) > PublishedPresentation.largeSourceBytes
        }
        guard let url = sidecarURL(for: profile) else { return false }
        return PublishedPresentation.isLargeSource(fileAt: url)
    }

     
     
     
     
     
     
     
    func loadPagesYAML(for profile: Profile) async -> String? {
        if hasLargeSource(profile), let url = sidecarURL(for: profile) {
            let store = resourceStoreForHomeTally
            let working = workingDir
             
            if let published = await Task.detached(priority: .userInitiated, operation: {
                PublishedPresentation.textForPages(sourceAt: url, profile: profile, store: store,
                                                   workingDirectory: working)
            }).value {
                return published
            }
        }
         
        return await loadPresentedProxiesYAML(for: profile)
    }

     
     
    private func sourceHasLargeRules(_ profile: Profile, at url: URL) async -> Bool {
        let key = projectionKey(for: profile)
        if let known = largeRulesVerdicts[profile.id], known.key == key { return known.large }
        let large = await Task.detached(priority: .userInitiated) { ConfigTransforms.hasLargeRuleSection(fileAt: url) }.value
        largeRulesVerdicts[profile.id] = (key, large)
        return large
    }

     
     
     
     
     
    func loadPresentedDocumentLeavingRules(for profile: Profile, sourceAt url: URL) async -> String? {
        let scriptBody = ScriptLibrary.load().first { $0.id == profile.selectedScriptID }?.body
        let key = ProxiesPresentedDocument.key(projectionKey: projectionKey(for: profile), profile: profile,
                                               scriptBody: scriptBody) + "#rules-in-source"
        if let cached = presentedProxiesYAMLCache[profile.id], cached.key == key { return cached.value }
        let value = await Task.detached(priority: .userInitiated) { () -> String? in
            Self.presentedDocumentLeavingRules(sourceAt: url, profile: profile)
        }.value
        guard let value else { return nil }
        presentedProxiesYAMLCache[profile.id] = (key, value)
        return value
    }

     
     
     
     
    nonisolated static func presentedDocumentLeavingRules(sourceAt url: URL, profile: Profile,
                                                          marked: Bool = true) -> String? {
        guard let rest = PagesRuleSource.sourceLeavingLargeRules(at: url) else { return nil }


        let built = ProxiesPresentedDocument.make(source: rest, profile: profile, fallback: rest) ?? rest
        return marked ? PagesRuleSource.marking(built, rulesAt: url) : built
    }

    func uiProjectedYAML(for profile: Profile) -> String? {
        let key = projectionKey(for: profile)
        if let cached = projectedYAMLCache[profile.id], cached.key == key {
            return cached.value
        }
        let value = CustomNodesGroupMaterializer.projectForUI(
            sourceYAML: sourceYAML(for: profile),
            profile: profile
        )
        projectedYAMLCache[profile.id] = (key, value)
        return value
    }

     
     
     
     
     
     
     
     
     
     
     
    func effectiveYAML(for profile: Profile) -> String? {
        let key = effectiveYAMLKey(for: profile)
        if let cached = effectiveYAMLCache[profile.id], cached.key == key {
            return cached.value
        }
        let value = previewText(for: profile)
        effectiveYAMLCache[profile.id] = (key, value)
        return value
    }

     
     
     
    func loadEffectiveYAML(for profile: Profile) async -> String? {
        let key = effectiveYAMLKey(for: profile)
        if let cached = effectiveYAMLCache[profile.id], cached.key == key { return cached.value }
        let value = await previewTextOffTheMainActor(for: profile)
        if effectiveYAMLKey(for: profile) == key { effectiveYAMLCache[profile.id] = (key, value) }
        return value
    }

     
     
     
     
     
     
     
     
    func effectiveYAMLIfReady(for profile: Profile) -> String? {
        let key = effectiveYAMLKey(for: profile)
        if let cached = effectiveYAMLCache[profile.id], cached.key == key { return cached.value }
        guard effectiveYAMLBuilding.insert(key).inserted else { return nil }
        Task { [weak self] in
            guard let self else { return }
            _ = await self.loadEffectiveYAML(for: profile)
            self.effectiveYAMLBuilding.remove(key)
            self.objectWillChange.send()
        }
        return nil
    }

    private var effectiveYAMLBuilding: Set<String> = []

    private func effectiveYAMLKey(for profile: Profile) -> String {
        var parts = [projectionKey(for: profile)]
         
         
         
         
         
         
         
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        if let encoded = try? encoder.encode(FlClashRuntimeConfig.load()) {
            parts.append("\(encoded.hashValue)")
        }
        parts.append(profile.postMergeScriptID ?? "-")
        parts.append(ScriptSettings.enabled() ? "script" : "-")
        return parts.joined(separator: "|")
    }

    private func projectionKey(for profile: Profile) -> String {
        var parts: [String] = [profile.id]
        if let workingDir {
            let sidecar = workingDir
                .appendingPathComponent("store/\(profile.id)/source.yaml")
            let attributes = try? FileManager.default
                .attributesOfItem(atPath: sidecar.path)
            let size = (attributes?[.size] as? NSNumber)?.intValue ?? -1
            let modified = (attributes?[.modificationDate] as? Date)?
                .timeIntervalSince1970 ?? -1
            parts.append("\(size)|\(modified)")
             
             
             
            parts.append(profile.activeRevision ?? "-")
        }
        parts.append(profile.lastUpdatedAt.map { "\($0.timeIntervalSince1970)" } ?? "-")
        parts.append(profile.override.patchJSON ?? "-")
        if let definitions = profile.providerDefinitions,
           let encoded = try? JSONEncoder().encode(definitions) {
            parts.append("\(encoded.hashValue)")
        }
         
         
         
         
         
        parts.append(profile.sourceCredentialsRedacted == true ? "1" : "0")
        let references = (profile.sourceCredentials ?? [])
            + (profile.proxyCredentials ?? [])
        if !references.isEmpty,
           let encoded = try? JSONEncoder().encode(references) {
            parts.append("\(encoded.hashValue)")
             
             
             
             
            if profile.sourceCredentialsRedacted == true {
                parts.append("\(credentialFingerprint(for: references))")
            }
        }
         
         
         
        if let overrides = profile.proxyNodeOverrides,
           let encoded = try? JSONEncoder.sortedKeys.encode(overrides) {
            parts.append("o:\(encoded.count)|\(encoded.hashValue)")
        }
        if let chain = profile.proxyChain,
           let encoded = try? JSONEncoder.sortedKeys.encode(chain) {
            parts.append("c:\(encoded.count)|\(encoded.hashValue)")
        }
        return parts.joined(separator: "\u{1}")
    }

     
     
     
     
     
    private func credentialFingerprint(
        for references: [ProxyCredentialReference]
    ) -> Int {
        var hasher = Hasher()
        for key in references.map(\.key).sorted() {
            hasher.combine(key)
            hasher.combine(credentials.get(key) ?? Data())
        }
        return hasher.finalize()
    }

     
     
    @discardableResult
    func move(from source: IndexSet, to destination: Int) -> Error? {
        guard let profileStore else { return nil }
        profiles = ProfileReorder.apply(profiles, from: source, to: destination)
         
         
         
        let order = Dictionary(profiles.map { ($0.id, $0.order) }, uniquingKeysWith: { first, _ in first })
        var failure: Error?
        do {
            _ = try profileStore.updateAll { stored in
                 
                var next = order.count
                for index in stored.indices {
                    if let placed = order[stored[index].id] {
                        stored[index].order = placed
                    } else {
                        stored[index].order = next
                        next += 1
                    }
                }
            }
        } catch {
            failure = error
        }
        load()
        return failure
    }

     
    private var tunnelIsRunning: Bool {
        vpn.status == "connected" || vpn.status == "reasserting"
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func configurationLibrarySources(for profile: Profile) -> [String]? {
        guard let snapshot = try? configurationLibraryStore?.snapshot(),
              let recipe = snapshot.recipes.first(where: { $0.id == profile.id }) else { return nil }
        return Self.fetchableSources(of: recipe, in: snapshot)
    }

    private static func fetchableSources(of recipe: ConfigurationRecipe,
                                         in snapshot: ConfigurationLibrarySnapshot) -> [String] {
        var seen = Set<String>()
        return (recipe.sources + [recipe.ruleSource]).compactMap { reference -> String? in
            guard seen.insert(reference.id).inserted,
                  let record = snapshot.sources.first(where: { $0.id == reference.id }),
                  case .subscription = record.origin, record.isRetainedSnapshot != true else { return nil }
            return reference.id
        }
    }

     
     
    private struct LibraryConfigurationEntry {
        let profile: Profile
        let sources: [String]
    }

     
     
     
     
     
     
    private struct UpdateAllPlan {
        var legacy: [Profile] = []
        var configurations: [LibraryConfigurationEntry] = []
        var sources: [ConfigurationSourceRecord] = []
        var count: Int { legacy.count + configurations.count }
    }

    private func planUpdateAll() -> UpdateAllPlan {
        var plan = UpdateAllPlan()
        let snapshot = (try? configurationLibraryStore?.snapshot()) ?? nil
        var seen = Set<String>()
        for profile in profiles {
            if let snapshot, let recipe = snapshot.recipes.first(where: { $0.id == profile.id }) {
                let ids = Self.fetchableSources(of: recipe, in: snapshot)
                guard !ids.isEmpty else { continue }
                plan.configurations.append(.init(profile: profile, sources: ids))
                for id in ids where seen.insert(id).inserted {
                    if let record = snapshot.sources.first(where: { $0.id == id }) { plan.sources.append(record) }
                }
            } else if case .url = profile.source {
                plan.legacy.append(profile)
            }
        }
        return plan
    }

     
     
    struct ConfigurationSourceRefresh {
        var changed: [String] = []
         
         
         
         
         
         
         
         
        var failures: [ProviderDownloadFailure] = []
    }

     
     
     
     
     
     
     
     
     
    func refreshConfigurationSources(_ references: [String]) async throws -> ConfigurationSourceRefresh {
         
         
        let before = (try? configurationLibraryStore?.snapshot()) ?? nil
        let records = Dictionary(uniqueKeysWithValues: (before?.sources ?? []).map { ($0.id, $0) })
        let versions = records.mapValues(\.version)
        var outcome = ConfigurationSourceRefresh()
        for reference in references {
            do {
                try await refreshConfigurationSource(reference)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let record = records[reference]
                var link: String?
                if case let .subscription(url)? = record?.origin { link = url }
                outcome.failures.append(.init(provider: record?.label ?? reference, url: link, underlying: error))
            }
        }
        let after = (try? configurationLibraryStore?.snapshot()) ?? nil
        outcome.changed = references.filter { reference in
            guard let now = after?.sources.first(where: { $0.id == reference })?.version else { return false }
            return versions[reference] != now
        }
        return outcome
    }

     
     
     
     
     
     
     
     
     
    @MainActor
     
    enum SyncOutcome: Equatable {
        case changed
        case unchanged
        case failed
    }

    @discardableResult
    private func runLibrarySync(_ profile: Profile, references: [String]) async -> SyncOutcome {
         
         
         
        defer { if busyProfileID == profile.id { busyProfileID = nil } }
        do {
            let outcome = try await refreshConfigurationSources(references)
             
             
            load()
             
             
            busyProfileID = nil
            await restageAfterSourceRefresh(profile.id, changed: outcome.changed)
             
             
             
            if outcome.failures.isEmpty {
                 
                 
                 
                 
                 
                statusMessage = outcome.changed.isEmpty
                    ? .format("%@ is up to date", [profile.label])
                    : .format("%@ synced", [profile.label])
                clearFailure()
                return outcome.changed.isEmpty ? .unchanged : .changed
            } else {
                recordFailure(ProviderDownloadFailuresError(failures: outcome.failures),
                              context: .subscription, operation: nil, preservesLastKnownGood: true)
                return .failed
            }
        } catch {
            recordFailure(error, context: .subscription, operation: nil, preservesLastKnownGood: true)
            return .failed
        }
    }

     
     
     
     
    @MainActor
    private func syncWithoutLibraryBranch(_ profile: Profile) {
        sync(profile)
    }

     
     
     
     
     
     
     
    @MainActor
    @discardableResult
    func syncAwaitingLibrary(_ profile: Profile) async -> SyncOutcome? {
         
         
         
         
        guard let references = configurationLibrarySources(for: profile),
              !references.isEmpty, busyProfileID == nil else {
            syncWithoutLibraryBranch(profile)
            return nil
        }
        busyProfileID = profile.id
        clearFailure()
        statusMessage = .format("Syncing %@…", [profile.label])
        return await runLibrarySync(profile, references: references)
    }

     
     
     
     
    private func restageAfterSourceRefresh(_ profileID: String, changed: [String]) async {
        guard !changed.isEmpty, profileID == activeProfileID, tunnelIsRunning,
              let latest = profiles.first(where: { $0.id == profileID }) else { return }
        startActivation(latest, applyToTunnel: true, preferCachedSource: true,
                        because: ClashPerf.Reason.profileSync)
        await waitForPendingActivation()
    }

     
     
     
    func sync(_ profile: Profile) {
         
         
         
         
         
         
         
         
         
         
         
         
        if let references = configurationLibrarySources(for: profile) {
             
             
             
            guard !references.isEmpty else { return }
             
             
             
             
             
            guard busyProfileID == nil else {
                 
                 
                 
                 
                if let busy = busyProfileID, busy != profile.id {
                    let label = profiles.first(where: { $0.id == busy })?.label ?? busy
                    statusMessage = .format("%@ is still updating — try again when it finishes.", [label])
                }
                return
            }
            busyProfileID = profile.id
            clearFailure()
            statusMessage = .format("Syncing %@…", [profile.label])
            Task { [weak self] in
                await self?.runLibrarySync(profile, references: references)
            }
            return
        }
        if profile.id == activeProfileID {
             
             
             
             
             
             
             
             
             
             
             
            startActivation(profile, applyToTunnel: tunnelIsRunning, fetchesFresh: true,
                            because: ClashPerf.Reason.profileSync)
            return
        }
        guard case .url = profile.source else { return }
        clearFailure()
        statusMessage = .format("Syncing %@…", [profile.label])
        Task { [weak self] in
            guard let self else { return }
            let subscriptions = SubscriptionManager(
                downloader: self.downloader, credentials: self.credentials)
            do {
                guard let profileStore = self.profileStore,
                      let workingDir = self.workingDir else {
                    throw PipelineError.sourceUnavailable(
                        "the shared profile store is unavailable"
                    )
                }
                let result = try await SubscriptionSourceRefresher.refresh(
                    profile: profile,
                    manager: subscriptions,
                    profileStore: profileStore,
                    credentials: self.credentials,
                    workingDirectory: workingDir,
                     
                     
                    conditional: false,
                     
                     
                    scripts: .surfaced
                )
                self.load()
                let heldBack = self.profiles.first(where: { $0.id == profile.id })?.suppressedUpdates?.count ?? 0
                self.statusMessage = result == .unchanged
                    ? .format("%@ is up to date", [profile.label])
                    : heldBack > 0
                        ? .format("%@ synced · %@ change(s) held back by your settings", [profile.label, String(heldBack)])
                        : .format("%@ synced", [profile.label])
                self.clearFailure()
            } catch {
                self.recordFailure(
                    error,
                    context: .subscription,
                    operation: .sync(profile.id)
                )
            }
        }
    }

     
     
     
     
     
     
    static func subscriptionProfiles(in profiles: [Profile]) -> [Profile] {
        profiles.filter {
            if case .url = $0.source { return true }
            return false
        }
    }

     
    var hasSubscriptionProfile: Bool {
        !Self.subscriptionProfiles(in: profiles).isEmpty
    }

     
     
    var isSyncingAll: Bool { batchTask != nil }

     
     
     
    func syncAllAndWait() async {
        if let running = batchTask, !batchTaskIsWhole {
             
            await running.value
             
             
             
            if batchReport == nil || batchReport?.wasCancelled == true || Task.isCancelled { return }
        }
        syncAll()
        await batchTask?.value
    }

    func syncAll() {
        guard batchTask == nil else { return }
        let plan = planUpdateAll()
        let candidates = plan.legacy
        batchReport = BatchUpdateReport(
            title: "Profile Sync",
            expectedCount: plan.count
        )
        guard plan.count > 0 else { return }
        isBatchSyncing = true
        clearFailure()
        let runID = UUID()
        batchRunID = runID
        batchTaskIsWhole = true
        batchTask = Task { [weak self] in
            guard let self else { return }
            for profile in candidates {
                guard self.batchRunID == runID else { return }
                if Task.isCancelled {
                    self.markBatchCancelled()
                    break
                }
                self.busyProfileID = profile.id
                self.statusMessage = .format("Syncing %@…", [profile.label])
                do {
                     
                     
                     
                     
                     
                    let state = try await withThrowingTaskGroup(
                        of: BatchUpdateState.self
                    ) { group in
                         
                         
                        group.addTask { try await self.performBatchSync(profile, scripts: .silent) }
                        group.addTask {
                            try await Task.sleep(
                                nanoseconds: UInt64(Self.batchItemLimit * 1_000_000_000)
                            )
                            throw URLError(.timedOut)
                        }
                        defer { group.cancelAll() }
                        guard let first = try await group.next() else {
                            throw URLError(.timedOut)
                        }
                        return first
                    }
                    guard self.batchRunID == runID else { return }
                    self.recordBatchItem(
                        id: profile.id,
                        label: profile.label,
                        state: state,
                        message: state == .unchanged
                            ? "Already up to date."
                            : "The validated source was saved."
                    )
                } catch is CancellationError {
                    guard self.batchRunID == runID else { return }
                    self.markBatchCancelled()
                    break
                } catch {
                    guard self.batchRunID == runID else { return }
                    self.recordBatchFailure(error, profile: profile)
                }
                self.busyProfileID = nil
                self.load()
            }
             
             
             
             
            if !plan.sources.isEmpty {
                let before = (try? self.configurationLibraryStore?.snapshot()) ?? nil
                let versions = Dictionary(uniqueKeysWithValues: (before?.sources ?? []).map { ($0.id, $0.version) })
                var failures: [String: ProviderDownloadFailure] = [:]
                var cancelled = false
                for source in plan.sources {
                    guard self.batchRunID == runID else { return }
                    if Task.isCancelled { self.markBatchCancelled(); cancelled = true; break }
                    self.statusMessage = ClashConfigurationSourceCopy.sentence("Syncing %@…", naming: source)
                    do {
                        try await withThrowingTaskGroup(of: Void.self) { group in
                            group.addTask { _ = try await self.refreshConfigurationSource(source.id) }
                            group.addTask {
                                try await Task.sleep(nanoseconds: UInt64(Self.batchItemLimit * 1_000_000_000))
                                throw URLError(.timedOut)
                            }
                            defer { group.cancelAll() }
                            try await group.next()
                        }
                    } catch is CancellationError {
                        guard self.batchRunID == runID else { return }
                        self.markBatchCancelled(); cancelled = true; break
                    } catch {
                        var link: String?
                        if case let .subscription(url) = source.origin { link = url }
                        failures[source.id] = .init(provider: source.label, url: link, underlying: error)
                    }
                }
                guard self.batchRunID == runID else { return }
                 
                 
                self.load()
                let after = (try? self.configurationLibraryStore?.snapshot()) ?? nil
                let changed = Set(plan.sources.map(\.id).filter { id in
                    guard let now = after?.sources.first(where: { $0.id == id })?.version else { return false }
                    return versions[id] != now
                })
                if let activeProfileID = self.activeProfileID,
                   let active = plan.configurations.first(where: { $0.profile.id == activeProfileID }) {
                    await self.restageAfterSourceRefresh(activeProfileID, changed: active.sources.filter(changed.contains))
                }
                guard self.batchRunID == runID else { return }
                if !cancelled {
                    for entry in plan.configurations {
                        let failed = entry.sources.compactMap { failures[$0] }
                        if !failed.isEmpty {
                            self.recordBatchFailure(ProviderDownloadFailuresError(failures: failed), profile: entry.profile)
                        } else if entry.sources.contains(where: changed.contains) {
                            self.recordBatchItem(id: entry.profile.id, label: entry.profile.label,
                                                 state: .updated, message: "The validated source was saved.")
                        } else {
                            self.recordBatchItem(id: entry.profile.id, label: entry.profile.label,
                                                 state: .unchanged, message: "Already up to date.")
                        }
                    }
                }
            }
            guard self.batchRunID == runID else { return }
            self.busyProfileID = nil
            self.isBatchSyncing = false
            self.batchRunID = nil
            self.batchTask = nil
            self.load()
            if let report = self.batchReport {
                 
                 
                 
                 
                 
                self.statusMessage = report.wasCancelled
                    ? "Profile sync cancelled"
                    : "Profile sync finished"
            }
        }
    }

     
     
     
     
    func refreshLegacyProfileAwaiting(_ profile: Profile) async throws -> BatchUpdateState {
        busyProfileID = profile.id
        defer { busyProfileID = nil; load() }
        return try await withThrowingTaskGroup(of: BatchUpdateState.self) { group in
            group.addTask { try await self.performBatchSync(profile, scripts: .silent) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(Self.batchItemLimit * 1_000_000_000))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw URLError(.timedOut) }
            return first
        }
    }

    func cancelBatchSync() {
        guard let task = batchTask else { return }
         
         
         
         
         
         
        batchRunID = nil
        batchTask = nil
        task.cancel()
        busyProfileID = nil
        isBatchSyncing = false
        markBatchCancelled()
        statusMessage = "Profile sync cancelled"
    }

    func dismissBatchReport() {
         
         
         
         
        if isBatchSyncing {
            cancelBatchSync()
        }
        batchReport = nil
    }

    func retryBatchItem(id: String) {
        guard batchTask == nil,
              let profile = profiles.first(where: { $0.id == id }) else { return }
        isBatchSyncing = true
        let runID = UUID()
        batchRunID = runID
        batchTaskIsWhole = false
        batchTask = Task { [weak self] in
            guard let self else { return }
            self.busyProfileID = profile.id
            do {
                 
                 
                let state = try await self.performBatchSync(profile, scripts: .surfaced)
                guard self.batchRunID == runID else { return }
                self.recordBatchItem(
                    id: profile.id,
                    label: profile.label,
                    state: state,
                    message: state == .unchanged
                        ? "Already up to date."
                        : "The validated source was saved."
                )
            } catch is CancellationError {
                guard self.batchRunID == runID else { return }
                self.markBatchCancelled()
            } catch {
                guard self.batchRunID == runID else { return }
                self.recordBatchFailure(error, profile: profile)
            }
            guard self.batchRunID == runID else { return }
            self.busyProfileID = nil
            self.isBatchSyncing = false
            self.batchRunID = nil
            self.batchTask = nil
            self.load()
            self.drainPendingActivation()
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    private func performBatchSync(_ profile: Profile, scripts: ScriptEngine.Caller) async throws -> BatchUpdateState {
        try Task.checkCancellation()

         
         
         
         
         
        if let references = configurationLibrarySources(for: profile) {
            guard !references.isEmpty else { return .unchanged }
            let outcome = try await refreshConfigurationSources(references)
             
             
             
            load()
            await restageAfterSourceRefresh(profile.id, changed: outcome.changed)
            guard outcome.failures.isEmpty else {
                throw ProviderDownloadFailuresError(failures: outcome.failures)
            }
            return outcome.changed.isEmpty ? .unchanged : .updated
        }

        let subscriptions = SubscriptionManager(
            downloader: downloader,
            credentials: credentials
        )
        guard let profileStore, let workingDir else {
            throw PipelineError.sourceUnavailable("the shared profile store is unavailable")
        }
        let result = try await SubscriptionSourceRefresher.refresh(
            profile: profile,
            manager: subscriptions,
            profileStore: profileStore,
            credentials: credentials,
            workingDirectory: workingDir,
             
            conditional: false,
            scripts: scripts
        )
        let state: BatchUpdateState = result == .unchanged ? .unchanged : .updated

        if state == .updated, profile.id == activeProfileID, tunnelIsRunning {
            try await republishToRunningTunnel(profile)
        }
        return state
    }

     
     
     
     
     
     
    private func republishToRunningTunnel(_ profile: Profile) async throws {
        guard let container,
              let store = try? ConfigResourceStore(containerURL: container) else {
            throw PipelineError.sourceUnavailable(
                "the shared configuration store is unavailable"
            )
        }
        let coordinator = try vpn.activationCoordinator(store: store, container: container)
        let owed = workingDir.flatMap { RecoveryRebuilds.token(for: profile.id, workingDir: $0) }
        let sourceYAML = try storedSourceYAML(for: profile, preferCachedSource: owed != nil)
        let (staged, stagedPreflight, stagedNotices) = try await Task.detached(priority: .userInitiated) {
            let pointer = try await coordinator.activate(profile: profile, sourceYAML: sourceYAML)
            return (pointer,
                    coordinator.lastPublicationPreflight.flatMap { $0.pointer == pointer ? $0.outcome : nil },
                    coordinator.lastPublicationNotices.flatMap { $0.pointer == pointer ? $0.notices : nil })
        }.value
        if let owed, sourceYAML != nil, let workingDir {
            RecoveryRebuilds.settle(profile.id, token: owed, workingDir: workingDir)
        }
         
         
         
         
         
         
         
        guard let preflight = try await Task.detached(priority: .userInitiated) { () throws -> ([String], PreflightOutcome)? in
            guard let activeYAML = try store.loadConfiguration(
                profileID: staged.profileID, revision: staged.revision
            ).text else { return nil }
            return (
                stagedNotices ?? ((try? ConfigTransforms.planResources(mergedYAML: activeYAML).notices) ?? []),
                stagedPreflight ?? PreflightService.intent(finalYAML: activeYAML, container: container)
            )
        }.value else { return }
        notices = preflight.0
        let outcome = preflight.1
        if let intentJSON = outcome.intentJSON,
           let intent = try? JSONDecoder().decode(
            PlatformConfigIntent.self,
            from: Data(intentJSON.utf8)
           ) {
            revisionHandedToTunnel = staged
            BackgroundRefresh.clearPendingHandover(staged)
             
             
            await vpn.applyActiveConfiguration(nextIntent: intent, startsWhenDown: false, publishedAs: staged)
        }
    }

    private func recordBatchFailure(_ error: Error, profile: Profile) {
        let context: ConfigurationFailureContext = profile.id == activeProfileID
            ? .activation : .subscription
        guard let failure = ConfigurationFailureClassifier.classify(
            error,
            context: context,
            preservesLastKnownGood: true
        ) else { return }
        recordBatchItem(
            id: profile.id,
            label: profile.label,
            state: .failed,
             
             
            message: nil,
            failure: failure
        )
    }

    private func recordBatchItem(
        id: String,
        label: String,
        state: BatchUpdateState,
        message: String?,
        failure: ConfigurationFailure? = nil
    ) {
        guard var report = batchReport else { return }
        report.wasCancelled = false
        report.record(BatchUpdateItem(
            id: id,
            label: label,
            state: state,
            message: message,
            failure: failure
        ))
        batchReport = report
    }

    private func markBatchCancelled() {
        guard var report = batchReport else { return }
        report.wasCancelled = true
        batchReport = report
    }

     
     
     
    func previewTextOffTheMainActor(for profile: Profile) async -> String? {
        let container = container
        let workingDir = workingDir
        let large = sidecarURL(for: profile).flatMap { url in hasLargeSource(profile) ? url : nil }
         
         
        return await Task.detached(priority: .userInitiated) { () -> String? in
            if let published = Self.publishedPreviewText(for: profile, container: container) { return published }
             
             
             
             
             
             
             
             
            if let large {
                if let rest = PagesRuleSource.sourceLeavingLargeRules(at: large) {
                    return PagesRuleSource.marking(rest, rulesAt: large)
                }
                if !ConfigTransforms.hasLargeRuleSection(fileAt: large),
                   let workingDir, let source = Self.sidecarYAML(for: profile, workingDir: workingDir) {
                    return try? ProfileRuntimeConfigBuilder.buildProduction(raw: source, profile: profile, scripts: .silent)
                }
                return LargeConfigurationDisplay.text(ofFileAt: large, containerPath: container?.path,
                                                      telling: { LargeConfigurationDisplay.phrase($0) })
            }
            guard let workingDir, let source = Self.sidecarYAML(for: profile, workingDir: workingDir) else { return nil }
            return try? ProfileRuntimeConfigBuilder.buildProduction(raw: source, profile: profile, scripts: .silent)
        }.value
    }

     
     
     
     
     
     
     
    func runtimeDisplayTextOffTheMainActor(for profile: Profile) async -> String? {
         
         
         
         
         
        if hasLargeSource(profile) {
            let url = sidecarURL(for: profile)
            let container = container
            return await Task.detached(priority: .userInitiated) {
                LargeConfigurationDisplay.text(for: profile, sourceAt: url, container: container)
            }.value
        }
        let text = await previewTextOffTheMainActor(for: profile)
        guard let text, Self.namesStorageInPlaceOfContent(text) else { return text }
         
        return await loadPresentedProxiesYAML(for: profile)
    }

     
     
     
    private func publishedPreview(for profile: Profile) -> String? {
        Self.publishedPreviewText(for: profile, container: container)
    }

     
     
     
     
    func publishedRuleSetsAndSubRules(for profile: Profile) async -> (ruleSets: Set<String>?, subRules: Set<String>?)? {
        let container = container
        return await Task.detached(priority: .userInitiated) {
            Self.publishedRuleSetsAndSubRules(for: profile, container: container)
        }.value
    }

     
     
    nonisolated static func publishedRuleSetsAndSubRules(
        for profile: Profile, container: URL? = ClashAppIdentifiers.appGroupContainer
    ) -> (ruleSets: Set<String>?, subRules: Set<String>?)? {
         
         
         
         
        guard let container, let store = try? ConfigResourceStore(containerURL: container),
              let pointer = store.activeIdentityOrNil(), pointer.profileID == profile.id else { return nil }
        let revision = pointer.revision
         
         
        if let url = store.publishedConfigurationURL(profileID: profile.id, revision: revision),
           let data = try? Data(contentsOf: url, options: .alwaysMapped),
           let declared = ProfileRuntimeConfigBuilder.declaredRuleSetsAndSubRules(inBytes: data, readersOwn: true) {
            return declared
        }
        guard let text = (try? store.loadConfiguration(profileID: profile.id, revision: revision))?.text else { return nil }
        return ProfileRuntimeConfigBuilder.declaredRuleSetsAndSubRules(in: text, readersOwn: true)
    }

     
     
     
    nonisolated static func publishedPreviewText(for profile: Profile, container: URL?) -> String? {
        guard let container, let revision = profile.activeRevision,
              let text = (try? ConfigResourceStore(containerURL: container)
                  .loadConfiguration(profileID: profile.id, revision: revision))?.text else { return nil }
        return PublishedPresentation.withModeChosen(PublishedRulesAsWritten.restoring(
            text, profileID: profile.id, revision: revision,
            workingDirectory: container.appendingPathComponent("working", isDirectory: true)))
    }

    func previewText(for profile: Profile) -> String? {
         
         
         
         
         
        if let published = publishedPreview(for: profile) { return published }
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        if hasLargeSource(profile), let url = sidecarURL(for: profile) {
            return LargeConfigurationDisplay.text(ofFileAt: url, containerPath: container?.path,
                                                  telling: { LargeConfigurationDisplay.phrase($0) })
        }
        guard let source = try? hydratedSourceYAML(for: profile) else {
            return sidecarYAML(for: profile)
        }
         
         
         
        return try? ProfileRuntimeConfigBuilder.buildProduction(raw: source, profile: profile, scripts: .silent)
    }

     
     
     
     
     
    func loadSavedConfigurationPreview(
        for profileID: String,
        build: @escaping (String, Profile) throws -> String = {
            try ProfileRuntimeConfigBuilder.buildProduction(raw: $0, profile: $1, scripts: .surfaced)
        }
    ) async throws -> String {
        guard let profile = profiles.first(where: { $0.id == profileID }),
              let workingDir else {
            throw PipelineError.sourceUnavailable("The saved configuration is unavailable.")
        }
         
         
        let large = hasLargeSource(profile) ? sidecarURL(for: profile) : nil
        let container = container
        return try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            if let large {
                guard let shown = LargeConfigurationDisplay.text(ofFileAt: large, containerPath: container?.path,
                                                                 telling: { LargeConfigurationDisplay.phrase($0) }) else {
                    throw PipelineError.sourceUnavailable("The saved configuration is unavailable.")
                }
                return shown
            }
             
             
            guard let source = Self.sidecarYAML(for: profile, workingDir: workingDir) else {
                throw PipelineError.sourceUnavailable("The saved configuration is unavailable.")
            }
            let text = try build(source, profile)
            try Task.checkCancellation()
            return text
        }.value
    }

     
     
    func loadAppliedConfigurationPreview(for profileID: String) async throws -> String? {
        guard let profile = profiles.first(where: { $0.id == profileID }),
              let container else { return nil }
        let large = hasLargeSource(profile) ? sidecarURL(for: profile) : nil
        return try await Task.detached(priority: .userInitiated) {
            let store = try ConfigResourceStore(containerURL: container)
             
             
            let active = try store.activeIdentity()
            guard let revision = active?.profileID == profileID
                ? active?.revision : profile.activeRevision else { return nil }
            guard let text = try store.loadConfiguration(profileID: profileID, revision: revision).text else { return nil }
             
            if large != nil {
                var shown = profile
                shown.activeRevision = revision
                return LargeConfigurationDisplay.text(for: shown, sourceAt: large, container: container)
            }
             
             
            return PublishedPresentation.withModeChosen(PublishedRulesAsWritten.restoring(
                text, profileID: profileID, revision: revision,
                workingDirectory: container.appendingPathComponent("working", isDirectory: true)))
        }.value
    }

     
     
    func loadCachedPreviewText(for profileID: String) async -> String? {
        try? await loadSavedConfigurationPreview(for: profileID)
    }


     
     
     
     
     
    func loadCachedExportDocument(for profileID: String) async -> (String, String)? {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return nil }
        let name = profile.label.isEmpty ? "profile" : profile.label
        guard let workingDir else { return capturedSourceText(for: profile).map { ("\(name).yaml", $0) } }
        let text = await Task.detached(priority: .userInitiated) {
            ProfileSourceStore.capturedText(workingDirectory: workingDir, profileID: profile.id)
                ?? Self.sidecarYAML(for: profile, workingDir: workingDir)
        }.value
        return text.map { ("\(name).yaml", $0) }
    }

     
     
    func exportDocument(for profile: Profile) -> (String, String)? {
        let name = profile.label.isEmpty ? "profile" : profile.label
        if let captured = capturedSourceText(for: profile) {
            return ("\(name).yaml", captured)
        }
         
         
        if hasLargeSource(profile), let source = try? hydratedSourceYAML(for: profile) {
            return ("\(name).yaml", source)
        }
        guard let text = previewText(for: profile) else { return nil }
         
         
         
         
        if Self.namesStorageInPlaceOfContent(text) {
            guard let source = try? hydratedSourceYAML(for: profile),
                  let built = try? ProfileRuntimeConfigBuilder.buildProduction(raw: source, profile: profile, scripts: .silent)
            else { return nil }
            return ("\(name).yaml", built)
        }
        return ("\(name).yaml", text)
    }

     
     
     
    nonisolated static func namesStorageInPlaceOfContent(_ text: String) -> Bool {
        ConfigTransforms.nodeLibraryPath(in: text) != nil || ConfigTransforms.ruleIndexPath(in: text) != nil
    }

    func subscriptionLink(for profile: Profile) -> String? {
        if case .url(let url) = profile.source { return url }
        return nil
    }

     
     
     
     
    private func forgetCachedSource(_ id: String? = nil) {
        if let id { sourceYAMLCache[id] = nil } else { sourceYAMLCache.removeAll() }
    }

    private func sidecarURL(for profile: Profile) -> URL? {
        workingDir?.appendingPathComponent("store/\(profile.id)/source.yaml")
    }

     
     
    func sourceLocation(for profile: Profile) -> URL? { sidecarURL(for: profile) }

     
     
    func loadSourceYAML(for profile: Profile) async -> String? {
        if let library = configurationLibraryStore,
           let raw = try? await Task.detached(operation: { () throws -> String? in
               guard let recipe = try library.snapshot().recipes.first(where: { $0.id == profile.id }),
                     recipe.preservesOriginal == true else { return nil }
               let payload = try library.payload(recipe.ruleSource)
                
                
                
                
                
                
               if payload.record.rulesWrittenInOriginal == true {
                   return String(data: payload.original, encoding: .utf8)
               }
                
                
                
               if let text = String(data: payload.original, encoding: .utf8),
                  (try? ConfigTransforms.validatedJSON(text)) != nil { return text }
               return try ConfigTransforms.jsonToYAML(payload.documentJSON)
           }).value { return raw }
        if let cached = sourceYAMLCache[profile.id] { return cached }
        guard let url = sidecarURL(for: profile) else { return sourceYAML(for: profile) }
        let value = await Task.detached(priority: .userInitiated) {
            try? String(contentsOf: url, encoding: .utf8)
        }.value
        sourceYAMLCache[profile.id] = value
        return value
    }

    func sourceYAML(for profile: Profile) -> String? {
         
         
         
         
        if let cached = sourceYAMLCache[profile.id] { return cached }
        let value = (try? hydratedSourceYAML(for: profile)) ?? sidecarYAML(for: profile)
        sourceYAMLCache[profile.id] = value
        return value
    }

     
     
     
     
     
     
     
     
     
     
    func capturedSourceText(for profile: Profile) -> String? {
        guard let workingDir else { return sourceYAML(for: profile) }
        return ProfileSourceStore.capturedText(
            workingDirectory: workingDir, profileID: profile.id
        ) ?? sourceYAML(for: profile)
    }

     
     
    func hasEditableSource(for profile: Profile) -> Bool {
        if let remembered = editableSourceCache[profile.id] { return remembered }
        guard let workingDir else { return false }
        let sidecar = workingDir.appendingPathComponent("store/\(profile.id)/source.yaml")
        editableSourceStatsForTesting += 1
        let exists = FileManager.default.fileExists(atPath: sidecar.path)
        editableSourceCache[profile.id] = exists
        return exists
    }

    func runtimeSourceYAML(for profile: Profile) -> String? {
        sidecarYAML(for: profile)
    }

     
     
     
     
     
     
     
    func udpFallbackGuardInput(for profile: Profile) async -> ConfigTransforms.UDPFallbackGuardInput? {
        guard let raw = runtimeSourceYAML(for: profile) else { return nil }
        return await Task.detached(priority: .userInitiated) {
            try? ProfileRuntimeConfigBuilder.udpFallbackGuardInput(raw: raw, profile: profile)
        }.value
    }

     
     
     
     
    private func sidecarYAML(for profile: Profile) -> String? {
        guard let workingDir else { return nil }
        let sidecar = workingDir.appendingPathComponent("store/\(profile.id)/source.yaml")
        return try? String(contentsOf: sidecar, encoding: .utf8)
    }

    private func cacheSourceYAML(_ yaml: String, for profile: Profile) throws {
        forgetCachedSource(profile.id)
        guard let workingDir else { throw PipelineError.sourceUnavailable(profile.label) }
        try sourceWriter(yaml, profile, workingDir)
        editableSourceCache.removeAll()
    }

     
     
     
     
     
     
    private static func writeSourceYAML(
        _ yaml: String,
        _ profile: Profile,
        _ workingDir: URL
    ) throws {
        let sidecar = workingDir.appendingPathComponent("store/\(profile.id)/source.yaml")
        try FileManager.default.createDirectory(
            at: sidecar.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(yaml.utf8).write(
            to: sidecar,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    private func restoreSourceYAML(_ yaml: String?, for profile: Profile) {
        guard let workingDir else { return }
        let sidecar = workingDir.appendingPathComponent("store/\(profile.id)/source.yaml")
        if let yaml {
            try? Self.writeSourceYAML(yaml, profile, workingDir)
        } else {
            try? FileManager.default.removeItem(at: sidecar)
            editableSourceCache.removeAll()
        }
    }

    private func externalResourceData(for profile: Profile) -> [String: Data] {
        guard let workingDir else { return [:] }
        return Self.externalResourceData(for: profile, workingDir: workingDir)
    }

     
     
    nonisolated private static func externalResourceData(
        for profile: Profile,
        workingDir: URL
    ) -> [String: Data] {
         
        Dictionary((profile.externalResources ?? []).compactMap { reference in
            let url = workingDir.appendingPathComponent(
                "store/\(profile.id)/resources/\(reference.storageKey)"
            )
            return (try? Data(contentsOf: url)).map { (reference.storageKey, $0) }
        }, uniquingKeysWith: { first, _ in first })
    }

     
    nonisolated private static func sidecarYAML(for profile: Profile, workingDir: URL) -> String? {
        let sidecar = workingDir.appendingPathComponent("store/\(profile.id)/source.yaml")
        return try? String(contentsOf: sidecar, encoding: .utf8)
    }

    private func hydratedSourceYAML(for profile: Profile) throws -> String {
        guard let yaml = sidecarYAML(for: profile) else {
            throw PipelineError.sourceUnavailable(
                "the saved source for this profile is unavailable"
            )
        }
         
        return yaml
    }

     
     
     
     
    nonisolated static func duplicatingLargeSource(_ profile: Profile, to id: String, workingDir: URL) throws
        -> [ProfileExternalResourceReference] {
        let fileManager = FileManager.default
        let from = workingDir.appendingPathComponent("store/\(profile.id)/source.yaml")
        let to = workingDir.appendingPathComponent("store/\(id)/source.yaml")
        try fileManager.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fileManager.removeItem(at: to)
        try fileManager.copyItem(at: from, to: to)
        #if os(iOS)
        try? fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                       ofItemAtPath: to.path)
        #endif
        let stored = externalResourceData(for: profile, workingDir: workingDir)
        var references: [ProfileExternalResourceReference] = []
        var resources: [String: Data] = [:]
        for reference in profile.externalResources ?? [] {
            guard let data = stored[reference.storageKey] else {
                throw ProfileExternalResourceError.storedResourceMissing(field: reference.fieldPath.joined(separator: "."))
            }
            let copy = ProfileExternalResourceImporter.reference(profileID: id, rekeying: reference)
            references.append(copy)
            resources[copy.storageKey] = data
        }
        try ProfileExternalResourceStore.replace(resources, profileID: id, coreHomeDir: workingDir)
        return references
    }

     
     
    nonisolated private static func duplicateResourceFiles(
        sourceYAML: String,
        profile: Profile,
        dataByKey: [String: Data]
    ) throws -> [ExternalResourceImportFile] {
        let json = try ConfigTransforms.yamlToJSON(sourceYAML)
        guard let root = try JSONSerialization.jsonObject(with: Data(json.utf8))
                as? [String: Any] else {
            throw ProfileExternalResourceError.invalidConfiguration
        }
        var filesByName: [String: Data] = [:]
        for requirement in IOSExternalResourceCatalog.requirements(root: root)
            where requirement.capability.confidentiality == .publicData {
            let sourceDigest = ProfileExternalResourceImporter.sha256(
                Data(requirement.rawValue.utf8)
            )
            guard let reference = (profile.externalResources ?? []).first(where: {
                $0.capabilityID == requirement.capability.id
                    && $0.proxy == requirement.proxyName
                    && $0.fieldPath == requirement.capability.fieldPath
                    && $0.sourceValueSHA256 == sourceDigest
            }), let data = dataByKey[reference.storageKey] else {
                throw ProfileExternalResourceError.storedResourceMissing(
                    field: requirement.capability.fieldPath.joined(separator: ".")
                )
            }
            let fileName = requirement.rawValue
                .replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/")
                .last
                .map(String.init) ?? requirement.rawValue
            if let previous = filesByName[fileName.lowercased()], previous != data {
                throw ProfileExternalResourceError.ambiguousSelection(
                    field: requirement.capability.fieldPath.joined(separator: ".")
                )
            }
            filesByName[fileName.lowercased()] = data
        }
        return filesByName.keys.sorted().compactMap { name in
            filesByName[name].map { ExternalResourceImportFile(fileName: name, data: $0) }
        }
    }

    private func uniqueCopyLabel(base: String, suffix: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = (trimmed.isEmpty ? "Profile" : trimmed) + suffix
        let existing = Set(profiles.map { $0.label.localizedLowercase })
        if !existing.contains(root.localizedLowercase) { return root }
        var index = 2
        while existing.contains("\(root) \(index)".localizedLowercase) { index += 1 }
        return "\(root) \(index)"
    }

    private func safeProfileFileName(_ label: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:")
        let sanitized = label.components(separatedBy: unsafe).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = String((sanitized.isEmpty ? "Profile" : sanitized).prefix(80))
        return "\(stem).yaml"
    }

    private func externalResourceSource(_ source: Profile.Source) -> IOSExternalResourceSource {
        switch source {
        case .url: return .subscription
        case .file: return .localFile
        case .clipboard: return .clipboard
        }
    }

     

     
     
     
     
     
     
     
    func startActivation(
        _ profile: Profile,
        applyToTunnel: Bool = true,
        preferCachedSource: Bool = false,
        runtimeCarriesChange: Bool = false,
        onlyIfActive: ActiveConfigurationPointer? = nil,
        inBackground: Bool = false,
        fetchesRuleSets: Bool = false,
        fetchesFresh: Bool = false,
        because reason: String = "unspecified"
    ) {
         
         
         
        ClashPerf.note(
            "activation.requested by=\(reason) applyToTunnel=\(applyToTunnel)"
        )


        var request = ActivationRequest(
            profile: profile,
            applyToTunnel: applyToTunnel,
            preferCachedSource: preferCachedSource,
            requestedWhileTunnelUp: ProfileSelectionRuntimePolicy.shouldApplyToTunnel(vpnStatus: vpn.status),
            runtimeCarriesChange: runtimeCarriesChange,
            onlyIfActive: onlyIfActive,
            inBackground: inBackground
        )
         
         
         
        if onlyIfActive != nil, pendingActivation != nil { return }
         
         
        if let pending = pendingActivation, !pending.inBackground { request.inBackground = false }
         
        request.fetchesRuleSets = fetchesRuleSets || pendingActivation?.fetchesRuleSets == true
         
        request.fetchesFresh = fetchesFresh || pendingActivation?.fetchesFresh == true
        clearFailure()
        guard activationTask == nil else {
             
             
             
            pendingActivation = request
            return
        }
         
         
         
         
         
        guard busyProfileID == nil else {
            pendingActivation = request
             
             
            statusMessage = request.profile.id == activeProfileID
                ? .format("Changes to %@ apply when the current update finishes.", [request.profile.label])
                : .format("%@ will switch when the current update finishes.", [request.profile.label])
            return
        }
        runActivation(request)
    }

    private func runActivation(_ queued: ActivationRequest) {
        activationAppliesToTunnel = queued.applyToTunnel
        isActivating = true
        activationInFlight = queued
        activationTask = Task { [weak self] in
            guard let self else { return }
             
             
             
             
             
             
             
            if let failure = await self.unresolvedReplacementRecovery() {
                self.recordFailure(failure, context: .activation, operation: .activation(queued.profile.id),
                                   preservesLastKnownGood: true)
            } else if let current = self.profiles.first(where: { $0.id == queued.profile.id }) {
                let request = ActivationRequest(profile: current, applyToTunnel: queued.applyToTunnel,
                                                preferCachedSource: queued.preferCachedSource,
                                                requestedWhileTunnelUp: queued.requestedWhileTunnelUp,
                                                runtimeCarriesChange: queued.runtimeCarriesChange,
                                                onlyIfActive: queued.onlyIfActive,
                                                inBackground: queued.inBackground,
                                                fetchesRuleSets: queued.fetchesRuleSets,
                                                fetchesFresh: queued.fetchesFresh)
                self.activationInFlight = request
                await self.activate(
                    request.profile,
                    applyToTunnel: request.applyToTunnel,
                    preferCachedSource: request.preferCachedSource,
                    requestedWhileTunnelUp: request.requestedWhileTunnelUp,
                    runtimeCarriesChange: request.runtimeCarriesChange,
                    onlyIfActive: request.onlyIfActive,
                    fetchesRuleSets: request.fetchesRuleSets,
                    fetchesFresh: request.fetchesFresh
                )
            }
            self.activationInFlight = nil
            self.activationTask = nil
            if let pending = self.pendingActivation {
                self.pendingActivation = nil
                 
                 
                 
                self.runActivation(pending)
            } else {
                self.activationAppliesToTunnel = nil
                self.isActivating = false
                self.restageOwedRebuild()
                self.restageOwedBuiltinUpgrade()
                 
                self.recomposeIfModulesMovedSincePublication()
            }
        }
    }

     
     
     
    private func drainPendingActivation() {
        guard activationTask == nil, busyProfileID == nil,
              let pending = pendingActivation else { return }
        pendingActivation = nil
        runActivation(pending)
    }

    func cancelActivation() {
        activationCancellationGeneration &+= 1
        pendingActivation = nil
        activationTask?.cancel()
    }

     
     
     
     
     
     
     
     
    func waitForPendingActivation() async {
        while let task = activationTask {
            await task.value
        }
    }

     
     
    private var republishedHandover: Task<Void, Never>?
    private var republishedHandoverGeneration = 0

     
    func waitForRepublishedHandover() async {
        while let task = republishedHandover { await task.value }
    }

    var failureProfile: Profile? {
        guard let failedOperation else { return nil }
        let id: String
        switch failedOperation {
        case .sync(let profileID), .activation(let profileID): id = profileID
        }
        return profiles.first { $0.id == id }
    }

    func retryLastFailure() {
        guard let failedOperation,
              let profile = failureProfile else { return }
        switch failedOperation {
        case .sync:
            sync(profile)
        case .activation:
            startActivation(profile)
        }
    }

    private func activate(
        _ profile: Profile,
        applyToTunnel: Bool,
        preferCachedSource: Bool,
        requestedWhileTunnelUp: Bool = false,
        runtimeCarriesChange: Bool = false,
        onlyIfActive: ActiveConfigurationPointer? = nil,
        fetchesRuleSets: Bool = false,
        fetchesFresh: Bool = false
    ) async {
        guard let container, busyProfileID == nil else { return }
        busyProfileID = profile.id
        statusMessage = .format("Preparing %@…", [profile.label])
        notices = []
        planErrors = []
        defer { busyProfileID = nil }
        var pipelineSucceeded = false
         
         
         
         
         
        let owed = workingDir.flatMap { RecoveryRebuilds.token(for: profile.id, workingDir: $0) }
        var builtFromStoredSource = false
        var laps = PerfLedger.Laps()
        do {
            let store = try ConfigResourceStore(containerURL: container)
             
             
             
            let coordinator = try vpn.activationCoordinator(
                store: store, container: container,
                fetchBudget: .forActivation(
                    connectInFront: fetchesRuleSets,
                    tunnelRunning: ProfileSelectionRuntimePolicy.shouldApplyToTunnel(vpnStatus: vpn.status)))
            let prefersStoredSource = preferCachedSource || owed != nil
            let workingDirectory = workingDir
             
             
             
             
             
             
             
             
             
             
             
             
             
            let (staged, stagedPreflight, stagedNotices, fromStoredSource) = try await Task.detached(priority: .userInitiated) {
                let handed = HandedSource(try Self.storedSourceYAML(
                    for: profile, preferCachedSource: prefersStoredSource, workingDir: workingDirectory))
                let fromStoredSource = handed.holdsText
                let pointer = try await coordinator.activate(
                    profile: profile, handedSource: handed, onlyIfActive: onlyIfActive,
                    forceFreshFetch: fetchesFresh
                )
                return (pointer,
                        coordinator.lastPublicationPreflight.flatMap { $0.pointer == pointer ? $0.outcome : nil },
                        coordinator.lastPublicationNotices.flatMap { $0.pointer == pointer ? $0.notices : nil },
                        fromStoredSource)
            }.value
            builtFromStoredSource = fromStoredSource
            laps.mark("restage.activate")

             
             
             
             
             
             
            let preflight = try await Task.detached(priority: .userInitiated) { () throws -> ([String], PreflightOutcome) in
                let activeYAML = try store.loadConfiguration(
                    profileID: staged.profileID, revision: staged.revision
                ).text ?? ""
                return (
                    stagedNotices ?? ((try? ConfigTransforms.planResources(mergedYAML: activeYAML).notices) ?? []),
                    stagedPreflight ?? PreflightService.intent(finalYAML: activeYAML, container: container)
                )
            }.value
            laps.mark("restage.readback")
            statusMessage = .format("%@ staged; applying to tunnel…", [profile.label])
            notices = preflight.0
            let outcome = preflight.1
             
             
             
             
            let handover = ActivationHandover.plan(
                applyToTunnel: applyToTunnel, requestedWhileTunnelUp: requestedWhileTunnelUp,
                runtimeCarriesChange: runtimeCarriesChange,
                tunnelUpNow: ProfileSelectionRuntimePolicy.shouldApplyToTunnel(vpnStatus: vpn.status))
            var applied: TunnelApplyOutcome?
            if handover.applies,
               let intentJSON = outcome.intentJSON,
               let intent = try? JSONDecoder().decode(PlatformConfigIntent.self,
                                                      from: Data(intentJSON.utf8)) {
                 
                 
                 
                 
                 
                revisionHandedToTunnel = staged
                BackgroundRefresh.clearPendingHandover(staged)
                applied = await vpn.applyActiveConfiguration(nextIntent: intent,
                                                             startsWhenDown: handover.startsWhenDown,
                                                             publishedAs: staged)
            }
             
             
             
            statusMessage = Self.statusLine(label: profile.label, outcome: applied)
            lastTunnelApply = TunnelApplyRecord(sequence: lastTunnelApply.sequence &+ 1, profileID: profile.id, outcome: applied)
            clearFailure()
            pipelineSucceeded = true
        } catch is CancellationError {
            statusMessage = "Update cancelled"
            clearFailure()
        } catch where ProfileActivationCoordinator.superseded(error) {
             
             
            statusMessage = .copy("")
            clearFailure()
        } catch where onlyIfActive != nil && ProfileActivationCoordinator.lostToASwitch(error) {
             
             
            statusMessage = .copy("")
            clearFailure()
        } catch let PipelineError.planRejected(failures) {
            planErrors = failures.map { "\($0.field): \($0.reason)" }
            recordFailure(
                PipelineError.planRejected(failures),
                context: .activation,
                operation: .activation(profile.id)
            )
        } catch {
            recordFailure(
                error,
                context: .activation,
                operation: .activation(profile.id)
            )
        }
        if pipelineSucceeded, builtFromStoredSource, let owed, let workingDir {
            RecoveryRebuilds.settle(profile.id, token: owed, workingDir: workingDir)
        }
        load()
         
         
         
         
         
        if pipelineSucceeded, lastFailure == nil, activeProfileID != profile.id {
            recordFailure(
                PipelineError.activationReadback,
                context: .activation,
                operation: .activation(profile.id)
            )
        }
    }

    private func clearFailure() {
        lastFailure = nil
        failedOperation = nil
        planErrors = []
    }

     
     
     
     
     
     
     
     
    func dismissFailure() {
        clearFailure()
    }

    private func recordFailure(
        _ error: Error,
        context: ConfigurationFailureContext,
        operation: FailedOperation?,
        preservesLastKnownGood: Bool = true
    ) {
        guard let failure = ConfigurationFailureClassifier.classify(
            error,
            context: context,
            preservesLastKnownGood: preservesLastKnownGood
        ) else {
            clearFailure()
            return
        }
        lastFailure = failure
        failedOperation = operation
        statusMessage = .copy(failure.title)
    }

     
     
     
     
    func storedSourceYAMLForSaving(_ profile: Profile) throws -> String? {
        try storedSourceYAML(for: profile, preferCachedSource: true)
    }

    private func storedSourceYAML(
        for profile: Profile,
        preferCachedSource: Bool = false
    ) throws -> String? {
        try Self.storedSourceYAML(for: profile, preferCachedSource: preferCachedSource, workingDir: workingDir)
    }

     
     
     
    nonisolated static func storedSourceYAML(
        for profile: Profile,
        preferCachedSource: Bool,
        workingDir: URL?
    ) throws -> String? {
        if case .url = profile.source,
           profile.usesLocalSourceOverride != true,
           !preferCachedSource {
            return nil
        }
        guard let workingDir else { throw PipelineError.sourceUnavailable(profile.label) }
        let sidecar = workingDir.appendingPathComponent("store/\(profile.id)/source.yaml")
        if preferCachedSource,
           case .url = profile.source,
           !FileManager.default.fileExists(atPath: sidecar.path) {
             
             
            return nil
        }
        guard let yaml = try? String(contentsOf: sidecar, encoding: .utf8) else {
            if case .url = profile.source {
                 
                 
                 
                return nil
            }
            throw PipelineError.sourceUnavailable(
                "original YAML for '\(profile.label)' is gone; re-add the profile")
        }
        return yaml
    }
}


 
 
 
struct ProfileBaseDocumentHost<Content: View>: View {
    @ObservedObject var profiles: ProfilesViewModel
    let profile: Profile
    @ViewBuilder let content: (String?) -> Content
    @State private var loaded: (profile: Profile, value: String?)?

    var body: some View {
        Group {
            if let cached = profiles.cachedBaseYAML(for: profile) {
                content(cached.value)
            } else if let loaded, loaded.profile == profile {
                content(loaded.value)
            } else {
                ClashOpeningProgress()
            }
        }
        .task(id: profile) {
            let value = await profiles.loadBaseYAML(for: profile)
            guard !Task.isCancelled else { return }
            loaded = (profile, value)
        }
    }
}

extension Notification.Name {
     
     
     
    static let clashProfileEditedOutsideTheModel = Notification.Name("ClashProfileEditedOutsideTheModel")
     
     
     
     
     
     
     
     
     
     
    static let clashProviderContentChanged = Notification.Name("ClashProviderContentChanged")
}

 
struct ConfigTextDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.yaml, .plainText]

    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

extension ConfigurationSchemePageOwnership {
     
    var schemeID: String? {
        switch self {
        case .own(let id, _, _), .shared(let id, _): return id
        case .original: return nil
        }
    }
}

 
 
struct ConfigurationRulesKeptByConfiguration: LocalizedError {
    let configuration: String
     
    var locale: Locale = .current
    var errorDescription: String? {
        ClashCopy.format("This link’s rules are kept in “%@”, so they were not added again.", locale: locale, configuration)
    }
}
