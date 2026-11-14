import ClashClientUI
import SwiftUI
#if os(macOS)
import AppKit
#endif

 
 
 
 
 
 
@MainActor
final class GeoResourcesModel: ObservableObject {
    @Published private(set) var entries: [GeoResourceInventory.Entry] = []
    @Published private(set) var syncing: Set<GeoResource> = []
    @Published private(set) var errors: [GeoResource: ConfigurationFailure] = [:]
    @Published private(set) var successes: [GeoResource: String] = [:]
    @Published private(set) var batchReport: BatchUpdateReport?
    @Published private(set) var isBatchSyncing = false
     
     
    @Published private(set) var configuration = ConfigurationGeoSettings.silent
    private var batchTask: Task<Void, Never>?

    private var homeDir: URL? {
        ClashAppIdentifiers.appGroupContainer?
            .appendingPathComponent("working")
    }

    func load() {
        guard let homeDir else { return }
        entries = GeoResourceInventory.scan(homeDir: homeDir)
    }

     
    func loadConfiguration() async {
        configuration = await Task.detached(priority: .utility) { ConfigurationGeoSettings.active() }.value
    }

    var lastFullSyncDescription: String {
        guard let date = GeoResourceSettings.lastSync() else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    func url(for resource: GeoResource) -> String {
        GeoResourceSettings.url(for: resource, following: configuration)
    }

    func urlIsTheConfigurations(_ resource: GeoResource) -> Bool {
        configuration.urls[resource] != nil
    }

    func sync(_ resource: GeoResource) {
        guard let homeDir, !syncing.contains(resource) else { return }
        syncing.insert(resource)
        errors[resource] = nil
        successes[resource] = nil
        let url = self.url(for: resource)
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.syncing.remove(resource)
                self.load()
            }
            do {
                try await self.syncResource(resource, url: url, homeDir: homeDir)
                self.successes[resource] = "\(resource.fileName) synced"
            } catch {
                self.errors[resource] = ConfigurationFailureClassifier.classify(
                    error,
                    context: .geodata,
                    preservesLastKnownGood: true
                )
            }
        }
    }

    func syncAll() {
        guard batchTask == nil, let homeDir else { return }
        batchReport = BatchUpdateReport(
            title: "Geo Resource Sync",
            expectedCount: GeoResource.allCases.count
        )
        isBatchSyncing = true
        batchTask = Task { [weak self] in
            guard let self else { return }
            for resource in GeoResource.allCases {
                if Task.isCancelled {
                    self.markBatchCancelled()
                    break
                }
                self.syncing.insert(resource)
                self.errors[resource] = nil
                self.successes[resource] = nil
                do {
                    try await self.syncResource(
                        resource,
                        url: self.url(for: resource),
                        homeDir: homeDir
                    )
                    self.successes[resource] = "\(resource.fileName) synced"
                    self.recordBatchItem(
                        resource: resource,
                        state: .updated,
                        message: "The resource was validated and saved atomically."
                    )
                } catch is CancellationError {
                    self.markBatchCancelled()
                    self.syncing.remove(resource)
                    break
                } catch {
                    self.recordBatchFailure(error, resource: resource)
                }
                self.syncing.remove(resource)
                self.load()
            }
            if self.batchIsCompleteAndSuccessful {
                GeoResourceSettings.recordSync()
            }
            self.syncing.removeAll()
            self.isBatchSyncing = false
            self.batchTask = nil
            self.load()
        }
    }

    func cancelBatchSync() {
        batchTask?.cancel()
    }

    func dismissBatchReport() {
        guard !isBatchSyncing else { return }
        batchReport = nil
    }

    func retryBatchItem(id: String) {
        guard batchTask == nil,
              let resource = GeoResource(rawValue: id),
              let homeDir else { return }
        isBatchSyncing = true
        syncing.insert(resource)
        batchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.syncResource(
                    resource,
                    url: self.url(for: resource),
                    homeDir: homeDir
                )
                self.successes[resource] = "\(resource.fileName) synced"
                self.errors[resource] = nil
                self.recordBatchItem(
                    resource: resource,
                    state: .updated,
                    message: "The resource was validated and saved atomically."
                )
            } catch is CancellationError {
                self.markBatchCancelled()
            } catch {
                self.recordBatchFailure(error, resource: resource)
            }
            if self.batchIsCompleteAndSuccessful {
                GeoResourceSettings.recordSync()
            }
            self.syncing.remove(resource)
            self.isBatchSyncing = false
            self.batchTask = nil
            self.load()
        }
    }

    private func syncResource(_ resource: GeoResource, url: String, homeDir: URL) async throws {
        try Task.checkCancellation()
        let plan = RemoteResourcePlan(
            providers: [],
            geodata: [.init(kind: resource.planKind, url: url)],
            notices: [],
            errors: []
        )
        try await GeodataManager(downloader: ResourceDownloader()).stage(
            plan: plan,
            homeDir: homeDir,
            maxBytesEach: ProfileActivationCoordinator.maxGeodataBytes
        )
    }

    private var batchIsCompleteAndSuccessful: Bool {
        guard let report = batchReport else { return false }
        return !report.wasCancelled
            && report.completedCount == report.expectedCount
            && report.failedCount == 0
    }

    private func recordBatchFailure(_ error: Error, resource: GeoResource) {
        let failure = ConfigurationFailureClassifier.classify(
            error,
            context: .geodata,
            preservesLastKnownGood: true
        )
        errors[resource] = failure
        guard let failure else { return }
        recordBatchItem(
            resource: resource,
            state: .failed,
             
             
            message: nil,
            failure: failure
        )
    }

    private func recordBatchItem(
        resource: GeoResource,
        state: BatchUpdateState,
        message: String?,
        failure: ConfigurationFailure? = nil
    ) {
        guard var report = batchReport else { return }
        report.wasCancelled = false
        report.record(BatchUpdateItem(
            id: resource.rawValue,
            label: resource.title,
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
}

struct ResourcesView: View {
    @Environment(\.locale) private var locale
    @StateObject private var model = GeoResourcesModel()

     
     
     
     
     
     
     
     
     
    @State private var deviations: ConfigDeviationReport?

    var body: some View {
        ClashMacSettingsContainer {
            Section {
                Button {
                    model.syncAll()
                } label: {
                    if model.isBatchSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Sync all Geo resources", systemImage: ClashSymbol.arrowTriangle2Circlepath.name)
                    }
                }
                .clashMacFormActionChrome()
                .disabled(model.isBatchSyncing)
                .accessibilityIdentifier("resources.sync-all")
            } footer: {
                 
                 
                 
                 
                 
                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                     
                     
                    Text("Automatic updates and download addresses are set in the configuration editor.")
                    Text(clash: .format(
                        "Last full refresh: %@.",
                        [
                            model.lastFullSyncDescription == "Never"
                                ? ClashCopy.string("Never", locale: locale)
                                : model.lastFullSyncDescription,
                        ]
                    ))
                }
            }

            ForEach(model.entries, id: \.resource) { entry in
                GeoResourceSection(
                    entry: entry,
                    url: model.url(for: entry.resource),
                    urlIsTheConfigurations: model.urlIsTheConfigurations(entry.resource),
                    isSyncing: model.syncing.contains(entry.resource),
                    error: model.errors[entry.resource],
                    success: model.successes[entry.resource],
                    sync: { model.sync(entry.resource) })
            }
            ConfigDeviationSection(
                report: deviations,
                fields: RunningCoreDeviations.fields(for: [.geoData]),
                identifierPrefix: "resource.deviation"
            )
        }
        .clashInsetGroupedListStyle()
         
         
         
         
         
         
        .clashPageTitle("Resources")
        .onAppear { model.load() }
        .task {
            await model.loadConfiguration()
            deviations = await Task.detached(priority: .utility) {
                RunningCoreDeviations.activeProfileReport()
            }.value
        }
        .clashSheet(isPresented: Binding(
            get: { model.batchReport != nil },
            set: { if !$0 { model.dismissBatchReport() } }
        )) {
            Group {
                if let report = model.batchReport {
                    BatchUpdateReportView(
                        report: report,
                        isRunning: model.isBatchSyncing,
                        cancel: { model.cancelBatchSync() },
                        retry: { model.retryBatchItem(id: $0) },
                        dismiss: { model.dismissBatchReport() }
                    )
                }
            }
            .clashModalPresentation(.page)
        }
    }
}

private struct GeoResourceSection: View {
    let entry: GeoResourceInventory.Entry
    let url: String
     
     
    let urlIsTheConfigurations: Bool
    let isSyncing: Bool
    let error: ConfigurationFailure?
    let success: String?
    let sync: () -> Void

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: ClashTheme.Spacing.row) {
                ClashIconWell(symbol: resourceSymbol, tint: resourceTint)
                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                    Text(entry.resource.fileName)
                        .font(.body)
                    Text(statusLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("resource.status.\(entry.resource.rawValue)")
            Text(url)
                .font(ClashPlatformLayout.pageUsesSystemSettingsIdiom ? ClashMacSettingsType.mono : .caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if urlIsTheConfigurations {
                Text(clash: .copy("Set by the configuration in use."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ClashGlassEffectContainer(spacing: ClashTheme.Spacing.row) {
                HStack(spacing: ClashTheme.Spacing.row) {
                    Button {
                        sync()
                    } label: {
                        if isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Sync", systemImage: ClashSymbol.arrowTriangle2Circlepath.name)
                        }
                    }
                    .clashSecondaryActionButtonStyle()
                    .clashMacFormActionChrome()
                    .disabled(isSyncing)
                    .accessibilityIdentifier("resource.sync.\(entry.resource.rawValue)")
                }
            }
            if let error {
                ConfigurationFailureView(failure: error) { action in
                    if action == .retry { sync() }
                }
                    .accessibilityIdentifier("resource.error.\(entry.resource.rawValue)")
            } else if let success {
                ClashStatusMessage(text: .copy(success), kind: .success)
                    .accessibilityIdentifier("resource.success.\(entry.resource.rawValue)")
            }
        } header: {
            Text(entry.resource.title)
        }
    }

    private var statusLine: String {
        guard let size = entry.sizeBytes else { return "Not downloaded" }
        var line = ByteCountFormatter.string(Int64(size))
        if let updatedAt = entry.updatedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            line += " · " + formatter.localizedString(for: updatedAt, relativeTo: Date())
        }
        return line
    }

    private var resourceSymbol: ClashSymbol {
        switch entry.resource {
        case .geoip: return .map
        case .geosite: return .globeAsiaAustralia
        case .mmdb: return .externaldrive
        case .asn: return .point3ConnectedTrianglepathDotted
        }
    }

    private var resourceTint: Color {
        switch entry.resource {
        case .geoip: return .blue
        case .geosite: return .green
        case .mmdb: return .purple
        case .asn: return .orange
        }
    }
}
