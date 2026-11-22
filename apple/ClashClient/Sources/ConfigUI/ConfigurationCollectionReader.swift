import ClashClientKit
import ClashClientUI
import Combine
import Foundation

 
 
 
 
 
 
 
 
@MainActor
final class ConfigurationCollectionReader: ObservableObject {
    let model: ProfilesViewModel
    let entry: ConfigurationCollectionEntry
     
     
     
     
    let running: RunningProvidersReader
     
     
    var locale: Locale = AppPreferences.language().localeOverride ?? .current
    @Published private(set) var page = ConfigurationCollectionContentBridge.Page()
    @Published private(set) var rows: [ClashConfigurationReadRow] = []
    @Published var query = ""
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var requestID = UUID()
     
     
     
    @Published private(set) var updating = false
     
     
    @Published private(set) var updatePhase: String?
    @Published private(set) var updateFailures: [String] = []
     
     
     
    @Published private(set) var runHasThis = false
     
     
     
     
    @Published private var shownCopy: ConfigurationCollectionContentBridge.Cache?
     
     
     
     
     
     
     
    @Published private var updateWord: String?
     
     
    private var updateWordAt: Date?
     
    private var relay: AnyCancellable?

    init(model: ProfilesViewModel, entry: ConfigurationCollectionEntry) {
        self.model = model
        self.entry = entry
        running = RunningProvidersReader(container: { [model] in model.appGroupContainer })
        relay = running.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

     
     
     
     
     
    private var inUse: ConfigurationCollectionContentBridge.RunningProviders.InUse? {
        running.current?.inUse(of: entry, copy: shownCopy)
    }

     
    func status(locale: Locale) -> String {
        var parts = [entry.source.displayLabel(locale: locale)]
        if let updateWord { parts.insert(ClashCopy.string(updateWord, locale: locale), at: 0) }
         
         
         
         
         
        let inUse = self.inUse
        parts += ClashConfigurationCollectionCopy.members(of: entry.collection, count: page.count, inUse: inUse?.count,
                                                          inUseIsThisCopy: inUse?.ofThisCopy ?? false)
            .map { $0.resolved(locale: locale) }
        if let date = page.updatedAt {
            parts.append(ClashCopy.format("Updated on %@", locale: locale,
                                          date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))))
        }
        if let message = page.statusMessage(locale: locale) { parts.append(message) }
        return parts.joined(separator: " · ")
    }

    var shownError: String? {
        let lines = (error.map { [$0] } ?? []) + updateFailures
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

     
     
    func say(_ error: Error) {
        self.error = ClashErrorCopy.message(error, locale: locale)
    }

     
     
     
     
     
     
     
    func followRun(inFlight: Bool) {
        let wasInFlight = runHasThis
        guard inFlight != wasInFlight else { return }
        runHasThis = inFlight
        if wasInFlight && !inFlight { Task { await reloadIfTheCopyChanged(); await running.reload() } }
    }

     
     
     
     
     
     
     
    func update() async {
        guard !updating else { return }
        updating = true; updateFailures = []; updateWord = nil; updateWordAt = nil
        defer { updating = false; updatePhase = nil }
        if model.isUpdatingNodeLibrary || model.isUpdatingRuleCollections {
            updatePhase = ClashCopy.string("Waiting for the current update to finish…", locale: locale)
        }
         
         
         
        await model.pageLibraryWrite { [self] in
            updatePhase = nil
            do {
                guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                let source = try await Task.detached { [entry] in try store.payload(.init(entry.source)) }.value
                var libraryFailure: Error?
                var refreshed = ConfigurationCollectionContentBridge.CollectionRefresh.downloaded
                do { refreshed = try await ConfigurationCollectionContentBridge.refresh(entry, source: source, inUse: model.providerCatalogInUse()) }
                catch { libraryFailure = error }
                if libraryFailure == nil, refreshed == .downloaded { await load() }
                updatePhase = ClashCopy.string("Applying to the configuration in use…", locale: locale)
                 
                 
                 
                 
                 
                let take: ProfilesViewModel.CollectionTake
                switch (libraryFailure, refreshed) {
                case (nil, .downloaded):
                    take = await model.takeUpdatedCollections([entry], scripts: .surfaced, locale: locale)
                case (nil, .coreOwned):
                    take = await model.takeUpdatedCollections([], coreOwned: [entry], scripts: .surfaced, locale: locale)
                default:
                    take = await model.takeUpdatedCollections([], failed: [entry], scripts: .surfaced, locale: locale)
                }
                updateFailures = ProfilesViewModel.joiningReasons(
                    libraryFailure.map { [ClashErrorCopy.message($0, locale: locale)] } ?? [], take.failures)
                updateWord = ProfilesViewModel.CollectionTake.word(
                    for: entry.id, take: take, libraryCopyIn: libraryFailure == nil && refreshed == .downloaded)
                updateWordAt = Date()
            } catch {
                 
                updateFailures = [ClashErrorCopy.message(error, locale: locale)]
            }
        }
        await running.reload()
    }

     
     
     
     
     
     
     
    func reloadIfTheCopyChanged() async {
        let entry = self.entry
        let copy = await Task.detached { ConfigurationCollectionContentBridge.libraryCopyRecord(of: entry) }.value
        guard copy != shownCopy else { return }
        await load()
    }

    func load(offset: Int = 0) async {
        let token = UUID(); requestID = token; loading = true; error = nil
        defer { if requestID == token { loading = false } }
        do {
            let entry = self.entry
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let source = try await Task.detached { try store.payload(.init(entry.source)) }.value
            let search = query
            let loaded = try await Task.detached {
                 
                 
                 
                let copy = ConfigurationCollectionContentBridge.libraryCopyRecord(of: entry)
                let page = try ConfigurationCollectionContentBridge.page(entry, source: source, query: search, offset: offset)
                let rows: [ClashConfigurationReadRow]
                if entry.id.kind == .nodes {
                    rows = page.nodes.enumerated().map { index, json in
                        let node = try? OrderedJSON.parse(json)
                        return .init(title: node?.topLevelValue("name")?.foundationValue as? String ?? "", subtitle: node?.topLevelValue("type")?.foundationValue as? String, nodeIndex: index)
                    }
                } else { rows = page.lines.map { .init(title: $0) } }
                return (page, rows, copy)
            }.value
            guard requestID == token, !Task.isCancelled else { return }
            if offset == 0 {
                page = loaded.0
                rows = loaded.1
                shownCopy = loaded.2
            } else {
                 
                 
                let base = page.nodes.count
                var next = loaded.0
                next.nodes = page.nodes + loaded.0.nodes
                page = next
                rows += loaded.1.map { row in
                    row.nodeIndex.map { .init(title: row.title, subtitle: row.subtitle, nodeIndex: base + $0) } ?? row
                }
            }
             
             
             
            if let said = updateWordAt,
               !ClashConfigurationCollectionCopy.updateWordStands(saidAt: said, lineUpdatedAt: page.updatedAt) {
                updateWord = nil
                updateWordAt = nil
            }
        } catch {
            guard requestID == token else { return }
            self.error = ClashErrorCopy.message(error, locale: locale)
        }
    }
}
