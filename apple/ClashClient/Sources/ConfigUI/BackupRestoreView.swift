import ClashClientUI
import SwiftUI
import UniformTypeIdentifiers

private struct PreparedBackupRestore: Identifiable {
    let id = UUID()
    let archive: BackupArchive
    let sourceTitle: String
}

 
 
 
 
struct BackupRestoreView: View {
     
     
     
    @State private var status: BackupStatus?
    @Environment(\.locale) private var locale
    @State private var exportDocument: BackupDocument?
    @State private var exporting = false
    @State private var showsImporter = false
    @State private var preparedRestore: PreparedBackupRestore?

    @ObservedObject private var autoBackup = ICloudAutoBackup.shared
    @State private var showsAutoBackupConsent = false
    @State private var icloud: ICloudBackupStore?
    @State private var icloudChecked = false
    @State private var icloudBusy = false
    @State private var icloudEntries: [ICloudBackupStore.Entry] = []

    @AppStorage("backup.restore.scope", store: GlobalConfig.appGroupDefaults)
    private var restoreScopeRaw: String = BackupRestoreScope.allData.rawValue

     
    @Environment(\.clashBackupDataScope) private var dataScope

    private var workingDir: URL? {
        BackupSandbox.workingDirectory(
            scope: dataScope,
            appGroupContainer: ClashAppIdentifiers.appGroupContainer
        )
    }

    var body: some View {
        if dataScope == .reviewUnavailable {
            reviewUnavailableBody
        } else {
            operatingBody
        }
    }

     
     
     
     
    private var reviewUnavailableBody: some View {
        ClashMacSettingsContainer {
            Section {
                Text("This review session has no disposable container, so Backup & Restore is off. It never falls back to installed data.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("backup.review.unavailable")
            }
        }
        .clashInsetGroupedListStyle()
        .accessibilityIdentifier("backup.root")
        .clashPageTitle("Backup & Restore")
    }

    private var operatingBody: some View {
        ClashMacSettingsContainer {
            Section("Restore Options") {
                Picker("Data", selection: $restoreScopeRaw) {
                    ForEach(BackupRestoreScope.allCases) { scope in
                        Text(clash: .copy(scope.title)).tag(scope.rawValue)
                    }
                }
                .accessibilityIdentifier("backup.restore.scope")
            }

             
             
             
             
            if dataScope == .ordinary {
            Section {
                Toggle(
                    "Sync Profiles to Apple TV",
                    isOn: Binding(
                        get: { autoBackup.isEnabled },
                        set: { wantsOn in
                            if wantsOn {
                                showsAutoBackupConsent = true
                            } else {
                                autoBackup.pressOff()
                            }
                        }
                    )
                )
                .disabled(autoBackup.isExporting)
                .accessibilityIdentifier("backup.icloud.auto")
            } header: {
                Text("Apple TV")
            } footer: {
                autoBackupFooter
            }
            }

            Section {
                if let icloud {
                    Button { backUpToICloud(store: icloud) } label: {
                        Label("Back up now", systemImage: ClashSymbol.icloudAndArrowUp.name)
                    }
                    .clashMacFormActionChrome()
                    .disabled(icloudBusy)
                    .accessibilityIdentifier("backup.icloud.create")

                    Button { refreshICloud(store: icloud) } label: {
                        Label(
                            "Refresh backup list",
                            systemImage: ClashSymbol.arrowClockwiseIcloud.name
                        )
                    }
                    .clashMacFormActionChrome()
                    .disabled(icloudBusy)
                    .accessibilityIdentifier("backup.icloud.refresh")

                    if icloudEntries.isEmpty {
                        Text("No iCloud backups yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(icloudEntries) { entry in
                            iCloudEntryRow(entry, store: icloud)
                        }
                    }
                } else if icloudChecked {
                    Text("iCloud unavailable — sign in to iCloud and enable iCloud Drive for Clash.")
                        .font(ClashPlatformLayout.pageUsesSystemSettingsIdiom ? ClashMacSettingsType.value : .caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            } header: {
                Text("iCloud")
            }

            Section {
                Button {
                    guard let workingDir, !exporting else { return }
                     
                     
                    exporting = true
                    let device = BackupArchive.localDeviceName()
                    Task {
                        defer { exporting = false }
                        do {
                            let archive = try await Task.detached(priority: .userInitiated) {
                                try BackupArchive.collect(workingDir: workingDir, sourceDevice: device)
                            }.value
                            exportDocument = BackupDocument(archive: archive)
                        } catch {
                            status = .failure("Export failed: %@", error, locale: locale)
                        }
                    }
                } label: {
                    Label("Export backup file", systemImage: ClashSymbol.squareAndArrowUp.name)
                }
                .disabled(exporting)
                .clashMacFormActionChrome()
                .accessibilityIdentifier("backup.local.export")

                Button { showsImporter = true } label: {
                    Label("Import backup file", systemImage: ClashSymbol.squareAndArrowDown.name)
                }
                .clashMacFormActionChrome()
                .accessibilityIdentifier("backup.local.import")
            } header: {
                Text("Local")
            } footer: {
                Text("This file carries your credentials so a restore works straight away. Treat it as private.")
            }

            if let status {
                Section("Last Operation") {
                    ClashStatusMessage(text: status.text, kind: status.kind)
                        .accessibilityIdentifier("backup.status")
                    if !status.detail.isEmpty {
                        Text(verbatim: status.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                     
                     
                    ForEach(Array(status.notes.enumerated()), id: \.offset) { _, note in
                        ClashStatusMessage(text: note, kind: .warning)
                    }
                }
            }
        }
        .clashInsetGroupedListStyle()
         
         
         
         
         
        .accessibilityIdentifier("backup.root")
        .clashPageTitle("Backup & Restore")
         
         
         
        .alert(
            "Sync Profiles to Apple TV?",
            isPresented: $showsAutoBackupConsent
        ) {
            Button("Turn On") { Task { await autoBackup.enable() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your profiles will be uploaded to iCloud for Apple TV to use.")
        }
        .fileExporter(
            isPresented: Binding(
                get: { exportDocument != nil },
                set: { if !$0 { exportDocument = nil } }
            ),
            document: exportDocument,
            contentType: .json,
            defaultFilename: "clash-backup"
        ) { result in
            switch result {
            case .success: status = .init(.copy("Backup exported"), .success)
            case .failure(let error): status = .failure("Export failed: %@", error, locale: locale)
            }
            exportDocument = nil
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.json]
        ) { result in
            importLocal(result)
        }
        .clashProductModal(item: $preparedRestore, role: .page) { prepared in
            Group {
                if let workingDir {
                    BackupRestorePreviewSheet(
                        prepared: prepared,
                        workingDir: workingDir,
                        scopeRaw: $restoreScopeRaw,
                        onRestore: { scope in
                            performRestore(prepared, scope: scope)
                        }
                    )
                }
            }
            .clashModalPresentation(.page)
        }
        .task { resolveICloud() }
    }

     
     
    @ViewBuilder
    private var autoBackupFooter: some View {
         
         
         
         
         
        Text("When on, this device uploads its own copy for Apple TV to restore; devices do not sync with each other.")
        autoBackupOutcomeLine
        if !autoBackup.leftOutProfiles.isEmpty {
            Text(clash: .format(
                "Left out, never downloaded: %@",
                [autoBackup.leftOutProfiles.joined(separator: ", ")]
            ))
        }
    }

    @ViewBuilder
    private var autoBackupOutcomeLine: some View {
        switch autoBackup.outcome {
        case .exported(let date)?:
            Text(clash: .format("This device's copy updated %@", [Self.relativeTime(date)]))
        case .unchanged?:
            Text("This device's copy is up to date")
        case .waitingForNetwork?:
            Text("Waiting for the network")
        case .waitingForServer?:
            Text("iCloud asked to wait; trying again shortly")
        case .noAccount?:
            Text("Sign in to iCloud to sync to Apple TV.")
        case .storageFull?:
            Text("iCloud storage is full.")
        case .failed(let sentence)?:
            Text(verbatim: sentence)
        case nil:
            if let date = autoBackup.lastExportedAt {
                Text(clash: .format("This device's copy updated %@", [Self.relativeTime(date)]))
            }
        }
    }

    private static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private func iCloudEntryRow(
        _ entry: ICloudBackupStore.Entry,
        store: ICloudBackupStore
    ) -> some View {
         
         
         
         
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom,
           entry.kind == .conflict {
            HStack(spacing: ClashTheme.Spacing.compact) {
                iCloudEntryRowCore(entry, store: store)
                Button {
                    resolveICloudConflict(entry, store: store)
                } label: {
                    Text(ClashCopy.key("Keep Copy"))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.primary)
                .disabled(icloudBusy)
            }
        } else if entry.kind == .current {
            ClashMacDeletableRow(onDelete: {
                deleteICloud(entry, store: store)
            }) {
                iCloudEntryRowCore(entry, store: store)
            }
        } else {
            iCloudEntryRowCore(entry, store: store)
        }
    }

    @ViewBuilder
    private func iCloudEntryRowCore(
        _ entry: ICloudBackupStore.Entry,
        store: ICloudBackupStore
    ) -> some View {
        Button {
            prepareICloudRestore(entry, store: store)
        } label: {
            HStack(spacing: ClashTheme.Spacing.row) {
                Image(systemName: entrySymbol(entry).name)
                    .foregroundStyle(entryTint(entry))
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.fileName)
                        .font(.body.monospaced())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(entrySubtitle(entry))
                        .font(ClashPlatformLayout.pageUsesSystemSettingsIdiom ? ClashMacSettingsType.value : .caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: ClashTheme.Spacing.compact)
                if let badge = entryBadge(entry) {
                    ClashStatusBadge(title: badge.title, tint: badge.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .tint(.primary)
        .disabled(icloudBusy)
        .accessibilityIdentifier("backup.icloud.restore.\(entry.id)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if entry.kind == .current {
                Button(role: .destructive) {
                    deleteICloud(entry, store: store)
                } label: {
                    Label("Delete", systemImage: ClashSymbol.trash.name)
                }
                 
                 
                 
                 
                 
                 
                .tint(.red)
                .accessibilityIdentifier("backup.icloud.delete.\(entry.id)")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if entry.kind == .conflict {
                Button {
                    resolveICloudConflict(entry, store: store)
                } label: {
                    Label("Keep Copy", systemImage: ClashSymbol.checkmarkCircle.name)
                }
                .tint(.green)
                .accessibilityIdentifier("backup.icloud.resolve.\(entry.id)")
            }
        }
    }

    private func entrySymbol(_ entry: ICloudBackupStore.Entry) -> ClashSymbol {
        switch entry.kind {
        case .conflict: return .exclamationmarkTriangle
        case .history: return .clock
        case .current:
            return entry.downloaded ? .icloudAndArrowDown : .arrowClockwiseIcloud
        }
    }

    private func entryTint(_ entry: ICloudBackupStore.Entry) -> Color {
        switch entry.kind {
        case .conflict: return .orange
        case .history: return .secondary
        case .current: return entry.downloaded ? .accentColor : .secondary
        }
    }

    private func entryBadge(
        _ entry: ICloudBackupStore.Entry
    ) -> (title: String, tint: Color)? {
        switch entry.kind {
        case .conflict: return ("Conflict", .orange)
        case .history: return ("History", .secondary)
        case .current where !entry.downloaded: return ("Download", .blue)
        case .current: return nil
        }
    }

    private func entrySubtitle(_ entry: ICloudBackupStore.Entry) -> String {
        var parts: [String] = []
        if entry.kind != .current { parts.append(entry.kind.title) }
        if let date = entry.modifiedAt {
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        if let bytes = entry.byteCount {
            parts.append(ByteCountFormatter.string(bytes))
        }
        if !entry.downloaded { parts.append("Stored in iCloud") }
        return parts.isEmpty ? "Backup" : parts.joined(separator: " · ")
    }

    private func resolveICloud() {
        Task {
            let store: ICloudBackupStore?
            if BackupSandbox.usesFixtureICloud(
                scope: dataScope,
                uiTestingEnabled: false
            ) {
                 
                 
                 
                 
                store = nil
            } else {
                store = await Task.detached { ICloudBackupStore.defaultContainer() }.value
            }
            let entries = await Task.detached { store?.list() ?? [] }.value
            icloud = store
            icloudEntries = entries
            icloudChecked = true
        }
    }

    private func refreshICloud(store: ICloudBackupStore) {
        icloudBusy = true
        Task {
            icloudEntries = await Task.detached { store.list() }.value
            status = .init(.copy("iCloud backup list refreshed"), .success)
            icloudBusy = false
        }
    }

    private func backUpToICloud(store: ICloudBackupStore) {
        guard let workingDir else { return }
        icloudBusy = true
        status = .init(.copy("Backing up to iCloud…"), .information)
        Task {
            do {
                _ = try await Task.detached {
                    try store.backUp(
                        try BackupArchive.collect(workingDir: workingDir)
                    )
                }.value
                status = .init(.copy("Backed up to iCloud"), .success)
            } catch {
                status = .failure("iCloud failed: %@", error, locale: locale)
            }
            icloudEntries = await Task.detached { store.list() }.value
            icloudBusy = false
        }
    }

    private func deleteICloud(
        _ entry: ICloudBackupStore.Entry,
        store: ICloudBackupStore
    ) {
        icloudBusy = true
        Task {
            do {
                try await Task.detached { try store.delete(entry) }.value
                status = .init(.format("Deleted “%@”", [entry.fileName]), .success)
            } catch {
                status = .failure("iCloud failed: %@", error, locale: locale)
            }
            icloudEntries = await Task.detached { store.list() }.value
            icloudBusy = false
        }
    }

    private func resolveICloudConflict(
        _ entry: ICloudBackupStore.Entry,
        store: ICloudBackupStore
    ) {
        icloudBusy = true
        status = .init(.copy("Resolving iCloud conflict…"), .warning)
        Task {
            do {
                try await Task.detached { try store.resolveConflict(entry) }.value
                status = .init(.copy("Kept selected iCloud conflict copy"), .warning)
            } catch {
                status = .failure("iCloud failed: %@", error, locale: locale)
            }
            icloudEntries = await Task.detached { store.list() }.value
            icloudBusy = false
        }
    }

    private func prepareICloudRestore(
        _ entry: ICloudBackupStore.Entry,
        store: ICloudBackupStore
    ) {
        guard let workingDir else { return }
        icloudBusy = true
        status = .init(.copy(entry.downloaded ? "Reading backup…" : "Requesting iCloud download…"), .information)
        Task {
            defer { icloudBusy = false }
            do {
                let outcome = try await Task.detached {
                    try store.restore(entry)
                }.value
                switch outcome {
                case .restored(let archive):
                    let scope = restoreScope
                    _ = try await Task.detached {
                        try archive.preview(
                            workingDir: workingDir,
                            scope: scope
                        )
                    }.value
                    status = nil
                    preparedRestore = PreparedBackupRestore(
                        archive: archive,
                        sourceTitle: entry.kind == .current
                            ? entry.fileName
                            : "\(entry.fileName) · \(entry.kind.title)"
                    )
                case .downloading(let name):
                    status = .init(.format("%@ is downloading from iCloud — refresh when it is available", [name]), .information)
                    icloudEntries = await Task.detached { store.list() }.value
                case .unavailable(let name):
                    status = .init(.format("%@ is unavailable offline — reconnect and refresh", [name]), .warning)
                    icloudEntries = await Task.detached { store.list() }.value
                case .empty:
                    status = .init(.copy("No iCloud backups yet"), .success)
                }
            } catch {
                status = .failure("Preview failed: %@", error, locale: locale)
            }
        }
    }

    private var restoreScope: BackupRestoreScope {
        BackupRestoreScope(rawValue: restoreScopeRaw) ?? .allData
    }

    private func performRestore(
        _ prepared: PreparedBackupRestore,
        scope: BackupRestoreScope
    ) {
        guard let workingDir else { return }
        preparedRestore = nil
        icloudBusy = true
        status = .init(.copy("Restoring backup…"), .information)
        Task {
            defer { icloudBusy = false }
            do {
                let result = try await Task.detached {
                    try prepared.archive.restore(
                        workingDir: workingDir,
                        scope: scope
                    )
                }.value
                 
                 
                let modules = await prepared.archive.restoringModules(
                    scope: scope, into: ModuleStore.shared(workingDir.deletingLastPathComponent()))
                status = .init(.format("Restored %@ profiles · %@ total",
                                        ["\(result.importedProfiles)", "\(result.totalProfiles)"]), .success,
                               detail: result.registrationFailures.joined(separator: "\n"), notes: modules)
                 
                 
                 
                NotificationCenter.default.post(
                    name: .clashProfileStoreReplaced,
                    object: nil
                )
            } catch {
                status = .failure("Restore failed; local data was rolled back: %@", error, locale: locale)
            }
        }
    }

    private func importLocal(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            status = .failure("Import failed: %@", error, locale: locale)
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let archive = try BackupArchive.decode(Data(contentsOf: url))
                if let workingDir {
                    _ = try archive.preview(
                        workingDir: workingDir,
                        scope: restoreScope
                    )
                }
                preparedRestore = PreparedBackupRestore(
                    archive: archive,
                    sourceTitle: url.lastPathComponent
                )
            } catch {
                status = .failure("Import failed: %@", error, locale: locale)
            }
        }
    }
}

private struct BackupRestorePreviewSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.locale) private var locale

    let prepared: PreparedBackupRestore
    let workingDir: URL
    @Binding var scopeRaw: String
    let onRestore: (BackupRestoreScope) -> Void

    private var scope: BackupRestoreScope {
        BackupRestoreScope(rawValue: scopeRaw) ?? .allData
    }

    private var preview: Result<BackupRestorePreview, Error> {
        Result {
            try prepared.archive.preview(
                workingDir: workingDir,
                scope: scope
            )
        }
    }

    var body: some View {
        ClashFeatureNavigationContainer {
            ClashMacSettingsContainer {
                Section("Source") {
                    Text(prepared.sourceTitle)
                        .font(.body.monospaced())
                        .lineLimit(2)
                        .accessibilityIdentifier("backup.preview.source")
                }

                Section("Restore Options") {
                    Picker("Data", selection: $scopeRaw) {
                        ForEach(BackupRestoreScope.allCases) { item in
                            Text(item.title).tag(item.rawValue)
                        }
                    }
                        .accessibilityIdentifier("backup.restore.scope")
                }

                switch preview {
                case .failure(let error):
                    Section("Preview") {
                        ClashStatusMessage(
                            text: .format("Preview failed: %@", [ClashErrorCopy.message(error, locale: locale)]),
                            kind: .error
                        )
                    }
                case .success(let preview):
                    previewSections(preview)
                }
            }
            .clashInsetGroupedListStyle()
            
            .clashPageTitle("Restore Preview")
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) {
                    ClashSheetCloseButton {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .clashProductModalRoot(title: "Restore Preview")
        }
    }

    @ViewBuilder
    private func previewSections(_ preview: BackupRestorePreview) -> some View {
        Section("Summary") {
            OverviewValueRow(title: "Added", value: .verbatim("\(preview.addedCount)"))
            OverviewValueRow(title: "Updated", value: .verbatim("\(preview.updatedCount)"))
            OverviewValueRow(title: "Unchanged", value: .verbatim("\(preview.unchangedCount)"))
            OverviewValueRow(title: "Removed", value: .verbatim("\(preview.removedCount)"))
            OverviewValueRow(
                title: "Profiles after restore",
                value: .verbatim("\(preview.totalProfilesAfterRestore)"))
            OverviewValueRow(
                title: "Referenced scripts",
                value: .verbatim("\(preview.referencedScriptCount)"))
            if scope == .allData {
                 
                 
                 
                 
                 
                OverviewValueRow(
                    title: "Override",
                    value: .copy(preview.globalConfigChanges ? "Will change" : "Unchanged")
                )
            }
        }
        .accessibilityIdentifier("backup.preview.summary")

        Section("Security") {
            ClashStatusMessage(
                text: .copy("This file carries your credentials so a restore works straight away. Treat it as private."),
                kind: .information
            )
            if preview.omittedRemoteSourceCount > 0 {
                ClashStatusMessage(
                    text: .format("%@ profile URL(s) were excluded. Their cached sources restore as local profiles.", [String(preview.omittedRemoteSourceCount)]),
                    kind: .information
                )
                .accessibilityIdentifier("backup.preview.omitted-remote")
            }
            if preview.rebindRequiredProviderCount > 0 {
                ClashStatusMessage(
                    text: .format(
                        "%@ provider source(s) were excluded. Those groups and rules stay empty until you point them at a source again.",
                        [String(preview.rebindRequiredProviderCount)]
                    ),
                    kind: .warning
                )
                .accessibilityIdentifier("backup.preview.rebind-required")
            }
        }

        if !preview.changes.isEmpty {
            Section("Profile Changes") {
                ForEach(preview.changes) { change in
                    HStack(spacing: ClashTheme.Spacing.row) {
                        Image(systemName: changeSymbol(change.kind).name)
                            .foregroundStyle(changeTint(change.kind))
                            .frame(width: 22)
                            .accessibilityHidden(true)
                         
                        Text(clash: .verbatim(change.label))
                        Spacer(minLength: ClashTheme.Spacing.compact)
                        ClashStatusBadge(
                            title: change.kind.title,
                            tint: changeTint(change.kind)
                        )
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("backup.preview.change.\(change.profileID)")
                }
            }
        }

        Section {
            if preview.removedCount > 0 {
                ClashStatusMessage(
                    text: .format("Restoring will remove %@ local profile(s); if it cannot finish, Clash keeps your current data.", [String(preview.removedCount)]),
                    kind: .warning
                )
            } else {
                Text("Clash replaces your data only after everything is ready; if the restore fails, your current data stays in place.")
                    .font(ClashPlatformLayout.pageUsesSystemSettingsIdiom ? ClashMacSettingsType.value : .caption)
                    .foregroundStyle(.secondary)
            }
            Button(role: preview.removedCount > 0 ? .destructive : nil) {
                onRestore(scope)
            } label: {
                Label(
                    "Restore \(scope.title)",
                    systemImage: ClashSymbol.arrowUturnBackward.name
                )
                .frame(maxWidth: .infinity)
            }
            .clashPrimaryActionButtonStyle()
            .clashCapsuleButtonBorderShape()
            .controlSize(.regular)
            .accessibilityIdentifier("backup.preview.restore")
        }
    }

    private func changeSymbol(_ kind: BackupRestorePreview.Change.Kind) -> ClashSymbol {
        switch kind {
        case .added: return .plus
        case .updated: return .arrowTriangle2Circlepath
        case .unchanged: return .checkmarkCircle
        case .removed: return .trash
        }
    }

    private func changeTint(_ kind: BackupRestorePreview.Change.Kind) -> Color {
        switch kind {
        case .added: return .green
        case .updated: return .blue
        case .unchanged: return .secondary
        case .removed: return .red
        }
    }
}

 
struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var archive: BackupArchive

    init(archive: BackupArchive) { self.archive = archive }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        archive = try BackupArchive.decode(data)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try archive.encoded())
    }
}

 
private struct BackupStatus {
    let text: ClashDisplayText
    let kind: ClashStatusKind
     
    var detail = ""
     
    var notes: [ClashDisplayText] = []

    init(_ text: ClashDisplayText, _ kind: ClashStatusKind, detail: String = "", notes: [ClashDisplayText] = []) {
        self.text = text
        self.kind = kind
        self.detail = detail
        self.notes = notes
    }

     
    static func failure(_ format: String, _ error: Error, locale: Locale) -> BackupStatus {
        BackupStatus(.format(format, [ClashErrorCopy.message(error, locale: locale)]), .error)
    }
}

extension BackupArchive.BackupError: ClashAuthoredError {
     
     
    var displayText: ClashDisplayText {
        switch self {
        case .incompleteProfiles(let labels):
            return .format(
                "%@ could not be backed up completely: a saved credential is missing. Re-enter it, then back up again.",
                [labels.joined(separator: ", ")]
            )
        default:
            return .copy(errorDescription ?? "")
        }
    }
}

extension BackupArchive {
     
     
     
    func restoringModules(scope: BackupRestoreScope, into store: ModuleStore,
                          log: (String) -> Void = { ClashLogStore.shared.append($0, stream: .app) }) async -> [ClashDisplayText] {
        guard scope == .allData else { return [] }
        var names: [String] = []
        if let modulesLeftOut {
            log("modules in the backup not restored: \(modulesLeftOut.reason)")
            names += modulesLeftOut.names
            if modulesLeftOut.names.isEmpty { names.append("") }
        }
        if let modules { names += await store.restore(modules) }
        var notes = names.filter { !$0.isEmpty }.map { name -> ClashDisplayText in
            .format("The module “%@” wasn't restored. You can add it again.", [name])
        }
        if names.contains("") { notes.append(.copy("The modules in this backup weren't restored. You can add them again.")) }
        return notes
    }
}
