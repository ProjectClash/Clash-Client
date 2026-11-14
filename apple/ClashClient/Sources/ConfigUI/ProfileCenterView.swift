import Combine
import ClashClientKit
import ClashClientUI
import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

 
 
 
 
 
struct ProfileCenterAdapter: View {
    @Environment(\.clashFeedback) private var feedback
     
     
    @Environment(\.locale)
    private var locale
    @Environment(\.clashShellLayout) private var shellLayout
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ObservedObject private var importRouter: ProfileImportRouter
     
     
     
     
     
     
     
     
     
     
     
     
    private let model: ProfilesViewModel
    @StateObject private var facts: ProfileCenterFacts
     
     
    @ObservedObject private var modulesEntry = ModulePageModel.shared.entrySource
     
     
    @ObservedObject private var moduleAddRequest = ModulePageModel.shared.addRequest

    private let initialDestination: AppNavigationDestination
    private let onActiveRuntimeChanged: () -> Void

     
     
     
     
     
     
    private var activeFailure: ProfileSwitchAlertFailure? {
        model.lastFailure.map { ProfileSwitchAlertFailure($0) }
    }
    private func sayFailure(_ failure: ConfigurationFailure?) {
         
         
         
        guard let failure else { feedback?.dismiss(operation: "profiles.failure"); return }
        let text = ProfileSwitchAlertFailure(failure)
        let retries = failure.recoveryActions.contains(.retry)
        let model = model
        let presentation = ClashFeedbackPresentation.error(
            title: .verbatim(text.titleText), message: .verbatim(text.messageText),
            action: retries ? .retry : nil, accessibilityIdentifier: "feedback.profiles.failure"
        )
        var retry: (@MainActor () -> Void)?
        if retries { retry = { model.retryLastFailure() } }
         
         
        feedback?.show(presentation, operation: "profiles.failure", perform: retry,
                       onDismiss: { model.dismissFailure() })
    }

     
     
    private var alertFailureShowing: Bool { false }
    @State private var exportDocument: ConfigTextDocument?
    @State private var exportName = ""
    @StateObject private var centerDismiss = ClashDismissHandle()
     
     
    @StateObject private var quickAdd: ProfileQuickAddController
    @State private var adaptationNoticeCounts: [String: Int] = [:]
    @State private var composedProfileIDs: Set<String> = []
    @State private var configurationLibrary = ConfigurationLibrarySnapshot()
     
     
    @State private var providerNodeCounts: [String: Int] = [:]
    @State private var providerDownloads = 0
    @State private var libraryBrowseCache: ConfigurationLibraryBrowseCache?
     
     
    @State private var handoffsTaken = 0
     
    @State private var centreID = UUID()

     
     
    private let ownsNavigationContainer: Bool

    private let palette: ClashClientUI.ClashProductPalette

     
     
    private let listPresentation:
        ((ClashClientUI.ClashProfilesListPresentation) -> AnyView)?
     
    private let capabilityInterceptor:
        ((ClashClientUI.ClashProfilesCapabilityDestination) -> Bool)?
     
     
    private let selections: GroupSelectionCarrying?

    init(
        profiles: ProfilesViewModel,
        importRouter: ProfileImportRouter,
        initialDestination: AppNavigationDestination = .profiles,
        ownsNavigationContainer: Bool = true,
         
         
         
         
        palette: ClashClientUI.ClashProductPalette = .clashProduct,
        onActiveRuntimeChanged: @escaping () -> Void = {},
        capabilityInterceptor: (
            (ClashClientUI.ClashProfilesCapabilityDestination) -> Bool
        )? = nil,
        listPresentation: (
            (ClashClientUI.ClashProfilesListPresentation) -> AnyView
        )? = nil,
        selections: GroupSelectionCarrying? = nil
    ) {
        self.selections = selections
        self.ownsNavigationContainer = ownsNavigationContainer
        self.importRouter = importRouter
        self.initialDestination = initialDestination
        self.palette = palette
        self.onActiveRuntimeChanged = onActiveRuntimeChanged
        self.listPresentation = listPresentation
        self.capabilityInterceptor = capabilityInterceptor
        model = profiles
        _facts = StateObject(wrappedValue: ProfileCenterFacts(model: profiles))
        _quickAdd = StateObject(wrappedValue: ProfileQuickAddController(model: profiles, target: .profile))
    }

    var body: some View {
        let _ = ClashPerf.count("center.body")
        ClashOptionalNavigationContainer(owns: ownsNavigationContainer) {
#if os(iOS)
            ClashConfigurationCenterSections(revealsConfigurations: handoffsTaken) {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                profilesPage
                    .profileQuickAddPresenters(quickAdd)
            } nodes: {
                ConfigurationSourceLibraryAdapter(model: model, library: configurationLibrary,
                    changed: applyNodeLibraryChange, close: { centerDismiss() },
                    embedded: true, showsClose: ownsNavigationContainer, browseCache: $libraryBrowseCache)
            } rules: {
                ConfigurationRuleLibraryAdapter(model: model, library: configurationLibrary,
                    changed: applyCenterLibrary, close: { centerDismiss() },
                    embedded: true, showsClose: ownsNavigationContainer, browseCache: $libraryBrowseCache)
            }
#else
            profilesPage
#endif
        }
        .clashCapturesDismiss(centerDismiss)
         
#if !os(iOS)
        .profileQuickAddPresenters(quickAdd)
#endif
#if os(iOS)
         
         
         
         
         
        .onReceive(model.$lastFailure) { sayFailure($0) }
#endif
         
         
        .modifier(ProfileHandoffRefusalAlert(router: importRouter, host: centreID, waits: alertFailureShowing))
#if os(iOS)
         
         
        .modifier(InstallLinkConfirmationAlert(router: importRouter,
            asksHere: importRouter.centresOnScreen.last == centreID && !alertFailureShowing,
            added: {}, declined: {}))
#endif
         
        .task { await ModulePageModel.shared.reload() }
        .onAppear {
            importRouter.centreAppeared(centreID)
            model.load()
            model.selectSoleProfileIfNeeded()
             
             
             
            importRouter.importSharedFiles()
        }
        .onDisappear { importRouter.centreDisappeared(centreID) }
        .onReceive(
            importRouter.$pendingImport.compactMap { $0 }
        ) { _ in
             
             
             
             
             
             
             
            if let request = importRouter.take() {
                consume(request)
                handoffsTaken &+= 1
            }
        }
        .onReceive(model.$profiles) { _ in
             
             
             
             
             
             
            Task { @MainActor in
                guard let store = model.configurationLibraryStore else { return }
                if let snapshot = try? await Task.detached(operation: { try store.snapshot() }).value {
                    guard snapshot.generation >= configurationLibrary.generation else { return }
                    let composed = Set(snapshot.recipes.filter { $0.preservesOriginal != true }.map(\.id))
                    if composed != composedProfileIDs { composedProfileIDs = composed }
                    if snapshot != configurationLibrary { configurationLibrary = snapshot }
                }
            }
        }
        .task(id: activeRevisionKey) {
            await loadAdaptationNoticeCount()
        }
        .task(id: "\(configurationLibrary.generation)|\(providerDownloads)") {
            guard let store = model.configurationLibraryStore else { return }
            let snapshot = configurationLibrary
            let model = model
            let counts = await Task.detached(priority: .utility) {
                 
                ConfigurationCollectionContentBridge.downloadedNodeCounts(store, snapshot: snapshot,
                                                                         inUse: model.providerCatalogInUse())
            }.value
            if counts != providerNodeCounts { providerNodeCounts = counts }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProviderDownloadActivity.didChangeNotification)) { _ in
            providerDownloads &+= 1
        }
    }

     
     
    private func rereadCentreLibrary() async {
        guard let store = model.configurationLibraryStore,
              let updated = try? await Task.detached(operation: { try store.snapshot() }).value,
              updated.generation >= configurationLibrary.generation else { return }
        applyCenterLibrary(updated)
    }

     
     
     
     
     
     
     
    private func librarySubscriptionFacts(for profile: Profile) -> ProfileSubscriptionSettingsAdapter.LibraryFacts? {
        guard let recipe = configurationLibrary.recipes.first(where: { $0.id == profile.id }),
              recipe.sources.count == 1, let reference = recipe.sources.first,
              let record = configurationLibrary.sources.first(where: { $0.id == reference.id }),
              case .subscription = record.origin else { return nil }
        return .init(intervalHours: record.updateIntervalHours ?? 0, sourceID: record.id,
                     sharedBy: configurationLibrary.recipes.filter { $0.sources.contains { $0.id == record.id } }.count)
    }

    private func applyCenterLibrary(_ snapshot: ConfigurationLibrarySnapshot) {
        configurationLibrary = snapshot
        composedProfileIDs = Set(snapshot.recipes.filter { $0.preservesOriginal != true }.map(\.id))
    }

     
     
     
     
    private func applyLibraryFromAPage(_ snapshot: ConfigurationLibrarySnapshot) {
        guard ConfigurationCollectionListing.takes(snapshot, over: configurationLibrary) else { return }
        applyCenterLibrary(snapshot)
    }

     
     
     
     
    private func applyNodeLibraryChange(_ snapshot: ConfigurationLibrarySnapshot) {
        guard ConfigurationCollectionListing.takes(snapshot, over: configurationLibrary) else { return }
        applyCenterLibrary(snapshot)
    }

    private var usesConfigurationSections: Bool {
#if os(iOS)
        true
#else
        false
#endif
    }

    private var profilesPage: some View {
            ClashClientUI.ClashProfilesView(
                snapshot: sharedSnapshot,
                actions: sharedActions,
                initialProfileID: initialProfileID,
                opensImportInitially: opensImportInitially,
                opensModules: opensModules,
                presentationClass:
                    shellLayout == .regularSidebar
                        ? .regularTouch
                        : .compactTouch,
                showsDismissControl: ownsNavigationContainer,
                isCenterSection: usesConfigurationSections,
                palette: productPalette,
                pagePresentation: { content in
                    AnyView(
            content
                    )
                },
                 
                 
                 
                 
                detailPresentation: { content in
                    AnyView(
                        content.fileExporter(
                            isPresented: Binding(
                                get: { exportDocument != nil },
                                set: { presented in
                                    if !presented {
                                        exportDocument = nil
                                    }
                                }
                            ),
                            document: exportDocument,
                            contentType: .yaml,
                            defaultFilename: exportName
                        ) { outcome in
                            exportDocument = nil
                             
                            switch outcome {
                            case .success(let url):
                                feedback?.show(.success(title: ClashFeedbackCopy.exported(url.lastPathComponent),
                                                        accessibilityIdentifier: "feedback.profile.export"),
                                               operation: "profile.export")
                            case .failure(let error):
                                if (error as? CocoaError)?.code == .userCancelled { return }
                                feedback?.show(.error(title: ClashFeedbackCopy.couldNotSave,
                                                      message: .copy(error.localizedDescription),
                                                      accessibilityIdentifier: "feedback.profile.export"),
                                               operation: "profile.export")
                            }
                        }
                    )
                },
                listPresentation: listPresentation,
                 
                 
                quickAdd: usesConfigurationSections
                    ? { AnyView(ProfileQuickAddCard(
                        controller: quickAdd,
                        identifiers: .init(linkIdentifier: "profile-center.quick-add.link",
                                           scanIdentifier: "profile-center.quick-add.scan",
                                           fileIdentifier: "profile-center.quick-add.file",
                                           manualIdentifier: "profile-center.quick-add.manual",
                                           statusIdentifier: "profile-center.quick-add.status"),
                        onFirstProfileCreated: ownsNavigationContainer ? { centerDismiss() } : nil)
                         
                        .disabled(model.isUpdatingNodeLibrary)) }
                    : nil,
                quickAddLeads: !ProfileCenterPolicy.hasUserProfile(model.profiles),
                configurationPage: configurationPage,
                capabilityInterceptor: capabilityInterceptor,
                icon: { symbol in
                    ClashSymbolImage(symbol: symbol)
                },
                capabilityContent: { destination in
                    capabilityView(destination)
                }
            )
    }

     
     
     
     
    private var configurationPage: ((ClashClientKit.Profile.ID) -> ClashClientUI.ClashConfigurationPageParts)? {
#if os(iOS)
        { id in
             
             
             
             
            let canUseOriginal = configurationLibrary.recipes
                .first(where: { $0.id == id.rawValue })
                .map { $0.sources.count == 1 } ?? true
             
             
             
            let setUsesOriginal: (Bool) async throws -> Void = { enabled in
                try await model.setUsesOriginalConfiguration(id.rawValue, enabled: enabled)
            }
            return ClashClientUI.ClashConfigurationPageParts(
                sections: AnyView(ConfigurationPageSections(canUseOriginal: canUseOriginal, setUsesOriginal: setUsesOriginal,
                                                            libraryChanged: applyLibraryFromAPage)),
                actions: AnyView(ConfigurationPageActions()),
                host: { content in
                    AnyView(ConfigurationPageHost(model: model, profileID: id.rawValue, libraryChanged: applyLibraryFromAPage,
                                                  selections: selections, content: content))
                })
        }
#else
        nil
#endif
    }

    private var initialProfileID: ClashClientKit.Profile.ID? {
        guard case .profileDetail(let rawID) = initialDestination else {
            return nil
        }
        return try? ClashClientKit.Profile.ID(rawID)
    }

    private var opensImportInitially: Bool {
        initialDestination == .profileImport
    }

     
     
     
     
    private var opensModules: Bool {
#if os(iOS)
        ownsNavigationContainer && moduleAddRequest.link != nil && !moduleAddRequest.isPageOnScreen
#else
        false
#endif
    }

    private var productPalette: ClashClientUI.ClashProductPalette {
        palette
    }

    private var catalogProfiles: [Profile] {
        ProfileCenterPolicy.catalog(model.profiles)
    }

    private var sharedSnapshot: AppleClientSnapshot {
         
         
         
        ClashPerf.measure("profiles.snapshot") { buildSharedSnapshot() }
    }

     
     
    private static func modulesEntry(_ entry: ClashModulesEntrySnapshot?) -> ClashModulesEntrySnapshot? {
#if os(macOS)
        nil
#else
        entry
#endif
    }

    private func buildSharedSnapshot() -> AppleClientSnapshot {
        let scripts = catalogProfiles.contains { $0.overwriteMode == .script } ? ScriptLibrary.load() : []
        return AppleClientSnapshot(
            revision: 0,
            connection: AppleClientConnectionSnapshot(
                phase: .unavailable
            ),
            profiles: ClashProfilesSnapshot(
                 
                 
                 
                profiles: catalogProfiles.compactMap { profileSnapshot($0, scripts: scripts) },
                 
                 
                 
                 
                 
                 
                 
                 
                 
                failure: nil,
                statusMessage: model.statusMessage,
                batchReport: model.batchReport.map(batchSnapshot),
                libraryHasFetchableSource: model.libraryHasFetchableSource,
                modules: Self.modulesEntry(modulesEntry.entry)
            ),
            capabilities: AppleClientCapabilities([
                .profiles: .available,
            ])
        )
    }

    private var sharedActions: AppleClientActions {
        AppleClientActions(
            resultCapability: .profiles
        ) { action in
            guard case .profiles(let command) = action else {
                return .none
            }
            return try await handle(command)
        }
    }

     
     
     
     
     
     
    struct LibraryProfileFacts: Equatable {
        var lastUpdatedAt: Date?
        var usage: ConfigurationSubscriptionUsage?
    }

    static func libraryFacts(for profile: Profile, in library: ConfigurationLibrarySnapshot) -> LibraryProfileFacts? {
        guard let recipe = library.recipes.first(where: { $0.id == profile.id }) else { return nil }
        let links = recipe.sources.compactMap { reference in
            library.sources.first { record in
                guard record.id == reference.id, case .subscription = record.origin else { return false }
                return true
            }
        }
        return LibraryProfileFacts(lastUpdatedAt: links.map(\.updatedAt).max(),
                                   usage: recipe.sources.count == 1 && links.count == 1 ? links[0].subscriptionUsage : nil)
    }

    static func subscriptionSnapshot(upload: Int64, download: Int64, total: Int64, expire: Int64) -> ClashProfileSubscriptionSnapshot {
        ClashProfileSubscriptionSnapshot(
            uploadBytes: upload, downloadBytes: download, totalBytes: total,
            expiration: expire > 0 ? Date(timeIntervalSince1970: TimeInterval(expire)) : nil)
    }

    private func profileSnapshot(
        _ profile: Profile, scripts: [ConfigScript]
    ) -> ClashProfileSnapshot? {
        guard let id = try? ClashClientKit.Profile.ID(profile.id) else {
            return nil
        }
        let isCurrent = profile.id == model.activeProfileID
        let libraryFacts = Self.libraryFacts(for: profile, in: configurationLibrary)
         
         
         
         
         
         
         
         
         
        let lastUpdatedAt = libraryFacts != nil
            ? libraryFacts?.lastUpdatedAt
            : profile.lastUpdatedAt
         
         
         
        let followingLinks = configurationLibrary.updateFollowing(ofRecipe: profile.id)
        let linksToRejoin = configurationLibrary.linksToRejoin(ofRecipe: profile.id)
        let shownFollowing = followingLinks == .copyWithoutOrigin && linksToRejoin.isEmpty ? nil : followingLinks
        let canDelete = ProfileCenterPolicy.canDelete(
            profileID: profile.id,
            activeProfileID: model.activeProfileID,
            profiles: model.profiles
        )

        return ClashProfileSnapshot(
            id: id,
            label: ProfileRowPresentation.label(for: profile, locale: .current),
            source: sourceKind(profile.source),
            sourceSummary: sourceSummary(profile, updatedAt: lastUpdatedAt),
            subscription: libraryFacts != nil
                ? libraryFacts?.usage.map { Self.subscriptionSnapshot(upload: $0.upload, download: $0.download, total: $0.total, expire: $0.expire) }
                : profile.subscriptionInfo.map { Self.subscriptionSnapshot(upload: $0.upload, download: $0.download, total: $0.total, expire: $0.expire) },
            lastUpdatedAt: lastUpdatedAt,
            autoUpdate: profile.autoUpdate,
            updateIntervalHours: profile.updateIntervalHours,
            isCurrent: isCurrent,
            isBusy: profile.id == model.busyProfileID,
            canEditSource: profile.id != LocalDefaultProfileProvisioner.profileID && facts.snapshot.editableSourceIDs.contains(profile.id),
            canDelete: canDelete,
            deleteSubtitle: deleteSubtitle(
                profile,
                canDelete: canDelete
            ),
            runtimeSummary: runtimeSummary(profile),
            requiresPlaintextExportConfirmation:
                profile.externalResources?.isEmpty == false,
            featureAvailability: featureAvailability(profile),
            heldBackUpdates: (profile.suppressedUpdates ?? []).map {
                ClashProfileHeldBackUpdate(
                    keyPath: $0.keyPath,
                    change: ClashProfileHeldBackUpdate.Change(rawValue: $0.change.rawValue) ?? .changed,
                    newValue: $0.newValue,
                    appValue: $0.appValue
                )
            },
            isComposed: composedProfileIDs.contains(profile.id),
             
             
             
             
             
            canUseOriginalConfiguration: configurationLibrary.recipes
                .first(where: { $0.id == profile.id })
                .map { $0.sources.count == 1 }
                ?? (profile.id != LocalDefaultProfileProvisioner.profileID),
            configurationSourceNames: configurationLibrary.recipes.first(where: { $0.id == profile.id }).map { recipe in
                recipe.sources.map { pin in
                    configurationLibrary.sources.first(where: { $0.id == pin.id }).map { $0.displayLabel(locale: locale) } ?? pin.id
                }
            },
            configurationRuleName: configurationLibrary.recipes.first(where: { $0.id == profile.id }).flatMap { recipe in
                (configurationLibrary.rules + ConfigurationBuiltins.schemes).first(where: { $0.id == recipe.ruleSchemeID })?.displayLabel
            },
             
             
            followsConfigurationSourceUpdates: shownFollowing.flatMap { _ in
                configurationLibrary.recipes.first(where: { $0.id == profile.id })?.followsUpdates
            },
            configurationUpdateFollowing: shownFollowing,
            configurationLinksToRejoin: linksToRejoin.map { ClashProfileLinkChoice(id: $0.id, label: $0.label) },
            overrideScriptName: profile.overwriteMode == .script
                ? scripts.first { $0.id == profile.selectedScriptID }?.label : nil,
            customRulesCount: profile.override.appendRules.count,
            badges: ProfileRowPresentation.badges(for: profile, in: configurationLibrary),
            note: ProfileRowPresentation.note(for: profile, in: configurationLibrary, providerNodes: providerNodeCounts),
            canOpenConfigurationPage: Self.drawsConfigurationPage(profile)
        )
    }

     
     
     
     
     
     
     
     
    static func drawsConfigurationPage(_ profile: Profile) -> Bool {
#if os(iOS)
        profile.id != LocalDefaultProfileProvisioner.profileID
#else
        false
#endif
    }

     
     
     
     
     
     
     
    private func featureAvailability(
        _ profile: Profile
    ) -> ClashProfileFeatureAvailabilitySnapshot {
        let isRemote: Bool
        if case .url = profile.source {
            isRemote = true
        } else {
            isRemote = false
        }
        return ClashProfileFeatureAvailabilitySnapshot(
            canSync: isRemote,
            canConfigureSubscription: isRemote,
            canCopySubscriptionLink: isRemote,
            canExport: facts.snapshot.editableSourceIDs.contains(profile.id),
            canOpenRuntimePreview: true
        )
    }

    private func sourceKind(
        _ source: Profile.Source
    ) -> ClashProfileSourceKind {
        switch source {
        case .url:
            .remote
        case .file:
            .file
        case .clipboard:
            .clipboard
        }
    }

     
     
     
    private func sourceSummary(
        _ profile: Profile,
        updatedAt: Date?
    ) -> ClashDisplayText {
        Self.sourceSummary(profile, updatedAt: updatedAt, locale: locale)
    }

     
     
     
     
    static func sourceSummary(
        _ profile: Profile,
        updatedAt: Date?,
        locale: Locale
    ) -> ClashDisplayText {
        switch profile.source {
        case .url(let rawURL):
            let host = SubscriptionURLPresentation.hostDescription(
                rawURL,
                locale: locale
            )
            if let updated = updatedAt {
                return .verbatim(
                    "\(host) · \(updated.formatted(.relative(presentation: .named)))"
                )
            }
            return .verbatim(host)
        case .file:
            return "Local · Imported file"
        case .clipboard:
            return "Local · Manually managed"
        }
    }

    private func deleteSubtitle(
        _ profile: Profile,
        canDelete: Bool
    ) -> ClashDisplayText {
        if profile.id == LocalDefaultProfileProvisioner.profileID {
            return "Clash keeps Direct as a safe system fallback"
        }
         
         
         
         
        if canDelete, profile.id == model.activeProfileID {
            return "Clash returns to its built-in profile"
        }
        return canDelete
            ? "Remove this profile from Clash"
            : "Switch to another profile before deleting"
    }

    private func runtimeSummary(_ profile: Profile) -> ClashDisplayText {
        if profile.id == model.activeProfileID,
           let count = adaptationNoticeCounts[profile.id],
           let summary = ProfileAdaptationPresenter.summary(
               noticesCount: count,
               locale: locale
           ) {
             
             
             
            return .verbatim(
                summary + " · " + ClashCopy.string("read-only", locale: locale)
            )
        }
        return "read-only"
    }

    private func batchSnapshot(
        _ report: BatchUpdateReport
    ) -> ClashProfileBatchReportSnapshot {
        Self.batchSnapshot(report, isRunning: model.isBatchSyncing, locale: locale)
    }

     
     
     
     
    static func batchSnapshot(
        _ report: BatchUpdateReport, isRunning: Bool, locale: Locale
    ) -> ClashProfileBatchReportSnapshot {
        ClashProfileBatchReportSnapshot(
            id: report.id,
            title: report.title,
            expectedCount: report.expectedCount,
            items: report.items.compactMap { item in
                guard let id = try? ClashClientKit.Profile.ID(
                    item.id
                ) else {
                    return nil
                }
                return ClashProfileBatchItemSnapshot(
                    id: id,
                    label: item.label,
                    state: batchState(item.state),
                    message:
                        item.failure.map { $0.displayMessage.resolved(locale: locale) }
                        ?? item.message
                        ?? item.state.title,
                    diagnosticCode:
                        item.failure?.diagnosticCode
                )
            },
            wasCancelled: report.wasCancelled,
            isRunning: isRunning
        )
    }

    private static func batchState(
        _ state: BatchUpdateState
    ) -> ClashProfileBatchUpdateState {
        switch state {
        case .updated:
            .updated
        case .unchanged:
            .unchanged
        case .failed:
            .failed
         
         
        case .pending:
            .unchanged
        }
    }

    private func legacyImportView(onSaved: @escaping () -> Void) -> some View {
        AddProfileView(createEmpty: { Task { _ = try? await handle(.createEmpty); onSaved() } }) { label, source, rawYAML, resources in
             
             
             
             
            Task { @MainActor in
                var check: ProfilesViewModel.SourceCheck = .inline
                if case .file = source {
                    check = .accepted
                } else if let rawYAML {
                    let refusal: String? = await Task.detached(priority: .userInitiated) {
                        do { try ConfigTransforms.validateSource(rawYAML); return nil }
                        catch { return error.localizedDescription }
                    }.value
                    check = refusal.map(ProfilesViewModel.SourceCheck.refused) ?? .accepted
                }
                model.add(label:label,source:source,rawYAML:rawYAML,resourceFiles:resources,sourceCheck:check)
                model.selectSoleProfileIfNeeded()
                onSaved()
            }
        }
    }

     
     
     
    private func networkPage(_ profile: Profile, landsOnSniffer: Bool = false) -> some View {
        ProfileBaseDocumentHost(profiles: model, profile: profile) { base in
             
             
            ProfileNetworkSettingsView.opening(profile: profile, sourceYAML: base, landsOnSniffer: landsOnSniffer) { draft in
                try model.updateNetwork(draft)
            }
        }
    }

    @ViewBuilder
    private func capabilityView(
        _ destination: ClashProfilesCapabilityDestination
    ) -> some View {
        switch destination {
        case .importProfile:
#if os(iOS)
            ConfigurationCreationAdapter(model: model)
#else
            legacyImportView(onSaved:{})
#endif
        case .backupRestore:
            BackupRestoreView()
        case .modules:
            ModulePageHost(model: ModulePageModel.shared, noticePlaces: ClashModulesNoticePlaces(
                 
                 
                 
                offers: { place in
                    ModulePageHost.offers(place, activeProfileID: model.activeProfileID,
                                          exists: { noticeProfile($0) != nil })
                },
                page: { place in
                     
                     
                    guard ModulePageHost.offers(place, activeProfileID: model.activeProfileID,
                                                exists: { noticeProfile($0) != nil }) else {
                        return AnyView(ClashOpeningCancelButton())
                    }
                    switch place {
                    case .snifferSettings(let id):
                        guard let profile = noticeProfile(id) else { return AnyView(ClashOpeningCancelButton()) }
                        return AnyView(networkPage(profile, landsOnSniffer: true))
                    }
                }))
        case .subscriptionSettings(let id):
            if let profile = appProfile(id) {
                ProfileSubscriptionSettingsAdapter(
                    profile: profile,
                    model: model,
                    library: librarySubscriptionFacts(for: profile)
                )
            } else {
                ClashOpeningCancelButton()
            }
        case .rules(let id):
            if let profile = appProfile(id) {
                 
                 
                 
                 
                 
                 
                ProfileProjectionLoader(profile: profile, model: model) { projected in
                    ProfileRulesAdapter(
                        profile: profile,
                        sourceYAML: projected
                    ) { draft in
                        try model.updateRules(draft)
                    }
                }
            } else {
                ClashOpeningCancelButton()
            }
        case .override(let id):
            if let profile = appProfile(id) {
                 
                 
                 
                ProfileOverrideView(profile: profile, rawYAML: model.cachedUIProjectedYAML(for: profile),
                    configurationCenter: true, loadRawYAML: { await model.loadUIProjectedYAML(for: profile) }) {
                    try model.updateOverrideSettings(from: $0)
                }
            } else {
                ClashOpeningCancelButton()
            }
        case .network(let id):
            if let profile = appProfile(id) {
                networkPage(profile)
            } else {
                ClashOpeningCancelButton()
            }
        case .trust(let id):
            if let profile = appProfile(id) {
                ProfileTrustPage(profile: profile, sourceYAML: model.sourceYAML(for: profile),
                    patchJSON: profile.override.patchJSON) { patchJSON in
                    var draft = ProfileAdvancedOverridesDraft(profile: profile)
                    draft.rawPatchJSON = patchJSON
                    try await model.updateAdvancedOverrides(draft)
                }
            } else {
                ClashOpeningCancelButton()
            }
        case .configurationSources(let id):
#if os(iOS)
             
            ConfigurationNodeSourcesSheet(model: model, profileID: id.rawValue, libraryChanged: applyCenterLibrary)
#else
            ConfigurationCreationAdapter(model: model, changed: applyCenterLibrary,
                editingProfileID: id.rawValue, editingStep: .sources)
#endif
        case .configurationRules(let id):
            ConfigurationCreationAdapter(model: model, changed: applyCenterLibrary,
                editingProfileID: id.rawValue, editingStep: .rules)
        case .sourceEditor(let id):
            if let profile = appProfile(id) {
                 
                 
                 
                 
                 
                 
                 
                ProfileSourceEditorLoader(profile: profile, model: model,
                    savesIndependentSource: composedProfileIDs.contains(profile.id))
            } else {
                ClashOpeningCancelButton()
            }
        case .runtimePreview(let id):
            if let profile = appProfile(id) {
                ProfilePreviewView(title: .verbatim(profile.label), load: {
                     
                     
                     
                     
                    try await model.loadSavedConfigurationPreview(for: profile.id)
                })
            } else {
                ClashOpeningCancelButton()
            }
        }
    }

    private func appProfile(
        _ id: ClashClientKit.Profile.ID
    ) -> Profile? {
        model.profiles.first { $0.id == id.rawValue }
    }

     
     
    private func noticeProfile(_ id: String) -> Profile? {
        (try? ClashClientKit.Profile.ID(id)).flatMap(appProfile)
    }

    private func handle(
        _ command: ClashProfilesCommand
    ) async throws -> AppleClientActionResult {
        switch command {
        case .createEmpty:
            guard let profile = model.addDirectProfile(),
                  let id = try? ClashClientKit.Profile.ID(
                      profile.id
                  ) else {
                return .none
            }
            model.selectSoleProfileIfNeeded()
            return .profileCreated(id: id)

        case .openImport, .openBackup, .openSourceEditor,
             .openRuntimePreview, .restoreLastKnownGood:
            return .none

        case .syncAll:
            await model.syncAllAndWait()
             
             
             
             
            await rereadCentreLibrary()
            return .none

        case .select(let id):
            guard let profile = appProfile(id) else {
                return .none
            }
             
             
             
             
             
            let succeeded = await model.selectAndWait(profile)
            guard !Task.isCancelled else {
                throw CancellationError()
            }
            if succeeded {
                onActiveRuntimeChanged()
#if canImport(UIKit)
                UINotificationFeedbackGenerator()
                    .notificationOccurred(.success)
#endif
                return .profileSelected(id: id)
            }
            if model.lastFailure != nil {
                 
                 
                 
                return .profileSelectionFailurePresented
            }
            return .none

        case .reorder(let ids):
            applyOrder(ids)
            return .none

        case .sync(let id):
            if let profile = appProfile(id) {
                 
                 
                 
                 
                 
                 
                 
                let outcome = await model.syncAwaitingLibrary(profile)
                await rereadCentreLibrary()
                 
                 
                switch outcome {
                case .changed?:
                    feedback?.show(.success(title: ClashFeedbackCopy.updated(profile.label),
                                            accessibilityIdentifier: "feedback.profile.update"),
                                   operation: "profile.update.\(profile.id)")
                case .unchanged?:
                    feedback?.show(.information(title: ClashFeedbackCopy.upToDate(profile.label),
                                                accessibilityIdentifier: "feedback.profile.update"),
                                   operation: "profile.update.\(profile.id)")
                case .failed?, nil:
                    break
                }
            }
            return .none
        case let .adoptHeldBackUpdate(id, keyPath):
            if let profile = appProfile(id) {
                try model.adoptHeldBackUpdate(profile, keyPath: keyPath)
                onActiveRuntimeChanged()
            }
            return .none
        case .dismissHeldBackUpdates(let id):
            if let profile = appProfile(id) {
                try model.dismissHeldBackUpdates(profile)
            }
            return .none

        case let .setConfigurationSourceUpdates(id, enabled):
            try await model.setConfigurationSourceUpdates(id.rawValue, enabled: enabled)
            await rereadCentreLibrary()
            return .none
        case let .followConfigurationLink(id, linkID):
            try await model.setConfigurationSourceUpdates(id.rawValue, enabled: true, link: linkID)
            await rereadCentreLibrary()
            return .none

        case let .setUsesOriginalConfiguration(id, enabled):
            try await model.setUsesOriginalConfiguration(id.rawValue, enabled: enabled)
            await rereadCentreLibrary()
            return .none

        case let .rename(id, label):
            guard let profile = appProfile(id) else {
                return .none
            }
            try model.updateMetadata(
                profile,
                label: label,
                subscriptionURL: subscriptionURL(profile),
                autoUpdate: profile.autoUpdate,
                updateIntervalHours: profile.updateIntervalHours
            )
            return .none

        case let .saveSubscription(
            id,
            url,
            autoUpdate,
            intervalHours
        ):
            guard let profile = appProfile(id) else {
                return .none
            }
            try model.updateMetadata(
                profile,
                label: profile.label,
                subscriptionURL: url,
                autoUpdate: autoUpdate,
                updateIntervalHours: intervalHours
            )
            return .none

        case .copySubscriptionLink(let id):
            if let profile = appProfile(id) {
                if let link = model.subscriptionLink(for: profile) {
                    ClashClipboard.copy(link, feedback: feedback, noun: "Profile URL", operation: "profile.copy-link")
                }
            }
            return .none

        case .duplicate(let id):
             
             
             
             
            guard let profile = appProfile(id) else { return .none }
            guard let copy = await model.duplicate(profile),
                  let copyID = try? ClashClientKit.Profile.ID(copy.id)
            else {
                 
                 
                 
                return .profileActionRefused(reason: model.statusMessage)
            }
             
             
             
             
             
            feedback?.show(.success(title: .copy("Configuration Duplicated"),
                                    message: ClashProfilesDuplicateNaming.message(label: copy.label),
                                    accessibilityIdentifier: "feedback.profile.duplicate"),
                           operation: "profile.duplicate")
            return .profileCreated(id: copyID)

        case .export(let id):
            guard let profile = appProfile(id) else {
                return .none
            }
            guard let (name, text) =
                await model.loadCachedExportDocument(
                    for: profile.id
                ) else {
#if os(macOS)
                presentMacExportUnavailableAlert()
#else
                 
                 
                feedback?.show(.error(title: .copy("No Local Copy"),
                                      message: .copy("Sync or import this profile to keep a copy on this device."),
                                      accessibilityIdentifier: "feedback.profile.export"),
                               operation: "profile.export")
#endif
                return .none
            }
#if os(macOS)
            presentMacExportPanel(
                defaultFilename: name,
                text: text
            )
#else
            exportName = name
            exportDocument = ConfigTextDocument(text: text)
#endif
            return .none

        case .delete(let id):
            guard let profile = appProfile(id) else {
                return .none
            }
            await model.delete(profile)
            return model.profiles.contains {
                $0.id == id.rawValue
            }
                ? .profileActionRefused(reason: model.statusMessage)
                : .profileDeleted(id: id)

        case .retryFailure:
            model.retryLastFailure()
            return .none

        case .cancelBatch:
            model.cancelBatchSync()
            return .none

        case .retryBatchItem(let id):
            model.retryBatchItem(id: id.rawValue)
            return .none

        case .dismissBatch:
            model.dismissBatchReport()
            return .none
        }
    }

#if os(macOS)
     
     
     
    private func presentMacExportUnavailableAlert() {
        let alert = NSAlert()
        alert.messageText = ClashCopy.string(
            "No Local Copy",
            locale: locale
        )
        alert.informativeText = ClashCopy.string(
            "Sync or import this profile to keep a copy on this device.",
            locale: locale
        )
        alert.addButton(
            withTitle: ClashCopy.string("Done", locale: locale)
        )
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

     
     
     
     
    private func presentMacExportPanel(
        defaultFilename: String,
        text: String
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.yaml]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultFilename

        let completion: (NSApplication.ModalResponse) -> Void = {
            response in
            guard response == .OK, let destination = panel.url else {
                return
            }
             
             
            do {
                try text.write(to: destination, atomically: true, encoding: .utf8)
                feedback?.show(.success(title: ClashFeedbackCopy.exported(destination.lastPathComponent),
                                        action: .reveal,
                                        accessibilityIdentifier: "feedback.profile.export"),
                               operation: "profile.export",
                               perform: { NSWorkspace.shared.activateFileViewerSelecting([destination]) })
            } catch {
                feedback?.show(.error(title: ClashFeedbackCopy.couldNotSave,
                                      message: .copy(error.localizedDescription),
                                      accessibilityIdentifier: "feedback.profile.export"),
                               operation: "profile.export")
            }
        }

        if let window = NSApp.keyWindow {
            panel.beginSheetModal(
                for: window,
                completionHandler: completion
            )
        } else {
            panel.begin(completionHandler: completion)
        }
    }
#endif

    private func applyOrder(
        _ desiredIDs: [ClashClientKit.Profile.ID]
    ) {
        let visible = desiredIDs.map(\.rawValue)
        guard visible.count == catalogProfiles.count,
              Set(visible) == Set(catalogProfiles.map(\.id)) else { return }
         
        let desired = visible + model.profiles.filter { !visible.contains($0.id) }.map(\.id)

        for targetIndex in desired.indices {
            guard let currentIndex = model.profiles.firstIndex(
                where: { $0.id == desired[targetIndex] }
            ), currentIndex != targetIndex else {
                continue
            }
            if let failure = model.move(
                from: IndexSet(integer: currentIndex),
                to:
                    currentIndex < targetIndex
                        ? targetIndex + 1
                        : targetIndex
            ) {
                 
                feedback?.show(.error(title: ClashFeedbackCopy.couldNotSave,
                                      message: .copy(failure.localizedDescription),
                                      accessibilityIdentifier: "feedback.profiles.reorder"),
                               operation: "profiles.reorder")
                return
            }
        }
    }

    private func subscriptionURL(_ profile: Profile) -> String? {
        if case .url(let url) = profile.source {
            return url
        }
        return nil
    }

    private func consume(_ request: ProfileImportRequest) {
        model.consume(request)
    }

    private var activeRevisionKey: String {
        guard let activeID = model.activeProfileID,
              let revision = model.profiles.first(
                  where: { $0.id == activeID }
              )?.activeRevision else {
            return ""
        }
        return "\(activeID)|\(revision)"
    }

    private func loadAdaptationNoticeCount() async {
        guard let activeID = model.activeProfileID,
              model.profiles.first(
                  where: { $0.id == activeID }
              )?.activeRevision != nil,
              let container = ClashAppIdentifiers.appGroupContainer else {
            if !adaptationNoticeCounts.isEmpty { adaptationNoticeCounts = [:] }
            return
        }

        let count = await Task.detached(
            priority: .utility
        ) { () -> Int in
            guard let store = try? ConfigResourceStore(
                containerURL: container
            ),
                let activeYAML = try? store.loadCurrent().text
            else {
                return 0
            }
            return (
                try? ConfigTransforms.planResources(
                    mergedYAML: activeYAML
                ).notices.count
            ) ?? 0
        }.value
        if adaptationNoticeCounts != [activeID: count] { adaptationNoticeCounts = [activeID: count] }
    }
}

 
 
typealias ProfileCenterView = ProfileCenterAdapter

 
enum ProfileAdaptationPresenter {
    static func summary(noticesCount: Int, locale: Locale) -> String? {
        guard noticesCount > 0 else {
            return nil
        }
        return ClashCopy.format(
            "%d items adapted automatically",
            locale: locale,
            noticesCount
        )
    }
}

 
 
 
 
 
 
 
 
struct InstallLinkConfirmationAlert: ViewModifier {
    @ObservedObject var router: ProfileImportRouter
     
    let asksHere: Bool
    let added: () -> Void
    let declined: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.alert(
             
             
            router.pendingConfirmation.map(
                ProfileImportRouter.confirmationIsLocalConfiguration
            ) == true
                ? Text("Add this profile?")
                : Text("Add this profile URL?"),
            isPresented: Binding(
                 
                 
                 
                 
                 
                 
                get: { router.pendingConfirmation != nil && asksHere && scenePhase == .active },
                 
                 
                 
                 
                 
                 
                 
                 
                set: { presented in
                     
                    if !presented, router.pendingConfirmation != nil {
                        ClashLogStore.shared.append(
                            "install link alert torn down (state kept)  \(router.pendingConfirmation ?? "")",
                            stream: .app, level: .warning)
                    }
                }
            )
        ) {
            Button("Add") {
                router.acceptPendingConfirmation()
                added()
            }
            Button("Don't Add", role: .cancel) {
                router.declinePendingConfirmation()
                declined()
            }
        } message: {
             
             
             
             
            let lead = router.pendingConfirmation.map(
                ProfileImportRouter.confirmationIsLocalConfiguration
            ) == true
                ? Text("An install link wants to add a profile to Clash.\n\n")
                : Text("An install link wants to add a profile URL to Clash.\n\n")
            let link = Text(verbatim: router.pendingConfirmation.map {
                ProfileImportRouter.confirmationText(for: $0)
            } ?? "")
             
             
            if let line = ProfileImportRouter.confirmationRuleLine(for: router.pendingRules) {
                lead + Text(clash: line) + Text(verbatim: "\n\n") + link
            } else {
                lead + link
            }
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ProfileHandoffRefusalAlert: ViewModifier {
    @ObservedObject var router: ProfileImportRouter
     
     
    let host: UUID?
     
    let waits: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale

    private var sceneAllows: Bool {
#if os(iOS)
        scenePhase == .active
#else
        true
#endif
    }

     
     
    static func tells(host: UUID?, centresOnScreen: [UUID]) -> Bool {
        guard let host else { return centresOnScreen.isEmpty }
        return centresOnScreen.last == host
    }

    func body(content: Content) -> some View {
        content.alert(
            "Import Failed",
            isPresented: Binding(
                 
                 
                 
                 
                 
                 
                 
                get: {
                    !router.untoldRefusals.isEmpty && !router.aQuestionIsAskedOrDue
                        && Self.tells(host: host, centresOnScreen: router.centresOnScreen)
                        && !waits && sceneAllows
                },
                set: { _ in }
            )
        ) {
            Button("OK", role: .cancel) { router.dismissRefusals() }
                .accessibilityIdentifier("profile-center.import-refusal.ok")
        } message: {
            Text(verbatim: router.untoldRefusals
                .map { ClashCopy.string(for: $0, locale: locale) }
                .joined(separator: "\n"))
        }
    }
}

 
 
 
private struct ProfileSubscriptionSettingsAdapter: View {
     
     
     
     
    struct LibraryFacts: Equatable {
         
        var intervalHours: Int
         
         
        var sourceID: String = ""
         
        var sharedBy: Int = 1
    }

    let profile: Profile
    @ObservedObject var model: ProfilesViewModel
     
     
     
     
     
    let library: LibraryFacts?

     
     
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
    @State private var subscriptionURL: String
    @State private var autoUpdate: Bool
    @State private var updateIntervalHours: Int
     
    @State private var libraryIntervalHours: Int
    @State private var errorMessage = ""
    @State private var confirmsCredentialRemoval = false
     
    @State private var copiedLink = false
     
    @State private var savingLibraryLink = false
     
     
     
    @State private var openedWith: (url: String, auto: Bool, hours: Int)?

    init(profile: Profile, model: ProfilesViewModel, library: LibraryFacts? = nil) {
        self.profile = profile
        self.model = model
        self.library = library
        if case .url(let url) = profile.source {
             
             
             
            _subscriptionURL = State(
                initialValue: ProfileImportRouter.confirmationText(for: url)
            )
        } else {
            _subscriptionURL = State(initialValue: "")
        }
        _autoUpdate = State(initialValue: profile.autoUpdate)
        _updateIntervalHours = State(
            initialValue: profile.updateIntervalHours
        )
        _libraryIntervalHours = State(initialValue: library?.intervalHours ?? 0)
    }

    var body: some View {
        ClashFeatureNavigationContainer {
            Form {
                if let library {
                     
                     
                     
                     
                     
                     
                     
                    Section {
                         
                         
                        TextField("", text: $subscriptionURL,
                                  prompt: Text(verbatim: "https://example.com/config.yaml"))
                            .labelsHidden()
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("profile-metadata.url")
                         
                         
                         
                        Picker("Update Interval", selection: $libraryIntervalHours) {
                            Text("Manually").tag(0)
                            ForEach([1, 6, 12, 24, 48, 168], id: \.self) { hours in
                                Text(clash: .format("Every %@ hours", [String(hours)])).tag(hours)
                            }
                            if ![0, 1, 6, 12, 24, 48, 168].contains(libraryIntervalHours) {
                                Text(clash: .format("Every %@ hours", [String(libraryIntervalHours)])).tag(libraryIntervalHours)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("profile-metadata.interval")
                        copyLinkRow
                    } header: {
                        Text("Profile URL")
                    } footer: {
                        if library.sharedBy > 1 {
                            Text(clash: .format("%@ configurations use this link; changing it changes it for all of them.",
                                               [String(library.sharedBy)]))
                        }
                    }
                } else {
                Section {
                     
                     
                     
                     
                     
                    TextField(
                        "",
                        text: $subscriptionURL,
                        prompt: Text(verbatim: "https://example.com/config.yaml")
                    )
                    .labelsHidden()
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("profile-metadata.url")

                    Toggle(
                        "Automatic Updates",
                        isOn: $autoUpdate
                    )
                    .accessibilityIdentifier(
                        "profile-metadata.auto-update"
                    )

                    if autoUpdate {
                        Stepper(
                            value: $updateIntervalHours,
                            in: 1...168
                        ) {
                            HStack {
                                Text("Interval")
                                Spacer()
                                Text(
                                    "\(updateIntervalHours) hours"
                                )
                                .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier(
                            "profile-metadata.interval"
                        )
                    }
                    copyLinkRow
                } header: {
                    Text("Profile URL")
                }
                }

                if ProfileMetadataUpdate.strippingSourceCredentials(
                    from: profile
                ) != nil {
                    Section {
                        Button(role: .destructive) {
                            confirmsCredentialRemoval = true
                        } label: {
                            Text("Remove Stored URL Credentials")
                        }
                        .accessibilityIdentifier("profile-metadata.strip-credentials")
                    } footer: {
                        Text("Removing them may require importing again.")
                    }
                }

                if !errorMessage.isEmpty {
                    Section {
                        ClashStatusMessage(
                            text: .copy(errorMessage),
                            kind: .error
                        )
                    }
                }
            }
            .clashPageTitle("Profile URL Settings")
            .alert("Remove Stored URL Credentials", isPresented: $confirmsCredentialRemoval) {
                Button("Remove Stored URL Credentials", role: .destructive) { stripStoredCredentials() }
                    .accessibilityIdentifier("profile-metadata.strip-credentials.confirm")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The saved profile URL carries sign-in details or query values. Removing them keeps the scheme, host and path only, and may require re-importing if the provider needs them.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !insideProductModal {
                        Button("Cancel") {
                            dismissPresentation()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !insideProductModal {
                        Button("Save") {
                            save()
                        }
                        .disabled((library != nil && !hasChanges) || savingLibraryLink)
                        .accessibilityIdentifier(
                            "profile-metadata.save"
                        )
                    }
                }
            }
            .clashProductModalRoot(title: "Profile URL Settings")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if insideProductModal {
                     
                    ClashModalActionBar(
                        primaryTitle: "Save",
                        primaryDisabled: !hasChanges || savingLibraryLink,
                        isBusy: savingLibraryLink,
                        onPrimary: save
                    )
                }
            }
        }
        .clashStackNavigationViewStyle()
        .clashCapturesDismiss(dismiss)
        .onAppear {
            if openedWith == nil {
                openedWith = (subscriptionURL, autoUpdate, updateIntervalHours)
            }
        }
    }

     
     
    @ViewBuilder
    private var copyLinkRow: some View {
        if let link = model.subscriptionLink(for: profile), !link.isEmpty {
            Button {
#if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link, forType: .string)
#else
                UIPasteboard.general.string = link
#endif
                copiedLink = true
            } label: {
                HStack {
                    Label { Text("Copy Profile URL") } icon: { Image(systemName: ClashSymbol.docOnDoc.name) }
                    if copiedLink {
                        Spacer()
                        Text("Copied").foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("profile-metadata.copy-link")
        }
    }

    private func stripStoredCredentials() {
        do {
            try model.stripSourceCredentials(profile)
            dismissPresentation()
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? "Profile settings could not be saved."
        }
    }

     
    private var hasChanges: Bool {
        guard let openedWith else { return false }
        return openedWith.url != subscriptionURL
            || openedWith.auto != autoUpdate
            || openedWith.hours != updateIntervalHours
            || (library.map { $0.intervalHours != libraryIntervalHours } ?? false)
    }

    private func save() {
        if let library {
            guard !savingLibraryLink else { return }
             
             
            let typed = subscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: typed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  !(url.host ?? "").isEmpty else {
                errorMessage = "Enter a full link, starting with https://."
                return
            }
            savingLibraryLink = true
            Task { @MainActor in
                defer { savingLibraryLink = false }
                do {
                    try await saveLibraryLink(library)
                    dismissPresentation()
                } catch {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? "Profile settings could not be saved."
                }
            }
            return
        }
        do {
            try model.updateMetadata(
                profile,
                label: profile.label,
                subscriptionURL: subscriptionURL,
                autoUpdate: autoUpdate,
                updateIntervalHours: updateIntervalHours
            )
            dismissPresentation()
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? "Profile settings could not be saved."
        }
    }

     
     
     
    private func saveLibraryLink(_ library: LibraryFacts) async throws {
        guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        let snapshot = try await Task.detached { try store.snapshot() }.value
        guard let record = snapshot.sources.first(where: { $0.id == library.sourceID }) else {
            throw ConfigurationLibraryError.missingDependency(library.sourceID)
        }
        var draft = ConfigurationSourceSettingsDraft(source: record)
        let url = subscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let linkChanged = url != draft.url
        draft.url = url
        draft.intervalHours = libraryIntervalHours
        _ = try await model.saveConfigurationSourceSettings(record.id, draft: draft, generation: snapshot.generation)
         
        if linkChanged, let latest = model.profiles.first(where: { $0.id == profile.id }) {
            await model.syncAwaitingLibrary(latest)
        }
    }

    private func dismissPresentation() {
        dismiss.closeModalOrDismiss()
    }
}

 
 
 
 
 
struct ClashOptionalNavigationContainer<Content: View>: View {
    let owns: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        if owns {
             
             
             
             
            if #available(iOS 16.0, *) {
                 
                 
                 
                 
                 
                ClashPushableNavigationStack { content() }
            } else {
                NavigationView { content() }
                    .clashStackNavigationViewStyle()
            }
        } else {
            content()
        }
    }
}


 
@available(iOS 16.0, *)
private struct ClashPushableNavigationStack<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) { content() }
            .environment(
                \.clashPushRoute,
                ClashClientUI.ClashRoutePusher { route in
                    path.append(route)
                }
            )
    }
}


 
 
 
 
 
 
 
 
 
struct ProfileProjectionLoader<Content: View>: View {
    let profile: Profile
    @ObservedObject var model: ProfilesViewModel
    @ViewBuilder let content: (String?) -> Content
    @State private var projected: String?
    @State private var ready = false

    var body: some View {
        Group {
            if ready {
                content(projected)
            } else {
                ProfileEditorOpeningPlaceholder(identifier: "profile.projection.loading")
            }
        }
        .task(id: profile.id) {
            projected = await model.loadUIProjectedYAML(for: profile)
            ready = true
        }
    }
}

 
 
struct ProfileEditorOpeningPlaceholder: View {
    let identifier: String

    var body: some View {
        VStack(spacing: ClashTheme.Spacing.compact) {
            Spacer()
            ProgressView()
            Text(clash: .copy("Opening Editor"))
                .font(.callout)
                .foregroundStyle(.secondary)
            ClashOpeningCancelButton()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ClashTheme.canvas.ignoresSafeArea())
        .accessibilityIdentifier(identifier)
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ProfileEditorDraftLoader<Draft, Content: View>: View {
    let identifier: String
    let build: @Sendable () -> Draft
    @ViewBuilder let content: (Draft) -> Content
    @State private var draft: Draft?

    init(identifier: String, build: @escaping @Sendable () -> Draft, @ViewBuilder content: @escaping (Draft) -> Content) {
        self.identifier = identifier
        self.build = build
        self.content = content
    }

    var body: some View {
        Group {
            if let draft {
                content(draft)
            } else {
                ProfileEditorOpeningPlaceholder(identifier: identifier)
            }
        }
        .task {
            guard draft == nil else { return }
            let build = build
            let built = await Task.detached(priority: .userInitiated) { build() }.value
            guard !Task.isCancelled else { return }
            draft = built
        }
    }
}

struct ProfileSourceEditorLoader: View {
    let profile: Profile
    @ObservedObject var model: ProfilesViewModel
    var savesIndependentSource = false
    @State private var source: String?
    @State private var read = false
    @State private var tooLarge = false

    var body: some View {
        Group {
            if tooLarge {
                 
                 
                 
                List {
                    Text(clash: .copy("These rules are too many to edit one by one here. They run as written in the configuration's file."))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("profile.sourceEditor.tooLarge")
                    if ClashSheetSurface.coversOnThisSystem { ClashOpeningCancelButton() }
                }
                .navigationTitle(Text(clash: .copy("Edit Source")))
            } else if read {
                ProfileEditView(
                    profile: profile,
                    rawYAML: source,
                    savesIndependentSource: savesIndependentSource
                ) { updated, rawYAML, resources, disablingAutoUpdate in
                    try await model.updateEdited(
                        updated,
                        sourceYAML: rawYAML,
                        resourceFiles: resources,
                        disablingAutoUpdate: disablingAutoUpdate
                    )
                }
            } else {
                ProfileEditorOpeningPlaceholder(identifier: "profile.sourceEditor.loading")
            }
        }
        .task(id: profile.id) {
            let profile = profile
            let workingDir = model.workingDir
            if await Task.detached(priority: .userInitiated, operation: {
                ProfilesViewModel.sourceIsTooLargeToReadWhole(profile, workingDir: workingDir)
            }).value {
                tooLarge = true
                return
            }
            source = await model.loadSourceYAML(for: profile)
            read = true
        }
    }
}


 
 
 
 
 
@MainActor
final class ProfileCenterFacts: ObservableObject {
    struct Snapshot: Equatable {
        var profiles: [Profile]
        var activeProfileID: String?
        var busyProfileID: String?
        var statusMessage: ClashDisplayText
        var batchReport: BatchUpdateReport?
        var isBatchSyncing: Bool
        var libraryHasFetchableSource: Bool
        var lastFailure: ConfigurationFailure?
        var isUpdatingNodeLibrary: Bool
         
         
         
        var editableSourceIDs: Set<String>

        @MainActor init(_ model: ProfilesViewModel) {
            profiles = model.profiles
            activeProfileID = model.activeProfileID
            busyProfileID = model.busyProfileID
            statusMessage = model.statusMessage
            batchReport = model.batchReport
            isBatchSyncing = model.isBatchSyncing
            libraryHasFetchableSource = model.libraryHasFetchableSource
            lastFailure = model.lastFailure
            isUpdatingNodeLibrary = model.isUpdatingNodeLibrary
            editableSourceIDs = Set(model.profiles.filter { model.hasEditableSource(for: $0) }.map(\.id))
        }
    }

    @Published private(set) var snapshot: Snapshot
    private let model: ProfilesViewModel
    private var watching: AnyCancellable?
    private var readScheduled = false

    init(model: ProfilesViewModel) {
        self.model = model
        snapshot = Snapshot(model)
         
         
        watching = model.objectWillChange.sink { [weak self] _ in self?.scheduleRead() }
    }

    private func scheduleRead() {
        guard !readScheduled else { return }
        readScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.readScheduled = false
            let next = Snapshot(self.model)
            if next != self.snapshot { self.snapshot = next }
        }
    }
}
