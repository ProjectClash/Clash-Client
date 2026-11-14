import Combine
import ClashClientKit
import ClashClientUI
import SwiftUI
import UniformTypeIdentifiers

extension AuthoredText {
     
     
     
    var displayText: ClashDisplayText {
        switch self {
        case .app(let key, let arguments): return arguments.isEmpty ? .copy(key) : .format(key, arguments)
        case .verbatim(let text): return .verbatim(text)
        }
    }
}

 
 
 
 
 
extension AuthoredError: ClashAuthoredError {
    var displayText: ClashDisplayText { text.displayText }
}
extension DownloadError: ClashAuthoredError {
    var displayText: ClashDisplayText { authoredText.displayText }
}
extension ProviderDownloadFailure: ClashAuthoredError {
    var displayText: ClashDisplayText { AuthoredText.of(underlying).displayText }
}
extension ProviderValidationFailure: ClashAuthoredError {
    var displayText: ClashDisplayText { AuthoredText.of(underlying).displayText }
}
extension ProviderDownloadFailuresError: ClashAuthoredError {
    var displayText: ClashDisplayText {
        failures.count == 1 ? AuthoredText.of(failures[0].underlying).displayText : .verbatim(localizedDescription)
    }
}
extension MaterializeError: ClashAuthoredError {
    var displayText: ClashDisplayText { (providerRowText ?? .verbatim(localizedDescription)).displayText }
}
extension PipelineError: ClashAuthoredError {
    var displayText: ClashDisplayText { authoredText.displayText }
}

extension ProviderNote {
     
    func displayText(locale: Locale) -> ClashDisplayText {
        switch self {
        case .fetchedByCore:
             
             
            return .verbatim("")
        case .notDownloadedYet: return .copy(ProviderFetchDeferred.sentence)
        case .downloading: return .copy(ProviderDownloadActivity.downloadingNote)
        case .downloadFailed(_, let reason):
            return .format("Download failed: %@", [ClashCopy.string(for: reason.displayText, locale: locale)])
        case .failed(let text), .held(let text), .checkFailed(let text): return text.displayText
        }
    }
}

extension ProviderCatalog {
     
     
     
     
    static func writtenAt(providersDir: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(
            atPath: providersDir.appendingPathComponent(fileName).path))?[.modificationDate] as? Date
    }

     
     
     
     
     
    func note(of entry: Entry, state: ProviderRefreshState?, written: Date?, copiedAt: Date?) -> ProviderNote? {
        let line = state?.entry(kind: entry.kind, name: entry.name, url: entry.url)
         
         
         
         
        var fetchedByCore = coreFetchedProviders?.contains(entry.name) ?? false
        if case .fetchedByCore? = entry.note { fetchedByCore = true }
        return ProviderNote.merging(
            catalog: entry.note, tunnel: line,
            line: line.flatMap { state?.displayLine(kind: entry.kind, name: entry.name, $0, appCanFetch: !fetchedByCore) },
             
             
            catalogDate: entry.note == nil ? copiedAt : entry.notedAt ?? [copiedAt, written].compactMap { $0 }.max())
    }

     
    func proxyProviderNotes(state: ProviderRefreshState?, written: Date?) -> [String: ProviderNote] {
        var notes: [String: ProviderNote] = [:]
        for entry in entries where entry.kind == "proxy" {
            notes[entry.name] = note(of: entry, state: state, written: written,
                                     copiedAt: entry.acquiredAt ?? entry.lastUpdatedAt)
        }
         
        for (name, notice) in unusableProxyProviders ?? [:] { notes[name] = .failed(.verbatim(notice)) }
        return notes
    }
}

 
enum ProviderInventory {
    struct Entry: Equatable {
        let name: String
        let sizeBytes: Int?
        let updatedAt: Date?
    }

    static func scan(providersDir: URL) -> [Entry] {
        guard let names = try? FileManager.default
            .contentsOfDirectory(atPath: providersDir.path) else { return [] }
        return names.sorted()
            .filter { $0 != "providers.json" }   
            .map { name in
                let attributes = try? FileManager.default.attributesOfItem(
                    atPath: providersDir.appendingPathComponent(name).path)
                return Entry(name: name,
                             sizeBytes: (attributes?[.size] as? NSNumber)?.intValue,
                             updatedAt: attributes?[.modificationDate] as? Date)
            }
    }
}

 
 
 
 
 
final class ProviderRefreshStateWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

     
    static var stateDirectory: URL? {
        ClashAppIdentifiers.appGroupContainer?
            .appendingPathComponent("working", isDirectory: true)
            .appendingPathComponent(ProviderRefreshState.directoryName, isDirectory: true)
    }

    private var directory: URL?
    private var onChange: (@MainActor () -> Void)?
     
     
    private var retry: DispatchWorkItem?

     
     
     
     
    func start(directory: URL?, onChange: @escaping @MainActor () -> Void) {
        stop()
        guard let directory else { return }
        self.directory = directory
        self.onChange = onChange
        watch()
    }

     
     
     
    private func watch(announce: Bool = false) {
        source?.cancel()
        source = nil
        retry?.cancel()
        retry = nil
        guard let directory else { return }
        let present = FileManager.default.fileExists(atPath: directory.path)
        let watched = present ? directory : directory.deletingLastPathComponent()
        let descriptor = open(watched.path, O_EVTONLY)
        guard descriptor >= 0 else {
             
             
             
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.directory == directory, self.source == nil else { return }
                self.watch(announce: true)
            }
            retry = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            if present {
                 
                if !source.data.isDisjoint(with: [.delete, .rename]) { self.watch() }
            } else if !source.data.isDisjoint(with: [.delete, .rename]) {
                 
                self.watch(announce: true)
                return
            } else {
                 
                guard FileManager.default.fileExists(atPath: directory.path) else { return }
                self.watch()
            }
            self.announce()
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        if announce { self.announce() }
    }

     
    private func announce() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let onChange = self?.onChange else { return }
            MainActor.assumeIsolated { onChange() }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func stop() {
        pending?.cancel()
        pending = nil
        retry?.cancel()
        retry = nil
        source?.cancel()
        source = nil
        directory = nil
        onChange = nil
    }

    deinit { stop() }
}

extension ProviderRefreshStateWatcher {
     
     
     
     
    static func changes(in directory: URL? = stateDirectory) -> AnyPublisher<Void, Never> {
        Deferred { () -> AnyPublisher<Void, Never> in
            let subject = PassthroughSubject<Void, Never>()
            let watcher = ProviderRefreshStateWatcher()
            watcher.start(directory: directory) { subject.send(()) }
             
            return subject.handleEvents(receiveCancel: { watcher.stop() }).eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }
}

 
 
 
 
 
 
 
 
 
@MainActor
final class RunningProvidersReader: ObservableObject {
    typealias Running = ConfigurationCollectionContentBridge.RunningProviders

    @Published private(set) var current: Running?
    private let container: @MainActor () -> URL?
    private let read: @Sendable (URL?) async -> Running?
    private var generation: UInt64 = 0
    private let watcher = ProviderRefreshStateWatcher()

    init(container: @escaping @MainActor () -> URL?,
         read: @escaping @Sendable (URL?) async -> Running? = { container in
             await Task.detached { Running.load(container: container) }.value
         }) {
        self.container = container
        self.read = read
    }

     
    func reload() async {
        generation &+= 1
        let token = generation
        let next = await read(container())
        guard token == generation else { return }
        current = next
    }

     
     
    func follow(_ onScreen: Bool) {
        guard onScreen else {
            watcher.stop()
            return
        }
        let directory = container()?
            .appendingPathComponent("working", isDirectory: true)
            .appendingPathComponent(ProviderRefreshState.directoryName, isDirectory: true)
        watcher.start(directory: directory) { [weak self] in
            Task { await self?.reload() }
        }
        Task { await reload() }
    }
}

 
 
 
 
 
 
@MainActor
final class ProvidersModel: ObservableObject {
    struct Row: Equatable, Identifiable {
        let name: String        
        let kind: String?       
        let sizeBytes: Int?
        let updatedAt: Date?
        let count: Int?
        let subscriptionInfo: SubscriptionInfo?
        let canRefresh: Bool
         
         
         
         
        var note: ProviderNote? = nil
        var runtime: ProviderRuntimeSummary? = nil
         
         
         
         
        var stateCheckedAt: Date? = nil
         
         
         
         
        var stateCount: Int? = nil
        var stateSubscriptionInfo: SubscriptionInfo? = nil
        var id: String { name }

         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        var shownUpdatedAt: Date? { runtime?.updatedAt ?? stateCheckedAt ?? updatedAt }
        var shownCount: Int? { runtime?.entryCount ?? stateCount ?? count }
        var shownSubscriptionInfo: SubscriptionInfo? {
            if runtime?.updatedAt != nil, let live = runtime?.subscriptionInfo { return live }
            return stateSubscriptionInfo ?? subscriptionInfo
        }
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var activeProfile: Profile?
    @Published private(set) var busy = false
    @Published private(set) var busyProvider: String?
     
     
     
     
     
    @Published private(set) var syncingProviders: Set<String> = []
    @Published private(set) var healthCheckingProvider: String?
    @Published private(set) var runtimeLoading = false
     
     
     
    enum LiveStatus: Equatable {
        case none
        case disconnected
         
        case loading
        case unavailable(reason: String?)
        case checkingHealth
        case healthCheckFailed(reason: String?)
    }
    @Published private(set) var liveStatus: LiveStatus = .none
     
    static var liveLoadingDelayNanoseconds: UInt64 = 1_000_000_000
    @Published private(set) var status = "" { didSet { statusText = nil; statusIsNotice = false; statusTone = nil } }
     
     
     
    @Published private(set) var statusText: ClashDisplayText?
     
     
    @Published private(set) var statusIsNotice = false
     
     
     
    @Published private(set) var statusTone: ClashStatusKind?
     
     
    var locale: Locale = .current
    @Published private(set) var lastFailure: ConfigurationFailure?
    @Published private(set) var batchReport: BatchUpdateReport?

    private let vpn: VPNController
    private let command: ClashCommandClient
    private var localRows: [Row] = []
    private var runtimeCatalog: ProviderRuntimeCatalog?
    private var runtimeTask: Task<Void, Never>?
    private var runtimeGeneration: UInt64 = 0
    private var retryOperation: RetryOperation?
    private var batchTask: Task<Void, Never>?
     
     
     
     
    private var requestedRefresh = 0
    private var honoredRefresh = 0
    private var hasLoaded = false

    private enum RetryOperation {
        case all
        case provider(String)
    }

    init(vpn: VPNController, command: ClashCommandClient) {
        self.vpn = vpn
        self.command = command
    }

    private var container: URL? {
        ClashAppIdentifiers.appGroupContainer
    }

     
     
    var providerNotices: [ProviderDefinitionMergeNotice] {
        activeProfile?.providerDefinitionNotices ?? []
    }

     
     
    func acknowledgeProviderNotices() {
        guard let container, let profile = activeProfile else { return }
        let store = ProfileStore(
            fileURL: container.appendingPathComponent("working/store/profiles.json"))
        Self.acknowledgeProviderNotices(in: store, profileID: profile.id)
        load()
    }

     
     
    static func acknowledgeProviderNotices(in store: ProfileStore, profileID: String) {
        _ = try? store.updateIfPresent(id: profileID, when: { $0.providerDefinitionNotices != nil }) {
            $0.providerDefinitionNotices = nil
        }
    }

    func load() {
        runtimeTask?.cancel()
        runtimeGeneration &+= 1
        runtimeCatalog = nil
        guard let container,
              let store = try? ConfigResourceStore(containerURL: container) else { return }
        if let dir = try? store.activeProvidersDirectory() {
            localRows = Self.rows(
                providersDir: dir,
                state: ProviderRefreshState.read(workingDirectory: container.appendingPathComponent("working")))
        } else {
            localRows = []
        }
        rows = localRows
        let profiles = ProfileStore(
            fileURL: container.appendingPathComponent("working/store/profiles.json")).load()
         
         
         
         
         
         
         
        let activeID = (try? store.activeIdentity())?.profileID
        activeProfile = profiles.first { $0.id == activeID }
        refreshRuntimeCatalog()
        hasLoaded = true
        fireRequestedRefreshIfReady()
    }

     
     
    func reloadForOutsideChange() {
        guard !busy else { return }
        load()
    }

     
    func honorRefreshRequest(_ token: Int) {
        requestedRefresh = token
        fireRequestedRefreshIfReady()
    }

    private func fireRequestedRefreshIfReady() {
        guard ProvidersRefreshRequestPolicy.fires(
            requested: requestedRefresh, honored: honoredRefresh, loaded: hasLoaded
        ) else { return }
        honoredRefresh = requestedRefresh
        refreshAll()
    }

    static func rows(providersDir: URL, state: ProviderRefreshState? = nil) -> [Row] {
        if let catalog = ProviderCatalog.load(providersDir: providersDir) {
            let written = ProviderCatalog.writtenAt(providersDir: providersDir)
            return catalog.entries
                .sorted { $0.name < $1.name }
                .map { entry in
                    let attributes = try? FileManager.default.attributesOfItem(
                        atPath: providersDir.appendingPathComponent(entry.path).path)
                    let updatedAt = entry.lastUpdatedAt ?? attributes?[.modificationDate] as? Date
                    let note = catalog.note(of: entry, state: state, written: written,
                                            copiedAt: entry.acquiredAt ?? updatedAt)
                     
                     
                    let owed = note == .notDownloadedYet
                     
                     
                     
                    let newer = owed ? nil : state?.newerEntry(of: entry, than: updatedAt)
                    return Row(name: entry.name, kind: entry.kind,
                               sizeBytes: owed ? nil : (attributes?[.size] as? NSNumber)?.intValue,
                               updatedAt: owed ? nil : updatedAt,
                               count: entry.count,
                               subscriptionInfo: entry.subscriptionInfo,
                               canRefresh: true,
                               note: note,
                               stateCheckedAt: newer?.checkedAt,
                               stateCount: newer?.countOfCheckedContent,
                               stateSubscriptionInfo: newer?.usage)
                }
        }
         
        return ProviderInventory.scan(providersDir: providersDir).map {
            Row(name: $0.name, kind: nil, sizeBytes: $0.sizeBytes,
                updatedAt: $0.updatedAt, count: nil,
                subscriptionInfo: nil, canRefresh: false)
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    nonisolated static func unreadableRuleSets(
        providersDir: URL
    ) -> [Row] {
        guard let catalog = ProviderCatalog.load(providersDir: providersDir)
        else { return [] }
        return catalog.entries
             
             
             
            .filter { $0.kind == "rule" && $0.note?.isFailure == true }
            .sorted { $0.name < $1.name }
            .map {
                Row(name: $0.name, kind: $0.kind, sizeBytes: nil,
                    updatedAt: $0.lastUpdatedAt, count: $0.count,
                    subscriptionInfo: nil, canRefresh: true,
                    note: $0.note)
            }
    }

    static func mergingRuntime(
        _ runtime: ProviderRuntimeCatalog,
        into localRows: [Row]
    ) -> [Row] {
        localRows.map { row in
            var merged = row
            merged.runtime = runtime.summary(name: row.name, kind: row.kind)
            return merged
        }
    }

    func refreshRuntimeCatalog() {
        runtimeTask?.cancel()
        runtimeGeneration &+= 1
        let token = runtimeGeneration
        guard command.isConnected else {
            runtimeLoading = false
            runtimeCatalog = nil
            rows = localRows
            liveStatus = .disconnected
            return
        }
        runtimeLoading = true
         
         
        if liveStatus != .checkingHealth { liveStatus = .none }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.liveLoadingDelayNanoseconds)
            guard let self, token == self.runtimeGeneration, self.runtimeLoading, self.liveStatus == .none else { return }
            self.liveStatus = .loading
        }
        runtimeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let catalog = try await self.command.providerRuntimeCatalog()
                guard !Task.isCancelled, token == self.runtimeGeneration else { return }
                self.runtimeCatalog = catalog
                self.rows = Self.mergingRuntime(catalog, into: self.localRows)
                 
                 
                if self.liveStatus == .loading || self.liveStatus == .none { self.liveStatus = .none }
            } catch is CancellationError {
                return
            } catch ProviderRuntimeCatalogError.notNow {
                 
                 
                guard !Task.isCancelled, token == self.runtimeGeneration else { return }
                if self.liveStatus == .loading { self.liveStatus = .none }
            } catch {
                guard !Task.isCancelled, token == self.runtimeGeneration else { return }
                self.runtimeCatalog = nil
                self.rows = self.localRows
                self.liveStatus = .unavailable(reason: ClashErrorCopy.message(error, locale: self.locale))
            }
            guard token == self.runtimeGeneration else { return }
            self.runtimeLoading = false
            self.runtimeTask = nil
        }
    }

    func checkHealth(provider name: String) {
        guard !busy,
              healthCheckingProvider == nil,
              command.isConnected,
              rows.contains(where: {
                  $0.name == name && $0.kind?.lowercased() == "proxy"
              }) else { return }
        healthCheckingProvider = name
        liveStatus = .checkingHealth
        Task { [weak self] in
            guard let self else { return }
            defer { self.healthCheckingProvider = nil }
            do {
                let provider = try await self.command.healthCheckProxyProvider(named: name)
                var catalog = self.runtimeCatalog ?? .empty
                catalog.proxyProviders[name] = provider
                self.runtimeCatalog = catalog
                self.rows = Self.mergingRuntime(catalog, into: self.localRows)
                 
                self.liveStatus = .none
            } catch {
                self.liveStatus = .healthCheckFailed(reason: ClashErrorCopy.message(error, locale: self.locale))
            }
        }
    }

    func refreshAll() {
        guard !busy, let container, let profile = activeProfile,
              let store = try? ConfigResourceStore(containerURL: container) else { return }
        let refreshable = rows.filter(\.canRefresh)
        guard !refreshable.isEmpty else {
            refreshLegacyRevision(profile: profile, store: store, container: container)
            return
        }
        batchReport = BatchUpdateReport(
            title: "Provider Sync",
            expectedCount: refreshable.count
        )
        busy = true
        clearFailure()
        status = "Refreshing providers…"
        statusTone = .information
        let names = refreshable.map(\.name)
        let profileID = profile.id
        batchTask = Task { [weak self] in
            guard let self else { return }
             
             
             
             
            self.syncingProviders = Set(names)
             
             
            let report = await ProviderUpdater.update(names, in: .live(
                profile: profile, store: store, container: container, vpn: self.vpn, scripts: .silent,
                stillInUse: { store.activeIdentityOrNil()?.profileID == profileID }),
                progress: { [weak self] name, outcome in
                    guard let self else { return }
                    self.syncingProviders.remove(name)
                    if let item = Self.batchItem(name, outcome, locale: self.locale) { self.recordBatchItems([item]) }
                })
            self.syncingProviders = []
            self.recordBatchItems(names.compactMap { Self.batchItem($0, report.outcomes[$0], locale: self.locale) })
             
            if Task.isCancelled { self.markBatchCancelled() }
            self.busyProvider = nil
            self.busy = false
            self.batchTask = nil
            self.load()
            if let report = self.batchReport {
                self.status = report.wasCancelled ? "Provider sync cancelled" : "Provider sync finished"
                self.statusTone = Self.batchTone(report)
            }
        }
    }

    func refresh(provider name: String) {
        guard !busy, let container, let profile = activeProfile,
              let store = try? ConfigResourceStore(containerURL: container) else { return }
        busy = true
        clearFailure()
        busyProvider = name
        status = "Updating \(name)…"
        statusText = .format("Updating %@…", [name])
        statusTone = .information
        let profileID = profile.id
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.busy = false
                self.busyProvider = nil
                self.load()
            }
             
             
             
             
            let report = await ProviderUpdater.update([name], in: .live(
                profile: profile, store: store, container: container, vpn: self.vpn, scripts: .surfaced,
                stillInUse: { store.activeIdentityOrNil()?.profileID == profileID }))
             
             
             
            if case .failed? = report.outcomes[name], let failure = report.errors[name] {
                self.recordFailure(failure.error, operation: .provider(name))
            } else {
                self.show(report.outcomes[name] ?? .skipped, for: name)
            }
        }
    }

     
     
     
    static func batchTone(_ report: BatchUpdateReport) -> ClashStatusKind {
        if report.failedCount > 0 { return .error }
        return report.wasCancelled || report.pendingCount > 0 ? .information : .success
    }

     
    private func show(_ outcome: ProviderUpdater.Outcome, for name: String) {
        let line = Self.statusLine(outcome, for: name, locale: locale)
        status = "\(name) \(line.tone)"
        statusText = line.text
        statusTone = line.tone
        statusIsNotice = line.tone == .information
    }

     
    static func statusLine(_ outcome: ProviderUpdater.Outcome, for name: String,
                           locale: Locale) -> (text: ClashDisplayText, tone: ClashStatusKind) {
        switch outcome {
        case .updated: return (.format("%@ updated", [name]), .success)
        case .unchanged: return (.format("%@ is up to date", [name]), .success)
        case .failed(let reason):
            return (.format("Could not update %@: %@", [name, ClashCopy.string(for: reason.displayText, locale: locale)]),
                    .error)
        case .heldByTunnel(let line):
            return (.format("%@: %@", [name, ClashCopy.string(for: line.displayText, locale: locale)]), .information)
        case .awaitingConnection: return (.format("%@ updates when you connect", [name]), .information)
        case .notConfirmed(let text): return (text.displayText, .information)
        case .notUpdatable(.unusableAddress): return (.format("Clash cannot use the address of %@.", [name]), .error)
        case .notUpdatable(.local), .skipped:
            return (.format("The configuration changed meanwhile; %@ was not updated.", [name]), .information)
        }
    }

     
     
    static func batchItem(_ name: String, _ outcome: ProviderUpdater.Outcome?,
                          locale: Locale) -> BatchUpdateItem? {
        switch outcome {
        case .updated?: return BatchUpdateItem(id: name, label: name, state: .updated)
        case .unchanged?: return BatchUpdateItem(id: name, label: name, state: .unchanged)
        case .failed(let reason)?: return BatchUpdateItem(id: name, label: name, state: .failed, text: reason.displayText)
        case .heldByTunnel(let line)?: return BatchUpdateItem(id: name, label: name, state: .pending, text: line.displayText)
        case .awaitingConnection?:
            return BatchUpdateItem(id: name, label: name, state: .pending, text: .copy("Updates when you connect"))
        case .notConfirmed(let text)?: return BatchUpdateItem(id: name, label: name, state: .pending, text: text.displayText)
        case .notUpdatable(.unusableAddress)?:
            return BatchUpdateItem(id: name, label: name, state: .failed,
                                   text: .format("Clash cannot use the address of %@.", [name]))
        case .notUpdatable(.local)?, .skipped?, nil: return nil
        }
    }

     
     
    func refreshAllAwaiting() async {
        refreshAll()
        await batchTask?.value
    }

     
     
     
     
    var canCancelBatch: Bool { busy && batchTask != nil }

    func cancelBatchRefresh() {
        batchTask?.cancel()
    }

    func dismissBatchReport() {
        guard !busy else { return }
        batchReport = nil
    }

    func retryBatchItem(id: String) {
        guard !busy, rows.contains(where: { $0.id == id }),
              let container, let profile = activeProfile,
              let store = try? ConfigResourceStore(containerURL: container) else { return }
        busy = true
        busyProvider = id
        let profileID = profile.id
        batchTask = Task { [weak self] in
            guard let self else { return }
             
             
             
            let report = await ProviderUpdater.update([id], in: .live(
                profile: profile, store: store, container: container, vpn: self.vpn, scripts: .surfaced,
                stillInUse: { store.activeIdentityOrNil()?.profileID == profileID }))
            if let item = Self.batchItem(id, report.outcomes[id], locale: self.locale) {
                self.recordBatchItems([item])
            } else if Task.isCancelled {
                self.markBatchCancelled()
            }
            self.busy = false
            self.busyProvider = nil
            self.batchTask = nil
            self.load()
        }
    }

    func sideLoad(provider name: String, fileURL: URL) {
        guard !busy, let container, let profile = activeProfile,
              let store = try? ConfigResourceStore(containerURL: container) else { return }
        busy = true
        clearFailure()
        busyProvider = name
        status = "Loading local file for \(name)…"
         
         
        statusText = .format("Loading %@ from a local file…", [name])
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.busy = false
                self.busyProvider = nil
                self.load()
            }
            let accessed = fileURL.startAccessingSecurityScopedResource()
            defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
            do {
                let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                if let size = values.fileSize,
                   size > ProfileActivationCoordinator.maxProviderBytes {
                    throw DownloadError.tooLarge(size)
                }
                let data = try Data(
                    contentsOf: fileURL,
                    options: [.mappedIfSafe, .uncached]
                )
                let coordinator = try vpn.activationCoordinator(store: store, container: container)
                let publication = try await coordinator.sideLoadProvider(
                    named: name,
                    data: data,
                    profile: profile
                )
                 
                 
                let handingOver = Date()
                let wait = await PublishedRuntimeHandover.bounded({
                    await PublishedRuntimeHandover.apply(vpn: self.vpn, profileID: publication.pointer.profileID)
                }, landedLate: PublishedRuntimeHandover.lateLanding(since: handingOver) {
                    "provider side-load step=handover-late took=\($0)s outcome=\($1)"
                })
                self.status = "\(name) loaded from local file"
                self.statusText = Self.sideLoadedLine(name, wait: wait)
                self.clearFailure()
            } catch PipelineError.sourceUnavailable {
                self.status = "No cached source; activate the profile once first"
            } catch where ProfileActivationCoordinator.lostToASwitch(error) {
                 
                 
                 
                self.status = name
                self.statusText = .format("The configuration changed meanwhile; %@ was not updated.", [name])
                self.statusIsNotice = true
                self.clearFailure()
            } catch {
                self.recordFailure(error, context: .localImport, operation: nil)
            }
        }
    }

     
     
    static func sideLoadedLine(_ name: String, wait: PublishedRuntimeHandover.Wait) -> ClashDisplayText {
        guard case .answered = wait else { return .copy("The tunnel did not confirm this update.") }
        return .format("%@ was loaded from a local file.", [name])
    }

    func reportImportFailure(_ error: Error) {
        recordFailure(error, context: .localImport, operation: nil)
    }

    func retryLastFailure() {
        guard let retryOperation else { return }
        switch retryOperation {
        case .all: refreshAll()
        case .provider(let name): refresh(provider: name)
        }
    }

     
     
    func updateActiveProfile(_ profile: Profile) throws {
        guard let container else { return }
        let store = ProfileStore(
            fileURL: container.appendingPathComponent("working/store/profiles.json")
        )
         
         
         
         
        let settings = ProfileSettingsFacade()
        guard let written = try store.updateIfPresent(id: profile.id, {
            $0 = settings.applying(settings.snapshot(for: profile), to: $0)
        }) else { return }
        activeProfile = written
         
         
        NotificationCenter.default.post(name: .clashProfileEditedOutsideTheModel, object: nil,
                                        userInfo: ["profileID": profile.id])
    }

    private func clearFailure() {
        lastFailure = nil
        retryOperation = nil
    }

     
     
    nonisolated static func providerBytesChanged(_ name: String, store: ConfigResourceStore,
                                                before: ActiveConfigurationPointer?,
                                                after: ActiveConfigurationPointer) -> Bool? {
        guard let before, before.profileID == after.profileID,
              let old = store.providersDirectory(profileID: before.profileID, revision: before.revision),
              let new = store.providersDirectory(profileID: after.profileID, revision: after.revision),
              let entry = ProviderCatalog.load(providersDir: new)?.entries.first(where: { $0.name == name }),
              let previous = try? Data(contentsOf: old.appendingPathComponent(entry.path)),
              let current = try? Data(contentsOf: new.appendingPathComponent(entry.path)) else { return nil }
        return previous != current
    }

     
     
     
    private func refreshLegacyRevision(
        profile: Profile,
        store: ConfigResourceStore,
        container: URL
    ) {
         
         
         
        guard let expected = store.activeIdentityOrNil(), expected.profileID == profile.id else { return }
        busy = true
        clearFailure()
        batchReport = nil
        status = "Re-materializing providers…"
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.busy = false
                self.load()
            }
            do {
                let coordinator = try self.vpn.activationCoordinator(
                    store: store,
                    container: container
                )
                _ = try await coordinator.activate(
                    profile: profile,
                    sourceYAML: self.sidecarYAML(for: profile),
                    onlyIfActive: expected
                )
                let wait = await self.applyToTunnel(store: store)
                 
                self.status = wait == .timedOut ? "The tunnel did not confirm this update." : "Providers refreshed"
                self.clearFailure()
            } catch where ProfileActivationCoordinator.superseded(error)
                            || ProfileActivationCoordinator.lostToASwitch(error) {
                 
                 
                self.status = ""
                self.clearFailure()
            } catch {
                self.recordFailure(error, operation: .all)
            }
        }
    }

    private func recordBatchItems(_ items: [BatchUpdateItem]) {
        guard var report = batchReport else { return }
        report.wasCancelled = false
        for item in items { report.record(item) }
        batchReport = report
    }

    private func markBatchCancelled() {
        guard var report = batchReport else { return }
        report.wasCancelled = true
        batchReport = report
    }

    private func recordFailure(
        _ error: Error,
        context: ConfigurationFailureContext = .provider,
        operation: RetryOperation?
    ) {
        guard let failure = ConfigurationFailureClassifier.classify(
            error,
            context: context,
            preservesLastKnownGood: true
        ) else {
            clearFailure()
            return
        }
        lastFailure = failure
        retryOperation = operation
        status = failure.title
    }

     
     
     
     
     
     
     
    private func applyToTunnel(store: ConfigResourceStore) async -> PublishedRuntimeHandover.Wait {
        let handingOver = Date()
        return await PublishedRuntimeHandover.bounded({
            await PublishedRuntimeHandover.apply(vpn: self.vpn, profileID: nil)
        }, landedLate: PublishedRuntimeHandover.lateLanding(since: handingOver) {
            "provider legacy refresh step=handover-late took=\($0)s outcome=\($1)"
        })
    }

    private func sidecarYAML(for profile: Profile) -> String? {
        if case .url = profile.source { return nil }
        guard let container else { return nil }
        let sidecar = container
            .appendingPathComponent("working/store/\(profile.id)/source.yaml")
        return try? String(contentsOf: sidecar, encoding: .utf8)
    }
}

enum ProviderDisplayScope: Equatable {
    case all
    case proxy
    case rule

    var title: String {
        switch self {
        case .all: return "Providers"
        case .proxy: return "Proxy Sources"
        case .rule: return "Rule Sets"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: return "No materialized providers are available in the active revision."
        case .proxy: return "No materialized proxy sources are available in the active revision."
        case .rule: return "No materialized rule sets are available in the active revision."
        }
    }

    func filtered(_ rows: [ProvidersModel.Row]) -> [ProvidersModel.Row] {
        switch self {
        case .all:
            return rows
        case .proxy:
            return rows.filter { $0.kind?.lowercased() == "proxy" }
        case .rule:
            return rows.filter { $0.kind?.lowercased() == "rule" }
        }
    }
}

 
 
 
 
 
 
struct ProviderNoticesSection: View {
    @Environment(\.locale) private var locale
    let notices: [ProviderDefinitionMergeNotice]
    let acknowledge: () -> Void

    var body: some View {
        Section {
            ForEach(notices) { notice in
                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                    Text(verbatim: notice.provider)
                        .font(.body)
                    Text(clash: ProviderNoticeCopy.line(for: notice, locale: locale))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("providers.notice.\(notice.id)")
            }
            Button {
                acknowledge()
            } label: {
                Text("Got It")
            }
            .accessibilityIdentifier("providers.notices.gotIt")
        } header: {
             
             
             
             
             
            Label(
                "Profile URL changes touched your edits",
                systemImage: ClashSymbol.exclamationmarkTriangle.rawValue
            )
            .accessibilityIdentifier("providers.notices")
        } footer: {
            Text(clash: ProviderNoticeCopy.summary(count: notices.count))
        }
    }
}

struct ProvidersView: View {
     
     
    @Environment(\.clashProvidersRefreshRequests) private var refreshRequests
    @Environment(\.locale) private var locale
    @StateObject private var model: ProvidersModel
     
     
     
     
    private let command: ClashCommandClient
     
    @State private var isConnected = false
    private let scope: ProviderDisplayScope
    @State private var stateWatcher = ProviderRefreshStateWatcher()
    @State private var importProvider: ProvidersModel.Row?
    @State private var isImporterPresented = false
    @State private var overridingProfile: Profile?
     
     
    @State private var editedConfiguration: EditedConfiguration?
    private let vpn: VPNController

    struct EditedConfiguration: Identifiable {
        let id: String
    }

    init(
        vpn: VPNController,
        command: ClashCommandClient,
        scope: ProviderDisplayScope = .all
    ) {
        self.command = command
        _isConnected = State(initialValue: command.isConnected)
        self.scope = scope
        self.vpn = vpn
        _model = StateObject(
            wrappedValue: ProvidersModel(vpn: vpn, command: command)
        )
    }

    var body: some View {
        ClashMacSettingsContainer {
            if let profile = model.activeProfile {
                if !model.providerNotices.isEmpty {
                    ProviderNoticesSection(notices: model.providerNotices) {
                        model.acknowledgeProviderNotices()
                    }
                }
                Section {
                     
                     
                     
                     
                     
                     
                     
                     
                    if model.liveStatus != .none {
                        liveStatusRow(model.liveStatus)
                            .accessibilityIdentifier("providers.runtime.status")
                    }
                    if !model.status.isEmpty {
                        if let failure = model.lastFailure {
                            ConfigurationFailureView(
                                failure: failure,
                                recover: { action in
                                    switch action {
                                    case .retry:
                                        model.retryLastFailure()
                                    case .editProfile:
#if os(iOS)
                                        editedConfiguration = model.activeProfile.map { EditedConfiguration(id: $0.id) }
#else
                                        overridingProfile = model.activeProfile
#endif
                                    case .editCredentials, .openProxyChains:
                                        overridingProfile = model.activeProfile
                                    case .viewDiagnostics:
                                        break
                                    }
                                }
                            )
                        } else {
                            ClashStatusMessage(text: model.statusText ?? .copy(model.status), kind: statusKind)
                        }
                    }
                } header: {
                    Text(clash: .format("Active profile · %@", [profile.label]))
                }
            }

            if visibleRows.isEmpty {
                Section {
                    ClashEmptyState(
                        title: "No Providers",
                        message: scope.emptyMessage,
                        symbol: .shippingbox
                    )
                    .listRowSeparator(.hidden)
                }
            } else {
                if scope != .rule {
                    providerSection(title: "Proxy Sources", rows: proxyRows)
                }
                if scope != .proxy {
                    providerSection(title: "Rule Sets", rows: ruleRows)
                }
                if scope == .all {
                    providerSection(title: "Other Providers", rows: otherRows)
                }
            }
        }
        .clashInsetGroupedListStyle()
        .clashPageTitle(.copy(scope.title))
         
         
         
         
         
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .primaryAction) {
                 
                 
                 
                 
                 
                if model.canCancelBatch {
                    ControlGroup {
                        Button {
                            model.cancelBatchRefresh()
                        } label: {
                            Label("Cancel", systemImage: ClashSymbol.xmark.name)
                        }
                    }
                    .clashReaderControlGroupStyle()
                    .accessibilityIdentifier("providers.refresh.cancel")
                } else {
                    ControlGroup {
                        Button {
                            model.refreshAll()
                        } label: {
                            Label(
                                "Refresh all providers",
                                systemImage: ClashSymbol.arrowTriangle2Circlepath.name
                            )
                        }
                        .disabled(model.busy || model.rows.allSatisfy { !$0.canRefresh })
                    }
                    .clashReaderControlGroupStyle()
                    .accessibilityIdentifier("providers.refreshAll")
                }
            }
        }
        .refreshable { await model.refreshAllAwaiting() }
        .clashDetailPageInsets()
        .onAppear {
            model.locale = locale
            model.load()
             
             
            if let refreshRequests { model.honorRefreshRequest(refreshRequests.token) }
        }
        .onReceive(
            refreshRequests?.$token.eraseToAnyPublisher()
                ?? Empty<Int, Never>().eraseToAnyPublisher()
        ) { token in
             
             
            model.honorRefreshRequest(token)
        }
         
         
         
         
         
         
         
        .onReceive(command.$isConnected) { connected in
            guard connected != isConnected else { return }
            isConnected = connected
            Task { @MainActor [weak held = model] in held?.refreshRuntimeCatalog() }
        }
         
         
         
         
        .onReceive(NotificationCenter.default.publisher(for: .clashProviderContentChanged)) { _ in
            model.reloadForOutsideChange()
        }
        .onAppear {
            stateWatcher.start(directory: ProviderRefreshStateWatcher.stateDirectory) {
                model.reloadForOutsideChange()
            }
        }
        .onDisappear { stateWatcher.stop() }
        .clashSheet(item: $overridingProfile) { profile in
            ProfileOverrideView(profile: profile, rawYAML: nil) {
                try model.updateActiveProfile($0)
            }
            .clashModalPresentation(.page)
        }
#if os(iOS)
        .clashSheet(item: $editedConfiguration) { edited in
            ConfigurationEditorHost(vpn: vpn, profileID: edited.id, selections: command)
                .clashModalPresentation(.page)
        }
#endif
        .clashSheet(isPresented: Binding(
            get: { model.batchReport != nil },
            set: { if !$0 { model.dismissBatchReport() } }
        )) {
            Group {
                if let report = model.batchReport {
                    BatchUpdateReportView(
                        report: report,
                        isRunning: model.busy,
                        cancel: { model.cancelBatchRefresh() },
                        retry: { model.retryBatchItem(id: $0) },
                        dismiss: { model.dismissBatchReport() },
                        inFlight: model.syncingProviders.sorted()
                    )
                }
            }
            .clashModalPresentation(.page)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let row = importProvider, let url = urls.first else { return }
                model.sideLoad(provider: row.name, fileURL: url)
            case .failure(let error):
                model.reportImportFailure(error)
            }
            importProvider = nil
        }
    }

    private var visibleRows: [ProvidersModel.Row] {
        scope.filtered(model.rows)
    }

    private var proxyRows: [ProvidersModel.Row] {
        model.rows.filter { $0.kind?.lowercased() == "proxy" }
    }

    private var ruleRows: [ProvidersModel.Row] {
        model.rows.filter { $0.kind?.lowercased() == "rule" }
    }

    private var otherRows: [ProvidersModel.Row] {
        model.rows.filter {
            guard let kind = $0.kind?.lowercased() else { return true }
            return kind != "proxy" && kind != "rule"
        }
    }

    private var statusKind: ClashStatusKind {
         
        if let tone = model.statusTone { return tone }
         
        if model.statusIsNotice { return .information }
        let normalized = model.status.lowercased()
        if normalized.contains("failed") || normalized.hasPrefix("no ") { return .error }
        if normalized.contains("updating") || normalized.contains("materializing")
            || normalized.contains("loading") { return .information }
         
         
        if normalized.contains("cancelled") { return .information }
        return .success
    }

    @ViewBuilder
    private func providerSection(title: String, rows: [ProvidersModel.Row]) -> some View {
        if !rows.isEmpty {
             
             
            Section {
                ForEach(rows) { row in
                    ProviderRow(
                        row: row,
                        status: statusLine(row),
                        isBusy: model.busyProvider == row.name
                            || model.syncingProviders.contains(row.name)
                            || model.healthCheckingProvider == row.name,
                        canCheckHealth: isConnected
                            && row.runtime?.healthCheckAvailable == true,
                        canConfigure: true,
                        checkHealth: { model.checkHealth(provider: row.name) },
                        sideLoad: {
                            importProvider = row
                            isImporterPresented = true
                        },
                        refresh: { model.refresh(provider: row.name) }
                    )
                    .disabled(
                        (model.busy && model.busyProvider != row.name && !model.syncingProviders.contains(row.name))
                            || (model.healthCheckingProvider != nil
                                && model.healthCheckingProvider != row.name)
                    )
                }
            } header: {
                Text(clash: .copy(title))
            }
        }
    }

    private func statusLine(_ row: ProvidersModel.Row) -> String {
        ProviderRowSummary.text(for: row, locale: locale, now: Date())
    }
}

 
 
 
 
enum ProviderRowSummary {
    static func text(for row: ProvidersModel.Row, locale: Locale, now: Date) -> String {
        var parts: [String] = []
        let isRule = row.kind?.lowercased() == "rule"
        if let count = row.shownCount {
            parts.append(ClashCopy.format(isRule ? "%@ rules" : "%@ proxies", locale: locale, String(count)))
        }
        if let size = row.sizeBytes { parts.append(ByteCountFormatter.string(Int64(size))) }
         
         
         
        if let updatedAt = row.shownUpdatedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            formatter.locale = locale
            parts.append(formatter.localizedString(for: updatedAt, relativeTo: now))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

extension ProvidersView {
     
     
    @ViewBuilder
    func liveStatusRow(_ status: ProvidersModel.LiveStatus) -> some View {
        switch status {
        case .none:
            EmptyView()
        case .disconnected:
            Label {
                Text(clash: .copy("Not connected — showing the last known status"))
            } icon: {
                Image(systemName: ClashSymbol.infoCircle.name).accessibilityHidden(true)
            }
            .foregroundStyle(.secondary)
        case .loading:
            HStack {
                ProgressView()
                    .accessibilityLabel(Text(clash: .copy("Loading")))
                Spacer()
            }
        case .checkingHealth:
            HStack(spacing: ClashTheme.Spacing.compact) {
                Text(clash: .copy("Checking which nodes work…"))
                    .foregroundStyle(.secondary)
                Spacer()
                ProgressView()
            }
        case .unavailable(let reason):
            liveFailure("Can't refresh status right now", reason: reason)
        case .healthCheckFailed(let reason):
            liveFailure("Couldn't check the nodes", reason: reason)
        }
    }

    private func liveFailure(_ key: String, reason: String?) -> some View {
        Label {
            Text(clash: reason.map { .format("%@: %@", [ClashCopy.string(key, locale: locale), $0]) } ?? .copy(key))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: ClashSymbol.exclamationmarkTriangle.name)
        }
        .foregroundStyle(.orange)
    }
}

struct ProviderRow: View {
    @Environment(\.locale) private var locale
    let row: ProvidersModel.Row
    let status: String
    let isBusy: Bool
    let canCheckHealth: Bool
    let canConfigure: Bool
    let checkHealth: () -> Void
    let sideLoad: () -> Void
    let refresh: () -> Void

    private var isRule: Bool { row.kind?.lowercased() == "rule" }

    var body: some View {
        HStack(alignment: .top, spacing: ClashTheme.Spacing.row) {
            ClashIconWell(
                symbol: isRule ? .listBulletRectangle : .serverRack,
                tint: isRule ? .orange : .purple
            )

            VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                Text(row.name)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                 
                 
                if !(status == "—" && row.note != nil) {
                    Text(status)
                        .font(ClashPlatformLayout.pageUsesSystemSettingsIdiom ? ClashMacSettingsType.value : .caption)
                        .foregroundStyle(.secondary)
                }
                if let note = row.note, note.isFailure {
                     
                     
                     
                     
                     
                    Label {
                        Text(clash: note.displayText(locale: locale))
                    } icon: {
                        Image(systemName: ClashSymbol.exclamationmarkTriangle.name)
                    }
                    .font(ClashPlatformLayout.pageUsesSystemSettingsIdiom ? ClashMacSettingsType.value : .caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("providers.row.loadFailure.\(row.name)")
                } else if let note = row.note, note.isShown {
                     
                     
                     
                     
                    Text(clash: note.displayText(locale: locale))
                        .font(ClashPlatformLayout.pageUsesSystemSettingsIdiom ? ClashMacSettingsType.value : .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("providers.row.note.\(row.name)")
                }
                if !isRule, let runtime = row.runtime, let health = Self.healthText(runtime) {
                    Label {
                        Text(clash: health)
                    } icon: {
                        Image(systemName: healthSymbol(runtime).name)
                    }
                        .font(ClashPlatformLayout.pageUsesSystemSettingsIdiom ? ClashMacSettingsType.value : .caption)
                        .foregroundStyle(healthColor(runtime))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let info = row.shownSubscriptionInfo {
                    SubscriptionInfoView(info: info)
                }
                 
                 
                 
                if let kind = row.kind,
                   !ClashPlatformLayout.pageUsesSystemSettingsIdiom {
                    ClashStatusBadge(
                        title: kind.capitalized,
                        tint: isRule ? .orange : .purple,
                        role: .category
                    )
                }
            }

            Spacer(minLength: ClashTheme.Spacing.compact)

            if isBusy {
                ProgressView()
                    .frame(
                        width: ClashClientUI.ClashTheme.Control
                            .minimumHitTarget,
                        height: ClashClientUI.ClashTheme.Control
                            .minimumHitTarget
                    )
            } else if canConfigure || (!isRule && canCheckHealth),
                      !ClashPlatformLayout.pageUsesSystemSettingsIdiom {
                 
                 
                 
                 
                 
                Menu {
                    rowActions
                } label: {
                    Image(systemName: ClashSymbol.ellipsisCircle.name)
                        .font(.title3)
                        .frame(
                            width: ClashClientUI.ClashTheme.Control
                                .minimumHitTarget,
                            height: ClashClientUI.ClashTheme.Control
                                .minimumHitTarget
                        )
                }
                .accessibilityLabel("Actions for \(row.name)")
                .accessibilityIdentifier("provider.menu.\(row.name)")
            }
        }
        .contextMenu {
             
             
             
            if !isBusy, ClashPlatformLayout.pageUsesSystemSettingsIdiom, canConfigure || (!isRule && canCheckHealth) {
                rowActions
            }
        }
        .padding(.vertical, ClashTheme.Spacing.tight)
    }

     
     
    @ViewBuilder
    private var rowActions: some View {
                if !isRule {
                    Button(action: checkHealth) {
                        Label("Check health", systemImage: ClashSymbol.waveformPathEcg.name)
                    }
                    .disabled(!canCheckHealth)
                    .accessibilityIdentifier("provider.health.\(row.name)")
                    if canConfigure { Divider() }
                }
                if canConfigure, row.canRefresh {
                    Button(action: refresh) {
                        Label("Sync provider", systemImage: ClashSymbol.arrowClockwise.name)
                    }
                     
                    .accessibilityLabel("Sync \(row.name)")
                    .accessibilityIdentifier("provider.refresh.\(row.name)")
                }
                if canConfigure {
                    Button(action: sideLoad) {
                        Label("Load local file", systemImage: ClashSymbol.squareAndArrowDown.name)
                    }
                    .accessibilityIdentifier("provider.sideload.\(row.name)")
                }
    }

     
     
     
    static func healthText(_ runtime: ProviderRuntimeSummary) -> ClashDisplayText? {
        guard runtime.healthCheckAvailable, runtime.entryCount > 0 else { return nil }
        return .format(
            "%@ available · %@ unavailable",
            [String(runtime.healthyCount ?? 0), String(runtime.unhealthyCount ?? 0)]
        )
    }

     
     
     
     
    enum HealthTone: Equatable { case allUp, someDown, noneUp, unknown }

    static func healthTone(_ runtime: ProviderRuntimeSummary) -> HealthTone {
        guard runtime.healthCheckAvailable else { return .unknown }
        if (runtime.unhealthyCount ?? 0) == 0 { return .allUp }
        return (runtime.healthyCount ?? 0) == 0 ? .noneUp : .someDown
    }

    private func healthSymbol(_ runtime: ProviderRuntimeSummary) -> ClashSymbol {
        switch Self.healthTone(runtime) {
        case .allUp: return .checkmarkCircleFill
        case .noneUp: return .exclamationmarkTriangle
        case .someDown, .unknown: return .infoCircle
        }
    }

    private func healthColor(_ runtime: ProviderRuntimeSummary) -> Color {
        switch Self.healthTone(runtime) {
        case .allUp: return .green
        case .noneUp: return .orange
        case .someDown, .unknown: return .secondary
        }
    }
}

 
 
 
 
 
enum ProviderRefreshService {
     
     
     
     
     
    struct ManyResult {
        var pointer: ActiveConfigurationPointer?
        var published: [String] = []
        var failed: [(name: String, error: Error)] = []
         
         
        var superseded = false
         
        var switched = false
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @MainActor
    static func publishMany(
        names: [String],
        republishingAnyway: Bool = false,
        profile: Profile,
        store: ConfigResourceStore,
        container: URL,
        vpn: VPNController,
        expectedActive: ActiveConfigurationPointer?,
        downloadRound: ProviderDownloadRound = ProviderDownloadRound(),
        scripts: ScriptEngine.Caller = .surfaced
    ) async throws -> ManyResult {
        try await publishMany(
            names: names, republishingAnyway: republishingAnyway, profile: profile, store: store,
            coordinator: try vpn.activationCoordinator(store: store, container: container),
            expectedActive: expectedActive, downloadRound: downloadRound, scripts: scripts)
    }

     
    @MainActor
    static func publishMany(
        names: [String],
        republishingAnyway: Bool = false,
        profile: Profile,
        store: ConfigResourceStore,
        coordinator: ProfileActivationCoordinator,
        expectedActive: ActiveConfigurationPointer?,
        downloadRound: ProviderDownloadRound = ProviderDownloadRound(),
        scripts: ScriptEngine.Caller = .surfaced
    ) async throws -> ManyResult {
        var expected = expectedActive
        for attempt in 0..<3 {
            do {
                return try await publishMany(names: names, republishingAnyway: republishingAnyway) { remaining in
                    try await coordinator.refreshProviders(
                        named: remaining, profile: profile, expectedActive: expected,
                        downloadRound: downloadRound, scripts: scripts).pointer
                }
            } catch where ProfileActivationCoordinator.lostToASwitch(error) {
                var result = ManyResult()
                guard let now = store.activeIdentityOrNil(), now.profileID == profile.id else {
                    result.switched = true
                    return result
                }
                 
                 
                 
                guard attempt < 2 else {
                    result.superseded = true
                    return result
                }
                expected = now
            }
        }
        var result = ManyResult()
        result.superseded = true
        return result
    }

     
     
     
     
     
    static func publishMany(
        names: [String],
        republishingAnyway: Bool = false,
        publish: ([String]) async throws -> ActiveConfigurationPointer
    ) async throws -> ManyResult {
        var result = ManyResult()
        var remaining = names
        guard republishingAnyway || !remaining.isEmpty else { return result }
        while true {
            try Task.checkCancellation()
            do {
                result.pointer = try await publish(remaining)
                result.published = remaining
                return result
            } catch let failures as ProviderDownloadFailuresError {
                let named = Set(failures.failures.map(\.provider)).intersection(remaining)
                guard !named.isEmpty else { throw failures }
                for failure in failures.failures where named.contains(failure.provider) {
                    result.failed.append((failure.provider, failure.underlying))
                }
                remaining.removeAll { named.contains($0) }
            } catch let failure as ProviderValidationFailure {
                guard remaining.contains(failure.provider) else { throw failure }
                result.failed.append((failure.provider, failure.underlying))
                remaining.removeAll { $0 == failure.provider }
            }
            if remaining.isEmpty && !republishingAnyway { return result }
        }
    }

     
     
     
     
     
     
     
     
    @MainActor
    static func coreFetchedProviders(in catalog: ProviderCatalog?, profile: Profile, store: ConfigResourceStore,
                                     container: URL, vpn: VPNController) async -> Set<String> {
        if let recorded = catalog?.coreFetchedProviders { return recorded }
        return await plannedCatalog(profile: profile, store: store, container: container, vpn: vpn)?
            .coreFetchedProviders ?? []
    }

     
     
     
    @MainActor
    static func plannedCatalog(profile: Profile, store: ConfigResourceStore, container: URL,
                               vpn: VPNController) async -> ProviderCatalog? {
        guard let coordinator = try? vpn.activationCoordinator(store: store, container: container) else { return nil }
        return await Task.detached(priority: .userInitiated) {
            try? coordinator.providerRetryCatalog(profile: profile)
        }.value
    }

}

 
 
 
 
 
 
enum PublishedRuntimeHandover {
     
     
     
    @MainActor
    @discardableResult
    static func apply(vpn: VPNController, profileID: String?) async -> TunnelApplyOutcome? {
        await vpn.applyPublished(forProfile: profileID, startsWhenDown: false)
    }

     
     
    static func hands(_ published: ActiveConfigurationPointer, forProfile profileID: String?) -> Bool {
        profileID == nil || published.profileID == profileID
    }

     
     
     
     
     
     
     
     
    static let waitLimitNanoseconds: UInt64 = 30_000_000_000

     
    enum Wait: Equatable {
         
        case answered(TunnelApplyOutcome?)
         
        case timedOut
         
        case cancelled

         
         
         
        var outcome: TunnelApplyOutcome? {
            if case .answered(let outcome) = self { return outcome }
            return nil
        }
    }

     
     
     
     
     
     
    @MainActor
    static func bounded(limitNanoseconds: UInt64 = waitLimitNanoseconds,
                        _ handOver: @escaping @MainActor () async -> TunnelApplyOutcome?,
                        landedLate: @escaping @MainActor (TunnelApplyOutcome?) -> Void) async -> Wait {
        let race = Race()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                race.install(continuation)
                Task { @MainActor in
                    let outcome = await handOver()
                    if !race.answer(.answered(outcome)) { landedLate(outcome) }
                }
                race.timer = Task { @MainActor in
                    PublishedRuntimeHandover.sleepingTimers += 1
                    defer { PublishedRuntimeHandover.sleepingTimers -= 1 }
                    try? await Task.sleep(nanoseconds: limitNanoseconds)
                    guard !Task.isCancelled else { return }
                    _ = race.answer(.timedOut)
                }
            }
        } onCancel: {
            Task { @MainActor in _ = race.answer(.cancelled) }
        }
    }

     
    @MainActor private(set) static var sleepingTimers = 0

     
     
     
     
     
     
     
     
     
     
     
    @MainActor
    static func lateLanding(
        since start: Date,
        line: @escaping @MainActor (_ took: String, _ outcome: String) -> String
    ) -> @MainActor (TunnelApplyOutcome?) -> Void {
        { late in
            ClashLogStore.shared.append(
                line(String(format: "%.2f", Date().timeIntervalSince(start)),
                     late.map { String(describing: $0) } ?? "nil"),
                stream: .app, level: .info)
            NotificationCenter.default.post(name: .clashProviderContentChanged, object: nil)
        }
    }

     
     
     
    @MainActor
    private final class Race {
        var timer: Task<Void, Never>?
        private var continuation: CheckedContinuation<Wait, Never>?
        private var given: Wait?

        func install(_ waiting: CheckedContinuation<Wait, Never>) {
            if let given {
                waiting.resume(returning: given)
            } else {
                continuation = waiting
            }
        }

         
        func answer(_ wait: Wait) -> Bool {
            guard given == nil else { return false }
            given = wait
            timer?.cancel()
            timer = nil
            continuation?.resume(returning: wait)
            continuation = nil
            return true
        }
    }

     
     
     
     
     
     
     
    static func readsNodesAgain(after note: Notification, isConnected: Bool) -> Bool {
        isConnected && note.userInfo?["profileID"] == nil
    }
}

 
 
 
 
 
@MainActor
final class NodeListRereads {
    private var running = false
    private var owed: (@MainActor () async -> Void)?

    func ask(_ read: @escaping @MainActor () async -> Void) {
        guard !running else {
            owed = read
            return
        }
        running = true
        Task { @MainActor in
            var next: (@MainActor () async -> Void)? = read
            while let current = next {
                await current()
                next = owed
                owed = nil
            }
            running = false
        }
    }
}
