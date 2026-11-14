import Foundation
import ClashClientKit
import SwiftUI

public enum ClashProfilesCapabilityDestination:
    Hashable,
    Identifiable,
    Sendable
{
    case importProfile
    case backupRestore
    case modules
    case subscriptionSettings(Profile.ID)
    case sourceEditor(Profile.ID)
    case configurationSources(Profile.ID)
    case configurationRules(Profile.ID)
     
     
    case runtimePreview(Profile.ID)
     
     
     
     
     
    case rules(Profile.ID)
    case override(Profile.ID)
    case network(Profile.ID)
    case trust(Profile.ID)

     
     
     
     
     
    public var presentsImmersively: Bool {
        if case .sourceEditor = self { return true }
        return false
    }

    public var id: String {
        switch self {
        case .importProfile:
            "import"
        case .backupRestore:
            "backup"
        case .modules:
            "adblock"
        case .subscriptionSettings(let id):
            "subscription|\(id.rawValue)"
        case .rules(let id):
            "rules|\(id.rawValue)"
        case .override(let id):
            "override|\(id.rawValue)"
        case .network(let id):
            "network|\(id.rawValue)"
        case .trust(let id):
            "trust|\(id.rawValue)"
        case .sourceEditor(let id):
            "source|\(id.rawValue)"
        case .configurationSources(let id):
            "configuration-sources|\(id.rawValue)"
        case .configurationRules(let id):
            "configuration-rules|\(id.rawValue)"
        case .runtimePreview(let id):
            "runtime|\(id.rawValue)"
        }
    }
}

 
 
 
 
 
 
 
 
public enum ClashProfilesDuplicateNaming {
    public static func message(label: String?) -> ClashDisplayText {
        guard let label, !label.isEmpty else { return .copy("The copy is in the configuration list.") }
        return .format("The copy is named “%@”.", [label])
    }
}

public struct ClashConfigurationPageParts {
    public let sections: AnyView
    public let host: (AnyView) -> AnyView
     
     
     
     
    public let actions: AnyView?

    public init(sections: AnyView, actions: AnyView? = nil, host: @escaping (AnyView) -> AnyView) {
        self.sections = sections
        self.actions = actions
        self.host = host
    }
}

private struct ClashConfigurationSearchingKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
     
     
     
     
    var clashConfigurationSearching: Bool {
        get { self[ClashConfigurationSearchingKey.self] }
        set { self[ClashConfigurationSearchingKey.self] = newValue }
    }
}

 
 
 
struct ClashConfigurationPageSearchSwitch<Before: View, After: View>: View {
    @Environment(\.clashConfigurationSearching) private var searching
    let sections: AnyView
    @ViewBuilder let before: () -> Before
    @ViewBuilder let after: () -> After

    var body: some View {
        if !searching { before() }
        sections
        if !searching { after() }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashProfilesListPresentation {
    public let profiles: [ClashProfileSnapshot]
     
     
     
    public let selectingProfileID: Profile.ID?
     
     
    public let selectionFailure: (Profile.ID) -> ClashDisplayText?
    public let select: (Profile.ID) -> Void
    public let openDetail: (Profile.ID) -> Void
     
     
     
     
    public let openImport: () -> Void
     
     
    public let reorder: ([Profile.ID]) -> Void
    public let perform: (ClashProfilesCommand) -> Void
}

 
 
 
 
 
 
public struct ClashProfilesView<Icon: View, CapabilityContent: View>: View {
    private let snapshot: AppleClientSnapshot
    private let actions: AppleClientActions
    private let presentationClass: ClashPresentationClass
     
    private let showsDismissControl: Bool
    private let isCenterSection: Bool
    private let palette: ClashProductPalette
    private let opensImportInitially: Bool
     
     
    private let opensModules: Bool
    private let pagePresentation: (AnyView) -> AnyView
     
     
     
     
    private let detailPresentation: (AnyView) -> AnyView
    private let icon: (ClashSymbol) -> Icon
    private let capabilityContent:
        (ClashProfilesCapabilityDestination) -> CapabilityContent
     
     
     
    private let capabilityInterceptor:
        ((ClashProfilesCapabilityDestination) -> Bool)?
     
     
     
     
    private let listPresentation:
        ((ClashProfilesListPresentation) -> AnyView)?
     
     
     
     
    private let quickAdd: (() -> AnyView)?
     
     
     
    private let quickAddLeads: Bool
     
     
     
     
     
    private let configurationPage: ((Profile.ID) -> ClashConfigurationPageParts)?

     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var requestedProfileID: Profile.ID?
    @Environment(\.clashPushRoute) private var pushRoute
    @Environment(\.clashPopRoute) private var popRoute
    @State private var activeCapability:
        ClashProfilesCapabilityDestination?
    @State private var showsReorder = false
    @State private var showsBatchDetails = false
    @State private var displayedProfiles: [ClashProfileSnapshot]
    @State private var draggedProfileID: String?
    @State private var reorderDropTarget: ClashReorderDropTarget?
    @State private var pendingSelectionID: Profile.ID?
    @State private var selectionFailure: ClashProfileSelectionFailure?
    @State private var didPresentInitialImport = false
    @State private var showsModules = false
     
    @State private var pendingDeletion: ClashProfileSnapshot?

    public init(
        snapshot: AppleClientSnapshot,
        actions: AppleClientActions,
        initialProfileID: Profile.ID? = nil,
        opensImportInitially: Bool = false,
        opensModules: Bool = false,
        presentationClass: ClashPresentationClass,
        showsDismissControl: Bool = true,
        isCenterSection: Bool = false,
        palette: ClashProductPalette,
        pagePresentation: @escaping (AnyView) -> AnyView = { $0 },
        detailPresentation: @escaping (AnyView) -> AnyView = { $0 },
        listPresentation:
            ((ClashProfilesListPresentation) -> AnyView)? = nil,
        quickAdd: (() -> AnyView)? = nil,
        quickAddLeads: Bool = false,
        configurationPage: ((Profile.ID) -> ClashConfigurationPageParts)? = nil,
        capabilityInterceptor:
            ((ClashProfilesCapabilityDestination) -> Bool)? = nil,
        @ViewBuilder icon: @escaping (ClashSymbol) -> Icon,
        @ViewBuilder capabilityContent: @escaping (
            ClashProfilesCapabilityDestination
        ) -> CapabilityContent
    ) {
        self.snapshot = snapshot
        self.actions = actions
        self.presentationClass = presentationClass
        self.showsDismissControl = showsDismissControl
        self.isCenterSection = isCenterSection
        self.palette = palette
        self.opensImportInitially = opensImportInitially
        self.opensModules = opensModules
        self.pagePresentation = pagePresentation
        self.detailPresentation = detailPresentation
        self.listPresentation = listPresentation
        self.quickAdd = quickAdd
        self.quickAddLeads = quickAddLeads
        self.configurationPage = configurationPage
        self.capabilityInterceptor = capabilityInterceptor
        self.icon = icon
        self.capabilityContent = capabilityContent
        _requestedProfileID = State(initialValue: initialProfileID)
        _displayedProfiles = State(
            initialValue: snapshot.profiles.profiles
        )
    }

    public var body: some View {
        let _ = ClashPerf.count("profiles.body")
        pagePresentation(AnyView(routedRootPage))
            .clashProductModal(
                item: $activeCapability,
                role: .page,
                immersive: { $0.presentsImmersively }
            ) { destination in
                capabilityContent(destination)
                    .clashModalPresentation(.page)
            }
            .clashProductModal(
                isPresented: $showsReorder,
                role: .form
            ) {
                ClashProfileReorderView(
                    profiles: snapshot.profiles.profiles,
                    snapshot: snapshot,
                    actions: actions,
                    palette: palette
                )
                .clashModalPresentation(.form)
            }
            .clashProductModal(
                isPresented: Binding(
                    get: { snapshot.profiles.batchReport != nil && (!isCenterSection || showsBatchDetails) },
                    set: { presented in
                        if !presented {
                            showsBatchDetails = false
                            if !isCenterSection { send(.dismissBatch) }
                        }
                    }
                ),
                role: .page,
                refreshID: batchModalRefreshID
            ) {
                Group {
                    if let report = snapshot.profiles.batchReport {
                        ClashProfileBatchReportView(
                            report: report,
                            snapshot: snapshot,
                            actions: actions,
                            icon: icon
                        )
                    }
                }
                .clashModalPresentation(.page)
            }
            .onAppear {
                guard opensImportInitially, !didPresentInitialImport else {
                    return
                }
                didPresentInitialImport = true
                activeCapability = .importProfile
            }
             
             
            .clashDeleteConfirmation(presenting: $pendingDeletion, name: \.label,
                actionTitle: .copy("Delete Profile"),
                message: { _ in .copy("This profile will be deleted. Sources and rule schemes in the library will remain.") },
                identifier: "profile-center.delete.confirm") { doomed in performDeletion(doomed) }
        .clashCapturesDismiss(dismiss)
    }

     
     
     
    private var batchModalRefreshID: AnyHashable {
        guard let report = snapshot.profiles.batchReport else {
            return AnyHashable(["profile-batch", "none"])
        }
        var components = [
            "profile-batch",
            report.id.uuidString,
            report.title,
            String(report.expectedCount),
            report.wasCancelled ? "cancelled" : "active",
            report.isRunning ? "running" : "finished",
        ]
        components.append(contentsOf: report.items.flatMap { item in
            [
                item.id.rawValue,
                item.label,
                item.state.rawValue,
                item.message,
                item.diagnosticCode ?? "",
            ]
        })
        return AnyHashable(components)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    private var routedRootPage: some View {
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            rootPage
                .navigationDestination(
                    for: ClashProfileRoute.self
                ) { route in
                    ClashLazyView {
                        switch route {
                        case .detail(let id):
                            pagePresentation(detailPresentation(
                                AnyView(
                                    ClashProfileDetailView(
                                        profileID: id,
                                        snapshot: snapshot,
                                        actions: actions,
                                        presentationClass: presentationClass,
                                        palette: palette,
                                        pagePresentation: pagePresentation,
                                        configurationPage: configurationPage,
                                        capabilityInterceptor: capabilityInterceptor,
                                        icon: icon,
                                        capabilityContent: capabilityContent
                                    )
                                )
                            ))
                            .clashPushedDetailPage()
                            .environment(\.clashPushRoute, pushRoute)
                            .environment(\.clashPopRoute, popRoute)
                            .modifier(ClashSetterRoutedBack())
                             
                            .clashDeparturePage()
                             
                             
                             
                            .environment(
                                \.clashRegularShellOwnsCanvas,
                                presentationClass == .regularTouch
                                    || presentationClass == .desktop
                            )
                        }
                    }
                }
        } else {
            rootPage
        }
    }

     
     
     
     
     
    private func performDeletion(_ profile: ClashProfileSnapshot) {
        selectionFailure = nil
        Task { @MainActor in
            do {
                let result = try await actions.performForResult(
                    .profiles(.delete(id: profile.id)),
                    allowedBy: snapshot
                )
                switch result {
                case .profileDeleted(let id) where id == profile.id:
                    break
                case .profileActionRefused(let reason):
                    selectionFailure = ClashProfileSelectionFailure(profileID: profile.id, message: reason, outlivesTheList: true)
                default:
                     
                     
                    selectionFailure = ClashProfileSelectionFailure(
                        profileID: profile.id, message: .copy("The profile was not deleted."), outlivesTheList: true)
                }
            } catch is CancellationError {
                 
            } catch {
                selectionFailure = ClashProfileSelectionFailure(
                    profileID: profile.id, message: .copy(error.localizedDescription), outlivesTheList: true)
            }
        }
    }

     
     
     
     
     
    @ViewBuilder
    private var rootPageContent: some View {
        if let listPresentation {
            listPresentation(
                ClashProfilesListPresentation(
                    profiles: displayedProfiles,
                    selectingProfileID: pendingSelectionID,
                    selectionFailure: { id in
                        selectionFailure?.profileID == id
                            ? selectionFailure?.message
                            : nil
                    },
                     
                     
                     
                     
                    select: { id in
                        guard let profile = displayedProfiles.first(where: {
                            $0.id == id
                        }) else { return }
                        performSelection(profile, closesPage: false)
                    },
                    openDetail: { pushRoute?(ClashProfileRoute.detail($0)) },
                    openImport: { activeCapability = .importProfile },
                    reorder: applyReorder,
                    perform: send
                )
            )
        } else {
            ownRootPage
        }
    }

     
     
     
     
    private var hidesEmptyProfilesSection: Bool {
        displayedProfiles.isEmpty && quickAdd != nil && isCenterSection
    }

    @ViewBuilder
    private var ownRootPage: some View {
        if isCenterSection {
            ClashConfigurationLibraryList(palette: palette, accessibilityIdentifier: "profile-center.root") {
                if let quickAdd, isCenterSection, quickAddLeads { quickAdd() }
                if !hidesEmptyProfilesSection { profilesSection }
                if hasRemoteProfile, snapshot.profiles.canSyncAll {
                    Section {
                        ClashConfigurationUpdateButton(title: "Update All", isUpdating: snapshot.profiles.batchReport?.isRunning == true,
                            disabled: false, action: { send(.syncAll) })
                            .accessibilityIdentifier("profile-center.sync-all")
                    } footer: {
                         
                         
                         
                         
                        if let report = snapshot.profiles.batchReport {
                            HStack(spacing: ClashTheme.Spacing.compact) {
                                if report.isRunning {
                                    Text("\(report.items.count) / \(report.expectedCount)").monospacedDigit()
                                } else {
                                    batchSummaryLine(report)
                                }
                                if report.needsAttention {
                                    Button("Details") { showsBatchDetails = true }
                                        .foregroundStyle(.tint)
                                        .accessibilityIdentifier("profile-center.update-details")
                                }
                            }
                            .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            .accessibilityIdentifier("profile-center.update-status")
                            .task(id: report.settledKey) {
                                guard !report.isRunning, !report.needsAttention else { return }
                                try? await Task.sleep(nanoseconds: Self.cleanBatchReportLingersNanoseconds)
                                send(.dismissBatch)
                            }
                        }
                    }
                }
                if let quickAdd, isCenterSection {
                    if !quickAddLeads { quickAdd() }
                } else if snapshot.profiles.canCreateEmpty || snapshot.profiles.canImport { addSection }
                if let modules = snapshot.profiles.modules { modulesSection(modules) }
                if snapshot.profiles.canBackup { dataSection }
                failureSection
            }
             
             
             
            .modifier(ClashLibraryPullToUpdate(action: hasRemoteProfile && snapshot.profiles.canSyncAll ? {
                try? await actions.perform(.profiles(.syncAll), allowedBy: snapshot)
            } : nil))
        } else {
            ClashProductRootPage(palette: palette, accessibilityIdentifier: "profile-center.root") {
                if let quickAdd, isCenterSection, quickAddLeads { quickAdd() }
                if !hidesEmptyProfilesSection { profilesSection }
                if let quickAdd, isCenterSection {
                    if !quickAddLeads { quickAdd() }
                } else if snapshot.profiles.canCreateEmpty || snapshot.profiles.canImport { addSection }
                if let modules = snapshot.profiles.modules { modulesSection(modules) }
                if snapshot.profiles.canBackup { dataSection }
                failureSection
            }
        }
    }

    private var rootPage: some View {
        rootPageContent
        .background(initialDetailLink)
        .background(modulesLink)
        .onAppear { if opensModules { showsModules = true } }
        .onChange(of: opensModules) { opens in
            if opens { showsModules = true }
        }
        .environment(\.clashDetailCanvas, palette.canvas)
        .onChange(of: snapshot.profiles.profiles) { profiles in
             
             
             
             
            if let failure = selectionFailure, failure.outlivesTheList, Date().timeIntervalSince(failure.said) < 3,
               profiles.contains(where: { $0.id == failure.profileID }) {
                 
            } else {
                selectionFailure = nil
            }
            displayedProfiles = profiles
        }
         
         
         
        .modifier(
            ClashProfilesRootTitleModifier(
                showsDismissControl: showsDismissControl
            )
        )
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) {
                 
                 
                if showsDismissControl {
                    ClashSheetCloseButton {
                        dismiss()
                    }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                 
                 
                 
                 
                 
                 
                 
                if showsReorderControl || showsAddControl {
                    ControlGroup {
                        if showsReorderControl {
                            Button {
                                showsReorder = true
                            } label: {
                                icon(.arrowUpArrowDown)
                                    .clashToolbarGlyph()
                                    .clashToolbarCapsuleEnd(.leading)
                            }
                            .accessibilityLabel("Reorder Profiles")
                            .accessibilityIdentifier("profile-center.reorder")

                             
                             
                             
                             
                            if showsAddControl {
                                ClashToolbarDivider()
                            }
                        }

                        if showsAddControl {
                             
                             
                             
                             
                             
                             
                             
                            Button {
                                activeCapability = .importProfile
                            } label: {
                                icon(.plusCircle)
                                    .clashToolbarGlyph()
                                    .clashToolbarCapsuleEnd(showsReorderControl ? .trailing : [])
                            }
                            .accessibilityLabel(ClashCopy.key(ClashConfigurationAddition.configuration.entryTitle))
                            .accessibilityIdentifier(
                                "profile-center.add.toolbar"
                            )
                        }
                    }
                    .clashReaderControlGroupStyle()
                }
            }
        }
    }

     
     
    private var showsReorderControl: Bool {
        ClashPlatformLayout.profileReorderingUsesDedicatedTask
            && snapshot.profiles.canReorder
            && snapshot.profiles.profiles.count > 1
    }

     
     
     
     
     
     
     
     
    private var showsAddControl: Bool {
        listPresentation == nil
            && (snapshot.profiles.canCreateEmpty
                || snapshot.profiles.canImport)
    }

     
     
     
     
     
     
    @ViewBuilder
    private var profilesSection: some View {
        if isCenterSection || ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            Section {
                if displayedProfiles.isEmpty {
                    profilesEmptyState
                } else {
                ForEach(
                    Array(
                        displayedProfiles.enumerated()
                    ),
                    id: \.element.id
                ) { index, profile in
                    ClashProfileRow(
                        profile: profile,
                        isSelecting:
                            pendingSelectionID == profile.id,
                         
                         
                         
                         
                        isBlocked: pendingSelectionID != nil
                            && pendingSelectionID != profile.id,
                        destination: {
                            pagePresentation(detailPresentation(
                            AnyView(
                                ClashProfileDetailView(
                                    profileID: profile.id,
                                    snapshot: snapshot,
                                    actions: actions,
                                    presentationClass:
                                        presentationClass,
                                    palette: palette,
                                    pagePresentation:
                                        pagePresentation,
                                    configurationPage: configurationPage,
                                    capabilityInterceptor: capabilityInterceptor,
                                    icon: icon,
                                    capabilityContent:
                                        capabilityContent
                                )
                            )
                            ))
                        },
                        select: {
                            select(profile)
                        },
                        palette: palette,
                        icon: icon, presentsDetailModally: isCenterSection
                    )
                    .clashDirectReorderRow(
                        id: profile.id.rawValue,
                        label: profile.label,
                        enabled: !isCenterSection && snapshot.profiles.canReorder
                            && displayedProfiles.count > 1,
                        draggedID: $draggedProfileID,
                        dropTarget: $reorderDropTarget,
                        canMoveUp: index > displayedProfiles.startIndex,
                        canMoveDown: index
                            < displayedProfiles.index(
                                before: displayedProfiles.endIndex
                            ),
                        onMove: reorderProfile,
                        onMoveUp: {
                            moveDisplayedProfile(
                                id: profile.id,
                                offset: -1
                            )
                        },
                        onMoveDown: {
                            moveDisplayedProfile(
                                id: profile.id,
                                offset: 1
                            )
                        }
                    )
                    .modifier(ClashProfileRowQuickActions(
                        profile: profile,
                        enabled: isCenterSection,
                        icon: icon,
                        update: { send(.sync(id: profile.id)) },
                        copyLink: { send(.copySubscriptionLink(id: profile.id)) },
                        delete: { pendingDeletion = profile }
                    ))

                    if let failure = selectionFailure,
                       failure.profileID == profile.id {
                        Text(clash: failure.message)
                            .font(.caption)
                            .foregroundStyle(Color.red)
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                            .padding(
                                .horizontal,
                                isCenterSection ? 0 : ClashTheme.Spacing.standard
                            )
                            .padding(
                                .bottom,
                                ClashTheme.Spacing.row
                            )
                            .accessibilityIdentifier(
                                "profile-center.select-failure"
                            )
                    }

                    if !isCenterSection && index
                        < displayedProfiles.count - 1
                    {
                        ClashRowDivider()
                            .padding(
                                .leading,
                                ClashTheme.Spacing.standard
                            )
                    }
                }
                 
                 
                 
                }
            } header: {
                profilesHeader
            }
        } else {
            traditionalProfilesSection
        }
    }

    private var profilesEmptyState: some View {
        ClashEmptyState(
            title: "No Profiles",
            message: ""
        ) {
            icon(.listBulletRectangle)
        }
        .padding(ClashTheme.Spacing.standard)
        
    }

    private var traditionalProfilesSection: some View {
        VStack(alignment: .leading, spacing: ClashTheme.Spacing.row) {
            profilesHeader

            if displayedProfiles.isEmpty {
                ClashCardSurface(
                    fill: palette.card,
                    separator: palette.separator
                ) {
                    ClashEmptyState(
                        title: "No Profiles",
                        message:
                            "Add a profile to choose its sources and rules."
                    ) {
                        icon(.listBulletRectangle)
                    }
                    .padding(ClashTheme.Spacing.standard)
                }
            } else {
                ClashCardSurface(
                    fill: palette.card,
                    separator: palette.separator
                ) {
                    VStack(spacing: 0) {
                        ForEach(
                            Array(
                                displayedProfiles.enumerated()
                            ),
                            id: \.element.id
                        ) { index, profile in
                            ClashProfileRow(
                                profile: profile,
                                isSelecting:
                                    pendingSelectionID == profile.id,
                                 
                                 
                                 
                                 
                                isBlocked: pendingSelectionID != nil
                                    && pendingSelectionID != profile.id,
                                destination: {
                                    pagePresentation(detailPresentation(
                                    AnyView(
                                        ClashProfileDetailView(
                                            profileID: profile.id,
                                            snapshot: snapshot,
                                            actions: actions,
                                            presentationClass:
                                                presentationClass,
                                            palette: palette,
                                            pagePresentation:
                                                pagePresentation,
                                            configurationPage: configurationPage,
                                            capabilityInterceptor: capabilityInterceptor,
                                            icon: icon,
                                            capabilityContent:
                                                capabilityContent
                                        )
                                    )
                                    ))
                                },
                                select: {
                                    select(profile)
                                },
                                palette: palette,
                                icon: icon, presentsDetailModally: isCenterSection
                            )
                            .clashDirectReorderRow(
                                id: profile.id.rawValue,
                                label: profile.label,
                                enabled: snapshot.profiles.canReorder
                                    && displayedProfiles.count > 1,
                                draggedID: $draggedProfileID,
                                dropTarget: $reorderDropTarget,
                                canMoveUp: index > displayedProfiles.startIndex,
                                canMoveDown: index
                                    < displayedProfiles.index(
                                        before: displayedProfiles.endIndex
                                    ),
                                onMove: reorderProfile,
                                onMoveUp: {
                                    moveDisplayedProfile(
                                        id: profile.id,
                                        offset: -1
                                    )
                                },
                                onMoveDown: {
                                    moveDisplayedProfile(
                                        id: profile.id,
                                        offset: 1
                                    )
                                }
                            )

                            if let failure = selectionFailure,
                               failure.profileID == profile.id {
                                Text(clash: failure.message)
                                    .font(.caption)
                                    .foregroundStyle(Color.red)
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                                    .padding(
                                        .horizontal,
                                        ClashTheme.Spacing.standard
                                    )
                                    .padding(
                                        .bottom,
                                        ClashTheme.Spacing.row
                                    )
                                    .accessibilityIdentifier(
                                        "profile-center.select-failure"
                                    )
                            }

                            if index
                                < displayedProfiles.count - 1
                            {
                                ClashRowDivider()
                                    .padding(
                                        .leading,
                                        ClashTheme.Spacing.standard
                                    )
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

     
     
     
     
     
     
     
    private var addSection: some View {
        ClashConfigurationLibraryAddCard(kind: .configuration,
            palette: palette, nativeList: isCenterSection, action: { activeCapability = .importProfile })
            .accessibilityIdentifier("profile-center.add")
    }

     
     
     
     
    private func modulesSection(_ entry: ClashModulesEntrySnapshot) -> some View {
        ClashConfigurationLibraryCard(palette: palette, nativeList: isCenterSection) {
            ClashRoutedViewLink(
                showsDisclosureIndicator: false
            ) {
                capabilityContent(.modules)
            } label: {
                ClashProfileActionRow(
                    title: "Modules",
                    value: entry.value,
                    symbol: .shieldLefthalfFilled,
                    tint: .primary,
                    showsDisclosure: !isCenterSection,
                    icon: icon
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile-center.modules")
        }
    }

    private var dataSection: some View {
        ClashConfigurationLibraryCard(title: "Data", palette: palette, nativeList: isCenterSection) {
            ClashRoutedViewLink(
                showsDisclosureIndicator: false
            ) {
                capabilityContent(.backupRestore)
            } label: {
                ClashProfileActionRow(
                    title: "iCloud Backup & Restore",
                    symbol: .icloudAndArrowUp,
                    tint: .primary,
                    showsDisclosure: !isCenterSection,
                    icon: icon
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile-center.backup")
        }
    }

    @ViewBuilder
    private var failureSection: some View {
        if let failure = snapshot.profiles.failure {
            ClashCardSurface(
                fill: palette.card,
                separator: palette.separator
            ) {
                VStack(
                    alignment: .leading,
                    spacing: ClashTheme.Spacing.row
                ) {
                    Text(clash: failure.message)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    if failure.canRetry {
                        Button("Try Again") {
                            send(.retryFailure)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(ClashTheme.Spacing.standard)
            }
            .accessibilityIdentifier("profile-center.error")
        }
    }

     
     
     
    private var profileCountTitle: ClashDisplayText {
        let count = snapshot.profiles.profiles.count
        return .format(
            count == 1 ? "%@ profile" : "%@ profiles",
            [String(count)]
        )
    }

    @ViewBuilder
    private var profilesHeader: some View {
        if isCenterSection {
            ClashConfigurationLibraryHeader(title: .copy("Profiles"), count: displayedProfiles.count)
        } else if dynamicTypeSize.isAccessibilitySize {
            accessibilityProfilesHeader
        } else {
            HStack(alignment: .firstTextBaseline) {
                profileCountLabel
                Spacer()
                if hasRemoteProfile,
                   snapshot.profiles.canSyncAll {
                    syncAllButton
                }
            }
        }
    }

    private var accessibilityProfilesHeader: some View {
        VStack(
            alignment: .leading,
            spacing: ClashTheme.Spacing.row
        ) {
            profileCountLabel
            if hasRemoteProfile,
               snapshot.profiles.canSyncAll {
                syncAllButton
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileCountLabel: some View {
        Text(clash: profileCountTitle)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

     
    private static var cleanBatchReportLingersNanoseconds: UInt64 { 4_000_000_000 }

     
     
    private func batchSummaryLine(_ report: ClashProfileBatchReportSnapshot) -> Text {
        var line = Text("")
        for (index, part) in report.summaryParts.enumerated() {
            line = index == 0 ? Text(clash: part) : line + Text(" · ") + Text(clash: part)
        }
        return line
    }

     
     
     
     
     
    private var hasRemoteProfile: Bool {
        snapshot.profiles.profiles.contains {
            $0.source == .remote
        } || snapshot.profiles.libraryHasFetchableSource
    }

    private var syncAllButton: some View {
        Button {
            send(.syncAll)
        } label: {
            Label {
                Text("Update All")
            } icon: {
                icon(.arrowTriangle2Circlepath)
            }
            .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.borderless)
        .disabled(snapshot.profiles.batchReport?.isRunning == true)
        .accessibilityIdentifier("profile-center.sync-all")
    }

     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    private var initialDetailLink: some View {
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
             
             
             
             
             
             
            if let requested = requestedProfileID,
               snapshot.profiles.profile(id: requested) != nil {
                Color.clear
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                    .onAppear {
                         
                         
                         
                        guard let pushRoute else { return }
                        requestedProfileID = nil
                        pushRoute(ClashProfileRoute.detail(requested))
                    }
            }
        } else {
            NavigationLink(
                destination: ClashLazyView {
                    requestedDetail.clashPushedDetailPage()
                },
                isActive: requestedDetailPresented
            ) {
                EmptyView()
            }
            .hidden()
        }
    }

     
     
     
     
     
    @ViewBuilder
    private var modulesLink: some View {
#if !os(macOS)
        ClashRoutedViewDestination(isPresented: $showsModules) {
            capabilityContent(.modules)
                .clashNativePushBoundary()
        }
        .opacity(0)
#endif
    }

    private var requestedDetailPresented: Binding<Bool> {
        Binding(
            get: {
                guard let requestedProfileID else {
                    return false
                }
                return snapshot.profiles.profile(
                    id: requestedProfileID
                ) != nil
            },
            set: { active in
                if !active {
                    requestedProfileID = nil
                }
            }
        )
    }

    @ViewBuilder
    private var requestedDetail: some View {
        if let requestedProfileID {
            pagePresentation(detailPresentation(
                AnyView(
                    ClashProfileDetailView(
                        profileID: requestedProfileID,
                        snapshot: snapshot,
                        actions: actions,
                        presentationClass: presentationClass,
                        palette: palette,
                        pagePresentation: pagePresentation,
                        configurationPage: configurationPage,
                        capabilityInterceptor: capabilityInterceptor,
                        icon: icon,
                        capabilityContent: capabilityContent
                    )
                )
            ))
        } else {
            EmptyView()
        }
    }

    private func select(_ profile: ClashProfileSnapshot) {
        performSelection(profile, closesPage: true)
    }

     
     
     
     
     
     
     
    private func performSelection(
        _ profile: ClashProfileSnapshot,
        closesPage: Bool
    ) {
        guard !profile.isCurrent, pendingSelectionID == nil else {
            return
        }
        pendingSelectionID = profile.id
        selectionFailure = nil
        Task { @MainActor in
            defer { pendingSelectionID = nil }
            do {
                let result = try await actions.performForResult(
                    .profiles(.select(id: profile.id)),
                    allowedBy: snapshot
                )
                if case .profileSelected(let id) = result,
                   id == profile.id {
                    if closesPage {
                        dismiss()
                    }
                } else if case .profileSelectionFailurePresented = result {
                     
                     
                } else {
                     
                     
                     
                     
                     
                    selectionFailure = ClashProfileSelectionFailure(
                        profileID: profile.id,
                        message: "Clash could not switch to this profile."
                    )
                }
            } catch {
                 
                 
                 
                selectionFailure = ClashProfileSelectionFailure(
                    profileID: profile.id,
                     
                     
                     
                     
                     
                    message: .copy(error.localizedDescription)
                )
            }
        }
    }

    private func reorderProfile(
        _ sourceID: String,
        _ destinationID: String,
        _ edge: ClashReorderDropEdge
    ) {
        guard sourceID != destinationID,
              let sourceIndex = displayedProfiles.firstIndex(where: {
                  $0.id.rawValue == sourceID
              }) else {
            return
        }

        var reordered = displayedProfiles
        let moved = reordered.remove(at: sourceIndex)
        guard let targetIndex = reordered.firstIndex(where: {
            $0.id.rawValue == destinationID
        }) else {
            return
        }
        let insertionIndex = edge == .before
            ? targetIndex
            : reordered.index(after: targetIndex)
        reordered.insert(moved, at: insertionIndex)
        guard reordered.map(\.id) != displayedProfiles.map(\.id) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.16)) {
            displayedProfiles = reordered
        }
        send(.reorder(ids: reordered.map(\.id)))
    }

     
     
     
     
     
     
    private func applyReorder(_ ids: [Profile.ID]) {
        guard Set(ids) == Set(displayedProfiles.map(\.id)),
              ids.count == displayedProfiles.count,
              ids != displayedProfiles.map(\.id) else {
            return
        }
        let byID = Dictionary(
            displayedProfiles.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        withAnimation(.easeInOut(duration: 0.16)) {
            displayedProfiles = ids.compactMap { byID[$0] }
        }
        send(.reorder(ids: ids))
    }

    private func moveDisplayedProfile(id: Profile.ID, offset: Int) {
        guard let index = displayedProfiles.firstIndex(where: {
            $0.id == id
        }) else {
            return
        }
        let destination = index + offset
        guard displayedProfiles.indices.contains(destination) else {
            return
        }

        var reordered = displayedProfiles
        reordered.swapAt(index, destination)
        withAnimation(.easeInOut(duration: 0.16)) {
            displayedProfiles = reordered
        }
        send(.reorder(ids: reordered.map(\.id)))
    }

    private func send(_ command: ClashProfilesCommand) {
        Task { @MainActor in
            try? await actions.perform(
                .profiles(command),
                allowedBy: snapshot
            )
        }
    }
}

 
 
enum ClashProfileRoute: Hashable {
    case detail(Profile.ID)
}

 
 
private struct ClashProfileSelectionFailure: Equatable {
    let profileID: Profile.ID
     
    let message: ClashDisplayText
     
     
     
     
     
    let outlivesTheList: Bool
    let said = Date()

    init(profileID: Profile.ID, message: ClashDisplayText, outlivesTheList: Bool = false) {
        self.profileID = profileID; self.message = message; self.outlivesTheList = outlivesTheList
    }
}

 
 
 
 
 
private struct ClashProfileBadge: View {
    let text: ClashDisplayText

    var body: some View {
        Text(clash: text)
            .font(.caption2)
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(.secondary.opacity(0.55), lineWidth: 1)
            )
    }
}

private struct ClashProfileRow<
    Icon: View,
    Destination: View
>: View {
    let profile: ClashProfileSnapshot
    let isSelecting: Bool
    let isBlocked: Bool
     
     
     
     
     
     
    let destination: () -> Destination
    let select: () -> Void
    let palette: ClashProductPalette
    let icon: (ClashSymbol) -> Icon
    var presentsDetailModally = false
    @State private var showsDetail = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let _ = ClashPerf.count("profiles.list.row")
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityProfileRow
            } else {
                standardProfileRow
            }
        }
        .clashProductModal(isPresented: $showsDetail, role: .page) {
            ClashSingleColumnNavigationContainer {
                destination()
                    .clashToolbarUnlessInPanel {
                        ToolbarItem(placement: .cancellationAction) {
                            ClashSheetCloseButton { showsDetail = false }
                        }
                    }
                    .clashProductModalRoot(title: .verbatim(profile.label))
            }
            .environment(\.clashProductModalDismiss, { showsDetail = false })
        }
    }

     
     
     
    @ViewBuilder
    private func rowLink<Label: View>(
        @ViewBuilder label: () -> Label
    ) -> some View {
        if presentsDetailModally {
            Button { showsDetail = true } label: { label() }
        } else if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
             
             
             
             
             
             
             
             
            ClashValueRowLink(
                value: ClashProfileRoute.detail(profile.id)
            ) {
                label()
            }
        } else {
            NavigationLink(
                destination: ClashLazyView {
                    destination().clashPushedDetailPage()
                }
            ) {
                label()
            }
        }
    }

     
     
     
     
     
     
     
    private var standardProfileRow: some View {
         
         
         
         
        HStack(
            alignment: .center,
            spacing: 0
        ) {
            Button(action: select) {
                HStack(
                    alignment: .center,
                    spacing: ClashTheme.Spacing.row
                ) {
                    statusSlot
                    VStack(
                        alignment: .leading,
                        spacing: ClashTheme.Spacing.compact
                    ) {
                         
                         
                         
                        HStack(
                            alignment: .center,
                            spacing: ClashTheme.Spacing.compact
                        ) {
                            Text(profile.label)
                                .font(
                                    .body.weight(
                                        profile.isCurrent
                                            ? .semibold
                                            : .regular
                                    )
                                )
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                            Spacer(minLength: ClashTheme.Spacing.compact)
                            ForEach(Array(profile.badges.enumerated()), id: \.offset) { _, badge in
                                ClashProfileBadge(text: badge)
                                    .fixedSize()
                            }
                        }
                         
                         
                         
                        if let subscription = profile.subscription {
                            ClashSubscriptionUsageView(
                                subscription: subscription,
                                style: .row,
                                note: profile.note
                            )
                        } else if let note = profile.note {
                            Text(clash: note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                         
                         
                         
                         
                        if profile.source == .remote, profile.badges.isEmpty {
                            Text(clash: profile.sourceSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, presentsDetailModally ? 0 : ClashTheme.Spacing.standard)
                .padding(
            .vertical,
            presentsDetailModally ? 0 : ClashMacSettingsMetrics.rowVerticalInset(
                touch: ClashTheme.Spacing.row
            )
        )
                .contentShape(Rectangle())
            }
            .disabled(isBlocked)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(isSelecting || profile.isBusy)
            .accessibilityLabel(
                profile.isCurrent
                    ? "\(profile.label), current"
                    : "Switch to \(profile.label)"
            )
            .accessibilityIdentifier(
                "profile-center.select.\(profile.id)"
            )

             
             
             
             
            detailButton
                .padding(.trailing, presentsDetailModally ? 0 : ClashTheme.Spacing.standard)
        }
         
         
         
         
         
         
         
        .accessibilityElement(children: .contain)
    }

     
    @ViewBuilder
    private var statusSlot: some View {
        Group {
            if isSelecting || profile.isBusy {
                ProgressView()
                    .controlSize(.small)
            } else if profile.isCurrent {
                icon(.checkmark)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityLabel(Text(clash: .copy("Current")))
                    .accessibilityIdentifier(
                        "profile-center.current.\(profile.id)"
                    )
            } else {
                Color.clear
            }
        }
        .frame(width: 24, height: 24)
    }

    private var detailButton: some View {
        rowLink {
            icon(presentsDetailModally ? .infoCircle : .chevronForward)
                .font(presentsDetailModally ? .title3 : .caption.weight(.semibold))
                .foregroundStyle(presentsDetailModally ? AnyShapeStyle(Color.blue) : AnyShapeStyle(.tertiary))
                .frame(
                    width: ClashTheme.Control.minimumHitTarget,
                    height: ClashTheme.Control.minimumHitTarget,
                    alignment: presentsDetailModally ? .center : .trailing
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(profile.label) details")
        .accessibilityIdentifier(
            "profile-center.detail.\(profile.id)"
        )
    }

     
     
     
    private var accessibilityProfileRow: some View {
        VStack(spacing: 0) {
            Button(action: select) {
                VStack(
                    alignment: .leading,
                    spacing: ClashTheme.Spacing.row
                ) {
                    HStack(
                        alignment: .firstTextBaseline,
                        spacing: ClashTheme.Spacing.row
                    ) {
                        statusSlot
                        Text(profile.label)
                            .font(
                                .body.weight(
                                    profile.isCurrent
                                        ? .semibold
                                        : .regular
                                )
                            )
                            .foregroundStyle(.primary)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                        Spacer(
                            minLength: ClashTheme.Spacing.compact
                        )
                    }

                    if let subscription = profile.subscription {
                        ClashSubscriptionUsageView(
                            subscription: subscription,
                            style: .row
                        )
                    }

                    if profile.source == .remote {
                        Text(clash: profile.sourceSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ClashTheme.Spacing.standard)
                .padding(
            .vertical,
            ClashMacSettingsMetrics.rowVerticalInset(
                touch: ClashTheme.Spacing.row
            )
        )
                .contentShape(Rectangle())
            }
            .disabled(isBlocked)
            .buttonStyle(.plain)
            .disabled(isSelecting || profile.isBusy)
            .accessibilityLabel(
                profile.isCurrent
                    ? "\(profile.label), current"
                    : "Switch to \(profile.label)"
            )
            .accessibilityIdentifier(
                "profile-center.select.\(profile.id)"
            )

            ClashRowDivider(leadingInset: ClashTheme.Spacing.standard)

            rowLink {
                HStack(spacing: ClashTheme.Spacing.row) {
                    Text("Details")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    icon(presentsDetailModally ? .infoCircle : .chevronForward)
                        .font(presentsDetailModally ? .title3 : .caption.weight(.semibold))
                        .foregroundStyle(presentsDetailModally ? AnyShapeStyle(Color.blue) : AnyShapeStyle(.tertiary))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, ClashTheme.Spacing.standard)
                .padding(
            .vertical,
            ClashMacSettingsMetrics.rowVerticalInset(
                touch: ClashTheme.Spacing.row
            )
        )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(profile.label) details")
            .accessibilityIdentifier(
                "profile-center.detail.\(profile.id)"
            )
        }
    }
}

private struct ClashProfileDetailView<
    Icon: View,
    CapabilityContent: View
>: View {
    let profileID: Profile.ID
    let snapshot: AppleClientSnapshot
    let actions: AppleClientActions
    let presentationClass: ClashPresentationClass
    let palette: ClashProductPalette
    let pagePresentation: (AnyView) -> AnyView
     
     
    var configurationPage: ((Profile.ID) -> ClashConfigurationPageParts)? = nil
     
     
    let capabilityInterceptor:
        ((ClashProfilesCapabilityDestination) -> Bool)?
    let icon: (ClashSymbol) -> Icon
    let capabilityContent:
        (ClashProfilesCapabilityDestination) -> CapabilityContent

     
    private func present(_ capability: ClashProfilesCapabilityDestination) {
        if capabilityInterceptor?(capability) == true { return }
        activeCapability = capability
    }

     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
     
     
     
     
     
     
    @State private var sourceUpdatesSwitch = ClashStoredSwitch<ClashProfileSnapshot.ID>()
     
     
    @State private var confirmsFollowingLink = false
     
    @State private var asksForFollowedLink = false
     
     
     
     
     
    @State private var originalConfigurationSwitch = ClashStoredSwitch<ClashProfileSnapshot.ID>()
    @State private var isDuplicating = false
     
     
    @State private var duplicated: Profile.ID?
    @Environment(\.clashFeedback) private var feedback
     
     
     
     
    @State private var showsActionFailure: ActionFailure?

    struct ActionFailure: Equatable {
        enum Action { case duplicate, delete }
        let action: Action
        let message: ClashDisplayText
    }

    @ViewBuilder
    private func actionFailureLine(for action: ActionFailure.Action) -> some View {
        if let showsActionFailure, showsActionFailure.action == action {
            failureLine(showsActionFailure.message)
        }
    }

     
    private func failureLine(_ message: ClashDisplayText) -> some View {
            Text(clash: message)
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ClashTheme.Spacing.standard)
                .padding(.bottom, ClashTheme.Spacing.tight)
                .accessibilityIdentifier("profile-detail.action-failure")
    }
     
     
     
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @State private var activeCapability:
        ClashProfilesCapabilityDestination?
    @State private var showsDeleteConfirmation = false
    @State private var showsPlaintextExportConfirmation = false
     
    @State private var isPastFirstFrame = false
    @State private var draftName = ""
    @FocusState private var editingName: Bool

    private var profile: ClashProfileSnapshot? {
        snapshot.profiles.profile(id: profileID)
    }

    var body: some View {
        Group {
            if let profile {
                detailPage(profile)
            } else {
                ClashEmptyState(
                    title: "Profile Unavailable",
                    message:
                        "Return to Profiles and choose another item."
                ) {
                    icon(.exclamationmarkTriangle)
                }
            }
        }
        .clashCapturesDismiss(dismiss)
        .clashProductModal(
            item: $activeCapability,
            role: .page,
            immersive: { $0.presentsImmersively }
        ) { destination in
            capabilityContent(destination)
                .clashModalPresentation(.page)
        }
        .onAppear {
            if draftName.isEmpty {
                draftName = profile?.label ?? ""
            }
        }
        .onChange(of: profile?.label) { label in
            if !editingName, let label {
                draftName = label
            }
        }
    }

    private func detailPage(
        _ profile: ClashProfileSnapshot
    ) -> some View {
        ClashPerf.count("profile.detail.body")
        return pageContent(profile)
        .onAppear {
            isPastFirstFrame = false
            DispatchQueue.main.async { isPastFirstFrame = true }
        }
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        .clashRegistersDeparture(
            isDirty: hasUnsavedName(profile),
            save: { completion in
                commitRename(profile)
                completion(true)
            },
            discard: { draftName = profile.label }
        )
        .clashPageTitle(.verbatim(profile.label), watchAs: "profile-detail")
        .clashToolbarUnlessInPanel {
             
             
             
             
            ToolbarItem(placement: .confirmationAction) {
                if hasUnsavedName(profile) {
                    Button("Save") {
                        commitRename(profile)
                        editingName = false
                    }
                    .accessibilityIdentifier("profile-detail.save")
                }
            }
        }
        .alert(Text(clash: .copy("Go Back to the Link’s Content?")), isPresented: $confirmsFollowingLink) {
            Button(role: .destructive) { saveSourceUpdates(profile, enabled: true) } label: {
                Text(clash: .copy("Go Back"))
            }
            .accessibilityIdentifier("profile-detail.configuration-source-updates.confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(clash: .copy("What was changed in this configuration here will be replaced."))
        }
        .confirmationDialog(Text(clash: .copy("Go Back to the Link’s Content?")), isPresented: $asksForFollowedLink,
                            titleVisibility: .visible) {
            ForEach(profile.linksToPick, id: \.id) { link in
                Button(role: .destructive) { followLink(profile, link: link.id) } label: {
                    Text(clash: .format("Follow “%@”", [link.label]))
                }
                .accessibilityIdentifier("profile-detail.configuration-source-updates.link")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(clash: .copy("What was changed in this configuration here will be replaced."))
        }
        .clashDeleteConfirmation(profile.label, isPresented: $showsDeleteConfirmation,
            actionTitle: .copy("Delete Profile"),
            message: .copy("This profile will be deleted. Sources and rule schemes in the library will remain."),
            identifier: "profile-detail.delete.confirm") { delete(profile) }
        .alert(Text(clash: .copy("Configuration Duplicated")),
               isPresented: Binding(get: { duplicated != nil }, set: { if !$0 { duplicated = nil } })) {
            Button("OK") {
                duplicated = nil
                leave()
            }
            .accessibilityIdentifier("profile-detail.duplicated.ok")
        } message: {
            Text(clash: ClashProfilesDuplicateNaming.message(label: duplicated.flatMap { id in snapshot.profiles.profiles.first { $0.id == id }?.label }))
        }
        .alert(
            "Export Profile Text Only?",
            isPresented: $showsPlaintextExportConfirmation
        ) {
            Button("Export Text") {
                send(.export(id: profile.id))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Imported certificate files are not included. Everything else — your credentials included — is exported as plaintext."
            )
        }
    }

     
     
    @ViewBuilder
    private func pageContent(_ profile: ClashProfileSnapshot) -> some View {
        if let parts = embeddedConfigurationPage(profile) {
            parts.host(AnyView(nativeConfigurationPage(profile, sections: parts.sections, actions: parts.actions)))
        } else {
    ClashProductRootPage(
                palette: palette,
                accessibilityIdentifier: "profile-detail.root"
            ) {
                identitySection(profile)
                 
                 
                 
                if isPastFirstFrame {
                    if (profile.isComposed == true || profile.canUseOriginalConfiguration
                        || (profile.isComposed == false && profile.canEditSource)) && compositionHasRows(profile) {
                        compositionSection(profile)
                    }
                    if profile.source == .remote,
                       profile.subscription != nil
                        || profile.canSync
                        || profile.canConfigureSubscription
                        || profile.canCopySubscriptionLink
                    {
                        subscriptionSection(profile)
                    }
                    if !profile.heldBackUpdates.isEmpty {
                        heldBackSection(profile)
                    }
                     
                     
                     
                     
                    if profile.canOpenConfigurationPage != true || profile.canDuplicate || profile.canExport {
                        manageSection(profile)
                    }
                    if profile.canOpenConfigurationPage != true { networkSection(profile) }
                    if profile.canOpenRuntimePreview
                        || profile.canRestoreLastKnownGood
                    {
                        runtimeSection(profile)
                    }
                    deleteSection(profile)
                }
                statusSection
            }
        }
    }

     
     
     
     
     
     
    private func nativeConfigurationPage(_ profile: ClashProfileSnapshot, sections: AnyView, actions: AnyView?) -> some View {
        ClashConfigurationLibraryList(palette: palette, accessibilityIdentifier: "profile-detail.root") {
             
             
            ClashConfigurationPageSearchSwitch(sections: sections) {
                nativeManagementSection(profile)
                if !profile.heldBackUpdates.isEmpty { nativeHeldBackSection(profile) }
            } after: {
                if actions != nil || profile.canDuplicate || profile.canExport { nativeManageSection(profile, actions: actions) }
                if profile.canOpenRuntimePreview || profile.canRestoreLastKnownGood { nativeRuntimeSection(profile) }
                nativeDeleteSection(profile)
                if !snapshot.profiles.statusMessage.rawValue.isEmpty { nativeStatusSection }
            }
        }
    }

     
     
    @ViewBuilder
    private func nativeValueRow<Value: View>(_ title: ClashDisplayText, @ViewBuilder value: () -> Value) -> some View {
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            LabeledContent { value() } label: { Text(clash: title) }
        } else {
            nativeValueRowBefore16(title, value: value())
        }
    }

     
     
     
    private func nativeValueRowBefore16<Value: View>(_ title: ClashDisplayText, value: Value) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.row) {
            Text(clash: title)
            Spacer(minLength: ClashTheme.Spacing.row)
            value.foregroundStyle(.secondary)
        }
    }

     
    @ViewBuilder
    private func nativeFailureRow(for action: ActionFailure.Action) -> some View {
        if let showsActionFailure, showsActionFailure.action == action {
            Text(clash: showsActionFailure.message)
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityIdentifier("profile-detail.action-failure")
        }
    }

     
     
     
     
    private func nativeManagementSection(_ profile: ClashProfileSnapshot) -> some View {
        Section {
            nativeValueRow("Name") {
                if profile.canRename {
                    nameEditor.multilineTextAlignment(.trailing)
                } else {
                    Text(verbatim: profile.label)
                }
            }
            .onChange(of: editingName) { focused in
                if profile.canRename, !focused { commitRename(profile) }
            }
             
             
             
             
             
             
            if profile.source == .remote {
                nativeSubscriptionRows(profile)
            } else {
                nativeSourceUpdatesRow(profile)
            }
        } header: {
             
             
             
             
            HStack {
                Text("Configuration")
                Spacer()
                if profile.isCurrent {
                    Label { Text("In Use") } icon: { icon(.checkmarkCircleFill) }
                        .foregroundStyle(.tint)
                        .accessibilityIdentifier("profile-detail.active")
                }
            }
        }
    }

     
     
     
     
     
     
    @ViewBuilder
    private func nativeSourceUpdatesRow(_ profile: ClashProfileSnapshot) -> some View {
        if let state = profile.sourceUpdatesState {
            if ClashProfileSnapshot.offersSourceUpdatesSwitch(state, canPickLink: !profile.linksToPick.isEmpty) {
                sourceUpdatesToggle(profile, state: state)
            }
            sourceUpdatesNote(state, canPickLink: !profile.linksToPick.isEmpty)
             
            ClashStoredFailure(sourceUpdatesSwitch, key: profile.id) { failure in
                Text(clash: .copy(failure))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("profile-detail.action-failure")
            }
        }
    }

    @ViewBuilder
    private func sourceUpdatesNote(_ state: ConfigurationUpdateFollowing, canPickLink: Bool) -> some View {
        if let note = ClashProfileSnapshot.sourceUpdatesNote(state, canPickLink: canPickLink) {
            Text(clash: note)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("profile-detail.configuration-source-updates.note")
        }
    }

     
     
     
     
     
    private func sourceUpdatesToggle(_ profile: ClashProfileSnapshot, state: ConfigurationUpdateFollowing) -> some View {
        ClashStoredToggle(sourceUpdatesSwitch, key: profile.id, stored: state == .following,
                          identifier: "profile-detail.configuration-source-updates", set: { value in
             
             
             
            if value, !sourceUpdatesSwitch.isPending(profile.id) {
                if state == .copyWithoutOrigin {
                    asksForFollowedLink = true
                    return
                }
                if ClashProfileSnapshot.turningOnReplacesChanges(state) {
                    confirmsFollowingLink = true
                    return
                }
            }
            saveSourceUpdates(profile, enabled: value)
        }) {
            Text("Follow Link Updates")
        }
         
         
        .disabled(profile.isBusy)
        .onChange(of: state) { sourceUpdatesSwitch.read(profile.id, stored: $0 == .following) }
    }

    private func saveSourceUpdates(_ profile: ClashProfileSnapshot, enabled value: Bool) {
        sourceUpdatesSwitch.press(profile.id, value, readBack: .whenRead) { [actions, snapshot] value in
            _ = try await actions.perform(.profiles(.setConfigurationSourceUpdates(id: profile.id, enabled: value)),
                                          allowedBy: snapshot)
        }
    }

     
     
    private func followLink(_ profile: ClashProfileSnapshot, link: String) {
        sourceUpdatesSwitch.press(profile.id, true, readBack: .whenRead) { [actions, snapshot] _ in
            _ = try await actions.perform(.profiles(.followConfigurationLink(id: profile.id, linkID: link)),
                                          allowedBy: snapshot)
        }
    }

     
     
     
    @ViewBuilder
    private func nativeSubscriptionRows(_ profile: ClashProfileSnapshot) -> some View {
        Group {
            if let subscription = profile.subscription {
                 
                 
                 
                 
                 
                 
                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                    if let fraction = subscription.usageFraction {
                        ProgressView(value: fraction) {
                            if let quota = ClashSubscriptionUsageView.quotaText(subscription) { quota }
                        }
                    }
                    Group {
                        if let used = ClashSubscriptionUsageView.usedText(subscription) {
                            used + Text(verbatim: " · ") + ClashSubscriptionUsageView.metaText(subscription)
                        } else {
                            ClashSubscriptionUsageView.metaText(subscription)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("profile-detail.subscription-status")
            }
            nativeSourceUpdatesRow(profile)
            if profile.canSync {
                Button { send(.sync(id: profile.id)) } label: {
                    HStack {
                        Label { Text("Sync Now") } icon: { icon(.arrowTriangle2Circlepath) }
                        Spacer()
                        if profile.isBusy {
                            ProgressView()
                        } else if let synced = profile.lastUpdatedAt {
                             
                             
                            Text(verbatim: synced.formatted(.relative(presentation: .named)))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .disabled(snapshot.profiles.profiles.contains { $0.isBusy })
                .accessibilityIdentifier("profile-detail.sync")
            }
            if profile.canConfigureSubscription {
                Button { activeCapability = .subscriptionSettings(profile.id) } label: {
                    Label { Text("Profile URL Settings") } icon: { icon(.link) }
                }
                .accessibilityIdentifier("profile-detail.subscription")
            }
        }
    }

    private func nativeHeldBackSection(_ profile: ClashProfileSnapshot) -> some View {
        Section {
            ForEach(profile.heldBackUpdates) { item in
                HStack(alignment: .top, spacing: ClashTheme.Spacing.row) {
                    VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                        Text(verbatim: item.keyPath).font(.subheadline.monospaced())
                        Text(clash: heldBackLine(item))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: ClashTheme.Spacing.compact)
                    Button {
                        send(.adoptHeldBackUpdate(id: profile.id, keyPath: item.keyPath))
                    } label: {
                        Text(clash: item.change == .removed ? .copy("Follow Removal") : .copy("Use New Value"))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("profile-detail.held-back.adopt.\(item.keyPath)")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("profile-detail.held-back.item.\(item.keyPath)")
            }
            Button { send(.dismissHeldBackUpdates(id: profile.id)) } label: {
                Text(clash: .copy("Keep My Settings"))
            }
            .accessibilityIdentifier("profile-detail.held-back.dismiss")
        } header: {
            Text("Held Back by Your Settings")
        } footer: {
            Text(clash: .format(
                "The last update changed %@ setting(s) that your app-wide settings override. Each is shown with the new value; adopt it or keep yours.",
                [String(profile.heldBackUpdates.count)]
            ))
        }
    }

     
     
    private func nativeManageSection(_ profile: ClashProfileSnapshot, actions: AnyView?) -> some View {
        Section {
            if let actions { actions }
            if profile.canDuplicate {
                 
                 
                Button { duplicate(profile) } label: {
                    HStack {
                        Label { Text("Duplicate Profile") } icon: { icon(.docOnDoc) }
                        if isDuplicating {
                            Spacer()
                            ProgressView().accessibilityIdentifier("profile-detail.duplicating")
                        }
                    }
                }
                .disabled(isDuplicating)
                .accessibilityIdentifier("profile-detail.duplicate")
                nativeFailureRow(for: .duplicate)
            }
            if profile.canExport {
                Button {
                    if profile.requiresPlaintextExportConfirmation {
                        showsPlaintextExportConfirmation = true
                    } else {
                        send(.export(id: profile.id))
                    }
                } label: {
                    Label { Text("Export") } icon: { icon(.squareAndArrowUp) }
                }
                .accessibilityIdentifier("profile-detail.export")
            }
        } footer: {
            if actions != nil { Text(clash: .copy("Changes take effect as you make them. Compiling only checks.")) }
        }
    }

    private func nativeRuntimeSection(_ profile: ClashProfileSnapshot) -> some View {
        Section {
            if profile.canOpenRuntimePreview {
                Button {
                    ClashPageProbe.markNavigation()
                    activeCapability = .runtimePreview(profile.id)
                } label: {
                    Label { Text("View Runtime Configuration") } icon: { icon(.eye) }
                }
                .accessibilityIdentifier("profile-detail.preview")
            }
            if profile.canRestoreLastKnownGood {
                Button { send(.restoreLastKnownGood(id: profile.id)) } label: {
                    Label { Text("Restore Last Known Good") } icon: { icon(.arrowTriangle2Circlepath) }
                }
                .accessibilityIdentifier("profile-detail.restore-lkg")
            }
        } footer: {
            if profile.canOpenRuntimePreview { Text(clash: profile.runtimeSummary) }
        }
    }

    private func nativeDeleteSection(_ profile: ClashProfileSnapshot) -> some View {
        Section {
             
             
             
            Button(role: .destructive) { showsDeleteConfirmation = true } label: {
                Label { Text("Delete Profile") } icon: { icon(.trash) }
                    .foregroundStyle(Color.red.opacity(profile.canDelete ? 1 : 0.4))
            }
            .disabled(!profile.canDelete)
            .accessibilityIdentifier("profile-detail.delete")
            nativeFailureRow(for: .delete)
        } footer: {
            Text(clash: profile.deleteSubtitle)
        }
    }

    private var nativeStatusSection: some View {
        Section {
            Text(clash: snapshot.profiles.statusMessage)
                .font(.subheadline)
                .foregroundStyle(snapshot.profiles.failure == nil ? Color.secondary : Color.red)
                .accessibilityIdentifier("profile-detail.status")
        } header: {
            Text("Last Action")
        }
    }

     
     
    private func embeddedConfigurationPage(_ profile: ClashProfileSnapshot) -> ClashConfigurationPageParts? {
        guard drawsConfigurationPage(profile) else { return nil }
        return configurationPage?(profile.id)
    }

    private func drawsConfigurationPage(_ profile: ClashProfileSnapshot) -> Bool {
        profile.canOpenConfigurationPage == true && configurationPage != nil
    }

     
     
     
    private func compositionHasRows(_ profile: ClashProfileSnapshot) -> Bool {
        guard drawsConfigurationPage(profile) else { return true }
        let usesOriginal = profile.isComposed == false && profile.canUseOriginalConfiguration
        return (!usesOriginal && profile.isComposed == true) || profile.sourceUpdatesState != nil
    }

    private func identitySection(
        _ profile: ClashProfileSnapshot
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: ClashTheme.Spacing.compact
        ) {
            identityHeader(profile)
            .padding(.horizontal, ClashTheme.Spacing.standard)

            ClashCardSurface(
                fill: palette.card,
                separator: palette.separator
            ) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        accessibilityIdentityEditor
                    } else {
                        HStack(
                            alignment: .firstTextBaseline,
                            spacing: ClashTheme.Spacing.standard
                        ) {
                            Text("Name")
                            Spacer(minLength: ClashTheme.Spacing.compact)
                            if profile.canRename {
                                nameEditor
                                    .multilineTextAlignment(.trailing)
                            } else {
                                Text(profile.label)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, ClashTheme.Spacing.standard)
                .padding(
            .vertical,
            ClashMacSettingsMetrics.rowVerticalInset(
                touch: ClashTheme.Spacing.row
            )
        )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if profile.source == .remote {
                Text(clash: profile.sourceSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(
                        dynamicTypeSize.isAccessibilitySize ? 2 : 1
                    )
                    .truncationMode(.middle)
                    .fixedSize(
                        horizontal: false,
                        vertical: dynamicTypeSize.isAccessibilitySize
                    )
                    .padding(.leading, ClashTheme.Spacing.standard)
            }
        }
        .onChange(of: editingName) { focused in
            if profile.canRename, !focused {
                commitRename(profile)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile-detail.identity")
    }

    @ViewBuilder
    private func identityHeader(
        _ profile: ClashProfileSnapshot
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(
                alignment: .leading,
                spacing: ClashTheme.Spacing.row
            ) {
                identityTitle
                if profile.isCurrent {
                    activeProfileLabel
                }
            }
        } else {
            HStack {
                identityTitle
                Spacer()
                if profile.isCurrent {
                    activeProfileLabel
                }
            }
        }
    }

    private var identityTitle: some View {
        Text("IDENTITY")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var activeProfileLabel: some View {
        Label {
            Text("In Use")
        } icon: {
            icon(.checkmarkCircleFill)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tint)
        .accessibilityIdentifier("profile-detail.active")
    }

    private var accessibilityIdentityEditor: some View {
        VStack(
            alignment: .leading,
            spacing: ClashTheme.Spacing.compact
        ) {
            Text("Name")
                .font(.caption)
                .foregroundStyle(.secondary)
            if profile?.canRename == true {
                nameEditor
                    .multilineTextAlignment(.leading)
            } else {
                Text(profile?.label ?? "")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var nameEditor: some View {
         
         
         
        if !isPastFirstFrame {
            Text(verbatim: draftName)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
        } else {
            nameField
        }
    }

    private var nameField: some View {
         
         
         
         
         
         
         
        TextField("Name", text: $draftName)
            .clashLabelsHiddenInSettingsIdiom()
            .submitLabel(.done)
            .focused($editingName)
            .onSubmit { editingName = false }
            .accessibilityIdentifier("profile-detail.name")
    }

     
     
     
     
    private func heldBackSection(
        _ profile: ClashProfileSnapshot
    ) -> some View {
        ClashProfileGroup(
            title: "Held Back by Your Settings",
            palette: palette,
            presentationClass: presentationClass
        ) {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.row) {
                Text(clash: .format(
                    "The last update changed %@ setting(s) that your app-wide settings override. Each is shown with the new value; adopt it or keep yours.",
                    [String(profile.heldBackUpdates.count)]
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                ForEach(profile.heldBackUpdates) { item in
                    HStack(alignment: .top, spacing: ClashTheme.Spacing.row) {
                        VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                            Text(verbatim: item.keyPath)
                                .font(.subheadline.monospaced())
                            Text(clash: heldBackLine(item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: ClashTheme.Spacing.compact)
                        Button {
                            send(.adoptHeldBackUpdate(id: profile.id, keyPath: item.keyPath))
                        } label: {
                            Text(clash: item.change == .removed ? .copy("Follow Removal") : .copy("Use New Value"))
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("profile-detail.held-back.adopt.\(item.keyPath)")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("profile-detail.held-back.item.\(item.keyPath)")
                }
                Button {
                    send(.dismissHeldBackUpdates(id: profile.id))
                } label: {
                    Text(clash: .copy("Keep My Settings"))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("profile-detail.held-back.dismiss")
            }
            .padding(.vertical, ClashTheme.Spacing.standard)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("profile-detail.held-back")
        }
    }

    private func heldBackLine(_ item: ClashProfileHeldBackUpdate) -> ClashDisplayText {
        switch item.change {
        case .removed:
            return .format("Removed by the profile URL · yours: %@", [item.appValue])
        case .added, .changed:
            return .format("Profile URL now: %@ · yours: %@", [item.newValue ?? "", item.appValue])
        }
    }

    private func subscriptionSection(
        _ profile: ClashProfileSnapshot
    ) -> some View {
        ClashProfileGroup(
            title: "Profile URL",
            palette: palette,
            presentationClass: presentationClass
        ) {
            if let subscription = profile.subscription {
                VStack(
                    alignment: .leading,
                    spacing: ClashTheme.Spacing.row
                ) {
                    ClashSubscriptionUsageView(
                        subscription: subscription
                    )
                    Text(lastSyncValue(profile))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.vertical, ClashTheme.Spacing.standard)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(
                    "profile-detail.subscription-status"
                )

                if profile.canSync
                    || profile.canConfigureSubscription
                    || profile.canCopySubscriptionLink
                {
                    ClashRowDivider()
                }
            }

            if profile.canSync {
                Button {
                    send(.sync(id: profile.id))
                } label: {
                    ClashProfileActionRow(
                        title: "Sync Now",
                        symbol: .arrowTriangle2Circlepath,
                        tint: .primary,
                        showsDisclosure: false,
                        isBusy: profile.isBusy,
                        icon: icon
                    )
                }
                .buttonStyle(.plain)
                .disabled(
                    snapshot.profiles.profiles.contains {
                        $0.isBusy
                    }
                )
                .accessibilityIdentifier("profile-detail.sync")
            }

            if profile.canSync
                && (profile.canConfigureSubscription
                    || profile.canCopySubscriptionLink)
            {
                ClashRowDivider()
            }

            if profile.canConfigureSubscription {
                Button {
                    activeCapability =
                        .subscriptionSettings(profile.id)
                } label: {
                    ClashProfileActionRow(
                        title: "Profile URL Settings",
                        symbol: .link,
                        tint: .primary,
                        icon: icon
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(
                    "profile-detail.subscription"
                )
            }

            if profile.canConfigureSubscription
                && profile.canCopySubscriptionLink
            {
                ClashRowDivider()
            }

            if profile.canCopySubscriptionLink {
                Button {
                    send(.copySubscriptionLink(id: profile.id))
                } label: {
                    ClashProfileActionRow(
                        title: "Copy Profile URL",
                        symbol: .docOnDoc,
                        tint: .primary,
                        showsDisclosure: false,
                        icon: icon
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(
                    "profile-detail.copy-link"
                )
            }
        }
    }

    private func compositionSection(_ profile: ClashProfileSnapshot) -> some View {
         
         
         
         
         
         
         
         
         
        let usesOriginal = profile.isComposed == false && profile.canUseOriginalConfiguration
         
         
        let offersSwitch = profile.canUseOriginalConfiguration && !drawsConfigurationPage(profile)
        return ClashProfileGroup(title: "Configuration", palette: palette, presentationClass: presentationClass) {
            if offersSwitch {
                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                     
                     
                     
                    ClashStoredToggle(originalConfigurationSwitch, key: profile.id, stored: usesOriginal,
                                      identifier: "profile-detail.uses-original-configuration", readBack: .whenRead,
                                      write: { [actions, snapshot] value in
                        _ = try await actions.perform(.profiles(.setUsesOriginalConfiguration(id: profile.id, enabled: value)),
                                                      allowedBy: snapshot)
                    }) {
                         
                         
                         
                         
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use Original Configuration")
                            if profile.isTakenOverByScript {
                                 
                                 
                                 
                                Text(clash: ClashProfileSnapshot.takenOverByScript).font(.footnote).foregroundStyle(.tertiary)
                            } else if let name = profile.configurationSourceNames?.first, !name.isEmpty {
                                Text(verbatim: name).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(profile.isBusy)
                    .onChange(of: usesOriginal) { originalConfigurationSwitch.read(profile.id, stored: $0) }
                     
                    ClashStoredFailure(originalConfigurationSwitch, key: profile.id) { failure in
                        failureLine(.copy(failure))
                    }
                }
                .padding(.vertical, ClashMacSettingsMetrics.rowVerticalInset(touch: ClashTheme.Spacing.row))
                .frame(maxWidth: .infinity, alignment: .leading)
                if !usesOriginal { ClashRowDivider() }
            }
            if !usesOriginal {
            if profile.isComposed == true {
            Button { present(.configurationSources(profile.id)) } label: {
                ClashProfileActionRow(title: "Node Sources",
                    subtitle: ClashProfileSourcesSummary.value(profile.configurationSourceNames),
                    symbol: .serverRack, tint: .primary, icon: icon)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile-detail.configuration-sources")
            if profile.canOpenConfigurationPage != true { ClashRowDivider() }
            }
             
             
            if profile.canOpenConfigurationPage != true {
             
             
             
             
            let takenOver = profile.isTakenOverByScript
            Button { present(.configurationRules(profile.id)) } label: {
                ClashProfileActionRow(title: "Rule Scheme",
                    subtitle: takenOver ? ClashProfileSnapshot.takenOverByScript
                        : profile.configurationRuleName.map { .verbatim($0) } ?? .copy("Choose a rule scheme"),
                    symbol: .ruleDomain, tint: takenOver ? .secondary : .primary,
                    titleColor: takenOver ? .secondary : .primary, showsDisclosure: !takenOver, icon: icon)
            }
            .buttonStyle(.plain)
            .disabled(takenOver)
            .accessibilityIdentifier("profile-detail.configuration-rules")
            }
            }
            if let state = profile.sourceUpdatesState {
                if offersSwitch || !usesOriginal { ClashRowDivider() }
                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                if ClashProfileSnapshot.offersSourceUpdatesSwitch(state, canPickLink: !profile.linksToPick.isEmpty) {
                    sourceUpdatesToggle(profile, state: state)
                }
                sourceUpdatesNote(state, canPickLink: !profile.linksToPick.isEmpty)
                 
                ClashStoredFailure(sourceUpdatesSwitch, key: profile.id) { failure in
                    failureLine(.copy(failure))
                }
                }
                .padding(.vertical, ClashMacSettingsMetrics.rowVerticalInset(touch: ClashTheme.Spacing.row))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

     
     
     
     
    private func networkSection(
        _ profile: ClashProfileSnapshot
    ) -> some View {
        ClashProfileGroup(
            title: "Network",
            palette: palette,
            presentationClass: presentationClass
        ) {
            Button { activeCapability = .network(profile.id) } label: {
                ClashProfileActionRow(title: "Sniffer & NTP",
                    symbol: .network, tint: .primary, icon: icon)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.detail.network")
            ClashRowDivider()
            Button { activeCapability = .trust(profile.id) } label: {
                ClashProfileActionRow(title: "Compatibility & Trust",
                    symbol: .lockShield, tint: .primary, icon: icon)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.detail.trust")
        }
    }

    private func manageSection(
        _ profile: ClashProfileSnapshot
    ) -> some View {
        ClashProfileGroup(
            title: "Manage",
            palette: palette,
            presentationClass: presentationClass
        ) {
             
             
             
            if profile.canOpenConfigurationPage != true {
            if profile.canEditSource {
                Button { present(.sourceEditor(profile.id)) } label: {
                    ClashProfileActionRow(title: "Edit Source",
                        symbol: .curlybraces, tint: .primary, icon: icon)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile-detail.edit-source")
                ClashRowDivider()
            }
             
             
             
             
             
            Button { activeCapability = .rules(profile.id) } label: {
                ClashProfileActionRow(title: "Custom Rules",
                    value: ClashProfileSnapshot.customRulesValue(count: profile.customRulesCount, locale: locale),
                    symbol: .ruleDomain, tint: .primary, icon: icon)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile-detail.custom-rules")
            ClashRowDivider()
            Button { activeCapability = .override(profile.id) } label: {
                ClashProfileActionRow(title: "Overrides and Scripts",
                    value: profile.overrideScriptName.map { .verbatim($0) },
                    symbol: .sliderHorizontal3, tint: .primary, icon: icon)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.detail.override")
            if profile.canDuplicate || profile.canExport { ClashRowDivider() }
            }

            if profile.canDuplicate {
                 
                 
                 
                Button {
                    duplicate(profile)
                } label: {
                    ClashProfileActionRow(
                        title: "Duplicate Profile",
                        subtitle: isDuplicating ? "Creating the copy…" : nil,
                        symbol: .docOnDoc,
                        tint: .primary,
                        showsDisclosure: false,
                        icon: icon
                    )
                }
                .overlay(alignment: .trailing) {
                    if isDuplicating {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, ClashTheme.Spacing.standard)
                            .accessibilityIdentifier("profile-detail.duplicating")
                    }
                }
                .disabled(isDuplicating)
                .buttonStyle(.plain)
                .accessibilityIdentifier(
                    "profile-detail.duplicate"
                )
            }

            actionFailureLine(for: .duplicate)

            if profile.canDuplicate && profile.canExport {
                ClashRowDivider()
            }

            if profile.canExport {
                Button {
                    if profile.requiresPlaintextExportConfirmation {
                        showsPlaintextExportConfirmation = true
                    } else {
                        send(.export(id: profile.id))
                    }
                } label: {
                    ClashProfileActionRow(
                        title: "Export",
                        symbol: .squareAndArrowUp,
                        tint: .primary,
                        showsDisclosure: false,
                        icon: icon
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile-detail.export")
            }
        }
    }

    private func runtimeSection(
        _ profile: ClashProfileSnapshot
    ) -> some View {
        ClashCardSurface(
            fill: palette.card,
            separator: palette.separator
        ) {
            VStack(spacing: 0) {
                if profile.canOpenRuntimePreview {
                    Button {
                        ClashPageProbe.markNavigation()
                        activeCapability =
                            .runtimePreview(profile.id)
                    } label: {
                        ClashProfileActionRow(
                            title: "View Runtime Configuration",
                            subtitle: profile.runtimeSummary,
                            symbol: .eye,
                            tint: .primary,
                            icon: icon
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        "profile-detail.preview"
                    )
                }

                if profile.canOpenRuntimePreview
                    && profile.canRestoreLastKnownGood
                {
                    ClashRowDivider()
                }

                if profile.canRestoreLastKnownGood {
                    Button {
                        send(
                            .restoreLastKnownGood(id: profile.id)
                        )
                    } label: {
                        ClashProfileActionRow(
                            title: "Restore Last Known Good",
                            subtitle:
                                "Reapply this profile's validated runtime",
                            symbol: .arrowTriangle2Circlepath,
                            tint: .primary,
                            showsDisclosure: false,
                            icon: icon
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        "profile-detail.restore-lkg"
                    )
                }
            }
            .padding(.horizontal, ClashTheme.Spacing.standard)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deleteSection(
        _ profile: ClashProfileSnapshot
    ) -> some View {
        ClashCardSurface(
            fill: palette.card,
            separator: palette.separator
        ) {
            Button(role: .destructive) {
                showsDeleteConfirmation = true
            } label: {
                ClashProfileActionRow(
                    title: "Delete Profile",
                    subtitle: profile.deleteSubtitle,
                    symbol: .trash,
                    tint: .red,
                    titleColor: .red,
                    showsDisclosure: false,
                    icon: icon
                )
            }
            .buttonStyle(.plain)
            .disabled(!profile.canDelete)
            .accessibilityIdentifier("profile-detail.delete")
            .padding(.horizontal, ClashTheme.Spacing.standard)
            actionFailureLine(for: .delete)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusSection: some View {
        if !snapshot.profiles.statusMessage.rawValue.isEmpty {
            ClashProfileGroup(
                title: "Last Action",
                palette: palette,
                presentationClass: presentationClass
            ) {
                Text(clash: snapshot.profiles.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(
                        snapshot.profiles.failure == nil
                            ? Color.secondary
                            : Color.red
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(
            .vertical,
            ClashMacSettingsMetrics.rowVerticalInset(
                touch: ClashTheme.Spacing.row
            )
        )
                    .accessibilityIdentifier(
                        "profile-detail.status"
                    )
            }
        }
    }

    private func lastSyncValue(
        _ profile: ClashProfileSnapshot
    ) -> String {
        let sync = profile.lastUpdatedAt.map {
            $0.formatted(.relative(presentation: .named))
        } ?? "never"
        var value = "Last sync \(sync)"
        if profile.autoUpdate {
            value +=
                " · every \(profile.updateIntervalHours) h automatically"
        }
        return value
    }

     
    private func hasUnsavedName(_ profile: ClashProfileSnapshot) -> Bool {
        guard profile.canRename else { return false }
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != profile.label
    }

    private func commitRename(
        _ profile: ClashProfileSnapshot
    ) {
        let trimmed = draftName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            draftName = profile.label
            return
        }
        guard trimmed != profile.label else {
            return
        }
        send(.rename(id: profile.id, label: trimmed))
    }

    private func delete(_ profile: ClashProfileSnapshot) {
        showsActionFailure = nil
        Task { @MainActor in
            do {
                let result = try await actions.performForResult(
                    .profiles(.delete(id: profile.id)),
                    allowedBy: snapshot
                )
                switch result {
                case .profileDeleted(let id) where id == profile.id:
                    leave()
                case .profileActionRefused(let reason):
                    showsActionFailure = ActionFailure(action: .delete, message: reason)
                default:
                    showsActionFailure = ActionFailure(
                        action: .delete, message: .copy("The profile was not deleted."))
                }
            } catch is CancellationError {
                 
            } catch {
                showsActionFailure = ActionFailure(
                    action: .delete, message: .copy(error.localizedDescription))
            }
        }
    }

     
     
     
     
     
    private func duplicate(_ profile: ClashProfileSnapshot) {
        guard !isDuplicating else { return }
        isDuplicating = true
        showsActionFailure = nil
        Task { @MainActor in
            defer { isDuplicating = false }
            do {
                let result = try await actions.performForResult(
                    .profiles(.duplicate(id: profile.id)),
                    allowedBy: snapshot
                )
                switch result {
                case .profileCreated(let id):
                     
                     
                     
                     
                     
                     
                    if feedback != nil { leave() } else { duplicated = id }
                case .profileActionRefused(let reason):
                     
                     
                     
                    showsActionFailure = ActionFailure(action: .duplicate, message: reason)
                default:
                    showsActionFailure = ActionFailure(
                        action: .duplicate, message: .copy("The copy was not created."))
                }
            } catch is CancellationError {
                 
            } catch {
                 
                 
                showsActionFailure = ActionFailure(
                    action: .duplicate, message: .copy(error.localizedDescription))
            }
        }
    }

     
     
     
    private func leave() {
        dismiss.closeModalOrDismiss()
    }

    private func send(_ command: ClashProfilesCommand) {
        Task { @MainActor in
            try? await actions.perform(
                .profiles(command),
                allowedBy: snapshot
            )
        }
    }
}

private struct ClashProfileReorderView: View {
    let snapshot: AppleClientSnapshot
    let actions: AppleClientActions
    let palette: ClashProductPalette

    @Environment(\.dismiss) private var dismiss
    @State private var profiles: [ClashProfileSnapshot]

    init(
        profiles: [ClashProfileSnapshot],
        snapshot: AppleClientSnapshot,
        actions: AppleClientActions,
        palette: ClashProductPalette
    ) {
        self.snapshot = snapshot
        self.actions = actions
        self.palette = palette
        _profiles = State(initialValue: profiles)
    }

    var body: some View {
        ClashSingleColumnNavigationContainer {
            List {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                ForEach(
                    Array(profiles.enumerated()),
                    id: \.element.id
                ) { index, profile in
                    HStack(spacing: ClashTheme.Spacing.row) {
                        Text(profile.label)
                            .lineLimit(1)
                        Spacer(minLength: ClashTheme.Spacing.compact)
                        if profile.isCurrent {
                            Text("In Use")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(
                        minHeight: ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform
                    )
                    .contentShape(Rectangle())
                    .accessibilityHint("Drag to reorder")
                    .accessibilityAction(named: "Move Up") {
                        moveProfile(at: index, offset: -1)
                    }
                    .accessibilityAction(named: "Move Down") {
                        moveProfile(at: index, offset: 1)
                    }
                    .contextMenu {
                        Button("Move Up") {
                            moveProfile(at: index, offset: -1)
                        }
                        .disabled(index == profiles.startIndex)

                        Button("Move Down") {
                            moveProfile(at: index, offset: 1)
                        }
                        .disabled(
                            index == profiles.index(before: profiles.endIndex)
                        )
                    }
                    .accessibilityIdentifier(
                        "profile-reorder.row.\(profile.label)"
                    )
                }
                .onMove(perform: moveProfiles)
            }
             
             
             
            .clashExplicitReorderMode()
            .clashPageTitle("Reorder Profiles")
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) {
                    ClashSheetCloseButton {
                        dismiss()
                    }
                }
            }
            .clashProductModalRoot(title: "Reorder Profiles")
        }
        .accessibilityIdentifier("profile-reorder.screen")
    }

    private func moveProfile(at index: Int, offset: Int) {
        let destination = index + offset
        guard profiles.indices.contains(index),
              profiles.indices.contains(destination) else {
            return
        }
        profiles.swapAt(index, destination)
        sendOrder()
    }

    private func moveProfiles(
        from source: IndexSet,
        to destination: Int
    ) {
        profiles.move(fromOffsets: source, toOffset: destination)
        sendOrder()
    }

    private func sendOrder() {
        let ids = profiles.map(\.id)
        Task { @MainActor in
            try? await actions.perform(
                .profiles(.reorder(ids: ids)),
                allowedBy: snapshot
            )
        }
    }
}

private struct ClashProfileBatchReportView<Icon: View>: View {
    let report: ClashProfileBatchReportSnapshot
    let snapshot: AppleClientSnapshot
    let actions: AppleClientActions
    let icon: (ClashSymbol) -> Icon
     
     
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal

    var body: some View {
        ClashSingleColumnNavigationContainer {
            List {
                Section {
                    VStack(
                        alignment: .leading,
                        spacing: ClashTheme.Spacing.tight
                    ) {
                        HStack(spacing: 4) {
                            ForEach(
                                Array(report.summaryParts.enumerated()),
                                id: \.offset
                            ) { index, part in
                                if index > 0 {
                                    Text(verbatim: " · ")
                                }
                                Text(clash: part)
                            }
                        }
                            .font(.headline)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                        if report.isRunning {
                            ProgressView(
                                value: Double(report.items.count),
                                total: Double(
                                    max(report.expectedCount, 1)
                                )
                            )
                            Text(
                                "\(report.items.count) of \(report.expectedCount) complete"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, ClashTheme.Spacing.tight)
                }

                Section("Results") {
                    if report.items.isEmpty, !report.isRunning {
                        Text("Nothing needed an update.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(report.items) { item in
                        HStack(
                            alignment: .top,
                            spacing: ClashTheme.Spacing.row
                        ) {
                            icon(symbol(for: item.state))
                                .foregroundStyle(tint(for: item.state))
                                .frame(width: 24, height: 24)
                                .accessibilityHidden(true)
                            VStack(
                                alignment: .leading,
                                spacing: ClashTheme.Spacing.tight
                            ) {
                                Text(item.label)
                                    .font(.body.weight(.semibold))
                                    .fixedSize(
                                        horizontal: false,
                                        vertical: true
                                    )
                                Text(clash: .copy(item.message))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(
                                        horizontal: false,
                                        vertical: true
                                    )
                                if let code = item.diagnosticCode {
                                    Text(code)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(
                                minLength: ClashTheme.Spacing.compact
                            )
                            if item.state == .failed,
                               !report.isRunning {
                                Button("Try Again") {
                                    send(
                                        .retryBatchItem(id: item.id)
                                    )
                                }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier(
                                    "batch.retry.\(item.id)"
                                )
                            }
                        }
                        .padding(.vertical, ClashTheme.Spacing.tight)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(
                            "batch.result.\(item.id)"
                        )
                    }
                }
            }
            .clashPageTitle(.copy(report.title))
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) {
                    if report.isRunning {
                        Button("Cancel", role: .cancel) {
                            send(.cancelBatch)
                        }
                        .accessibilityIdentifier("batch.cancel")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !report.isRunning {
                        Button("Done") {
                            send(.dismissBatch)
                        }
                        .accessibilityIdentifier("batch.done")
                    }
                }
            }
            .clashProductModalRoot(
                title: .copy(report.title)
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if insideProductModal {
                     
                     
                     
                     
                     
                     
                    ClashModalActionBar(
                        primaryTitle: "Done",
                        primaryDisabled: report.isRunning
                    ) {
                        send(.dismissBatch)
                    }
                }
            }
        }
        .interactiveDismissDisabled(report.isRunning)
    }

    private func symbol(
        for state: ClashProfileBatchUpdateState
    ) -> ClashSymbol {
        switch state {
        case .updated:
            .checkmarkCircleFill
        case .unchanged:
             
             
             
             
            .checkmarkCircle
        case .failed:
            .exclamationmarkTriangleFill
        }
    }

    private func tint(
        for state: ClashProfileBatchUpdateState
    ) -> Color {
        switch state {
        case .updated:
            .green
        case .unchanged:
            .green
        case .failed:
            .red
        }
    }

    private func send(_ command: ClashProfilesCommand) {
        Task { @MainActor in
            try? await actions.perform(
                .profiles(command),
                allowedBy: snapshot
            )
        }
    }
}

 
 
 
public struct ClashProfileGroup<
    Content: View
>: View {
    let nativeList: Bool
    let title: ClashDisplayText
    let palette: ClashProductPalette
    let presentationClass: ClashPresentationClass
    let content: Content

    public init(
        title: ClashDisplayText,
        palette: ClashProductPalette,
        presentationClass: ClashPresentationClass,
        nativeList: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.palette = palette
        self.presentationClass = presentationClass
        self.nativeList = nativeList
        self.content = content()
    }

    @ViewBuilder
    public var body: some View {
        let _ = ClashPerf.count("profile.group")
        if nativeList || ClashPlatformLayout.pageUsesSystemSettingsIdiom {
             
             
             
             
             
             
             
            Section {
                content
            } header: {
                if nativeList { ClashConfigurationLibraryHeader(title: title) }
                else { Text(clash: title) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            traditionalGroup
        }
    }

    private var traditionalGroup: some View {
        VStack(
            alignment: .leading,
            spacing: ClashTheme.Spacing.compact
        ) {
             
             
             
             
             
            ClashConfigurationLibraryHeader(title: title)
                .padding(.horizontal, ClashTheme.Spacing.standard)
            ClashCardSurface(
                fill: palette.card,
                separator: palette.separator
            ) {
                VStack(spacing: 0) {
                    content
                }
                .padding(.horizontal, ClashTheme.Spacing.standard)
                .padding(
                    .vertical,
                    presentationClass == .regularTouch
                        || presentationClass == .desktop
                        ? ClashTheme.Spacing.compact
                        : 0
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

 
 
public struct ClashProfileActionRow<Icon: View>: View {
    let title: ClashDisplayText
    var subtitle: ClashDisplayText? = nil
     
     
    var value: ClashDisplayText? = nil
    let symbol: ClashSymbol
    let tint: Color
    var titleColor: Color = .primary
    var showsDisclosure: Bool = true
     
     
     
    var isBusy: Bool = false
    let icon: (ClashSymbol) -> Icon

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        title: ClashDisplayText,
        subtitle: ClashDisplayText? = nil,
        value: ClashDisplayText? = nil,
        symbol: ClashSymbol,
        tint: Color,
        titleColor: Color = .primary,
        showsDisclosure: Bool = true,
        isBusy: Bool = false,
        icon: @escaping (ClashSymbol) -> Icon
    ) {
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.symbol = symbol
        self.tint = tint
        self.titleColor = titleColor
        self.showsDisclosure = showsDisclosure
        self.isBusy = isBusy
        self.icon = icon
    }

    public var body: some View {
        let _ = ClashPerf.count("profile.action.row")
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityActionRow
            } else {
                HStack(spacing: ClashTheme.Spacing.row) {
                    leadingIcon
                    actionCopy
                    Spacer(minLength: ClashTheme.Spacing.compact)
                    if let value {
                        Text(clash: value)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else if showsDisclosure {
                        disclosureIcon
                    }
                }
                .padding(
            .vertical,
            ClashMacSettingsMetrics.rowVerticalInset(
                touch: ClashTheme.Spacing.row
            )
        )
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilityActionRow: some View {
        VStack(
            alignment: .leading,
            spacing: ClashTheme.Spacing.row
        ) {
            HStack {
                leadingIcon
                Spacer(minLength: ClashTheme.Spacing.standard)
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else if showsDisclosure {
                    disclosureIcon
                }
            }
            actionCopy
             
             
             
            if let value {
                Text(clash: value)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(
            .vertical,
            ClashMacSettingsMetrics.rowVerticalInset(
                touch: ClashTheme.Spacing.row
            )
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var leadingIcon: some View {
        icon(symbol)
            .font(.body.weight(.medium))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)
    }

    private var actionCopy: some View {
        VStack(
            alignment: .leading,
            spacing: ClashTheme.Spacing.tight
        ) {
            Text(clash: title)
                .font(.body)
                .foregroundStyle(titleColor)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(clash: subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var disclosureIcon: some View {
         
         
        if !ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            icon(.chevronForward)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }
}

private struct ClashSubscriptionUsageView: View {
    enum Style {
         
         
         
         
        case row
         
        case detail
    }

    let subscription: ClashProfileSubscriptionSnapshot
    var style: Style = .detail
     
     
    var note: ClashDisplayText? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

     
     
     
     
     
     
     
    static func quotaText(_ subscription: ClashProfileSubscriptionSnapshot) -> Text? {
        guard subscription.totalBytes > 0 else { return nil }
        let view = ClashSubscriptionUsageView(subscription: subscription)
        return Text("\(view.compactBytes(subscription.usedBytes)) of \(view.compactBytes(subscription.totalBytes))")
    }

     
     
    static func metaText(_ subscription: ClashProfileSubscriptionSnapshot) -> Text {
        ClashSubscriptionUsageView(subscription: subscription).detailMetaLine
    }

    static func usedText(
        _ subscription: ClashProfileSubscriptionSnapshot
    ) -> Text? {
        subscription.usageFraction.map {
             
             
             
            Text(clash: .format("%@ used", ["\(Int($0 * 100))%"]))
        }
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: ClashTheme.Spacing.tight
        ) {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityUsageSummary
            } else if style == .detail {
                 
                 
                 
                 
                 
                HStack(
                    alignment: .firstTextBaseline,
                    spacing: ClashTheme.Spacing.compact
                ) {
                    if subscription.totalBytes > 0 {
                        Text(
                            "\(compactBytes(subscription.usedBytes)) of \(compactBytes(subscription.totalBytes))"
                        )
                        .font(.caption)
                        .foregroundStyle(.primary)
                    }
                    Spacer(minLength: ClashTheme.Spacing.compact)
                    if let used = Self.usedText(subscription) {
                        used
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .monospacedDigit()
                .lineLimit(1)
            }
            if let fraction = subscription.usageFraction {
                ClashUsageGauge(fraction: fraction)
            }
            if !dynamicTypeSize.isAccessibilitySize {
                if style == .detail {
                     
                     
                     
                     
                    detailMetaLine
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else if let line = rowMetaLine {
                     
                     
                     
                     
                     
                     
                    line
                        .font(.caption)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }


     
     
     
    private var rowMetaLine: Text? {
        var pieces: [Text] = []
        if let used = Self.usedText(subscription) { pieces.append(used.foregroundColor(.secondary)) }
        if let note { pieces.append(Text(clash: note).foregroundColor(.secondary)) }
        if let expiration = subscription.expiration {
            pieces.append(
                Text(clash: .format("until %@", [dateString(expiration)]))
                    .foregroundColor(expiryTint(expiration))
            )
        }
        guard let first = pieces.first else { return nil }
        return pieces.dropFirst().reduce(first) { $0 + Text(" · ").foregroundColor(.secondary) + $1 }
    }

     
     
    private var detailMetaLine: Text {
        var line = Text(
            "↑ \(compactBytes(subscription.uploadBytes)) · ↓ \(compactBytes(subscription.downloadBytes))"
        )
        if let expiration = subscription.expiration {
            line = Text(clash: .format(
                "until %@", [dateString(expiration)]
            ))
                .foregroundColor(expiryTint(expiration))
                + Text(" · ")
                + line
        }
        return line
    }

    private var accessibilityUsageSummary: some View {
        VStack(
            alignment: .leading,
            spacing: ClashTheme.Spacing.tight
        ) {
            Text(
                "Uploaded \(compactBytes(subscription.uploadBytes))"
            )
            Text(
                "Downloaded \(compactBytes(subscription.downloadBytes))"
            )
            if subscription.totalBytes > 0 {
                Text(
                    "Total \(compactBytes(subscription.totalBytes))"
                )
            }
            if let expiration = subscription.expiration {
                Text("Expires \(dateString(expiration))")
                    .foregroundStyle(expiryTint(expiration))
            }
        }
        .font(.caption2)
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
    }



    private func compactBytes(_ bytes: Int64) -> String {
        let units = ["K", "M", "G", "T"]
        var value = Double(max(0, bytes)) / 1_024
        var unit = 0
        while value >= 1_000, unit < units.count - 1 {
            value /= 1_024
            unit += 1
        }
        let text = value < 100
            ? String(format: "%.1f", value)
            : String(format: "%.0f", value)
        return text.replacingOccurrences(
            of: ".0",
            with: ""
        ) + units[unit]
    }

     
     
     
     
     
     
     
     
     
    private static let expiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private func dateString(_ date: Date) -> String {
        Self.expiryFormatter.string(from: date)
    }

    private func expiryTint(_ expiration: Date) -> Color {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone =
            TimeZone(identifier: "UTC")
            ?? TimeZone(secondsFromGMT: 0)!
        let days =
            calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: Date()),
                to: calendar.startOfDay(for: expiration)
            ).day ?? 0
        if days <= 0 {
            return .red
        }
        if days <= 7 {
            return .orange
        }
        return .secondary
    }
}

 
enum ClashProfileSourcesSummary {
     
     
     
     
     
     
    static func value(_ names: [String]?) -> ClashDisplayText {
        let present = (names ?? []).filter { !$0.isEmpty }
        guard !present.isEmpty else { return .copy("Choose node sources") }
        guard present.count > 2 else { return .verbatim(present.joined(separator: " · ")) }
         
        return .format("%@ sources", [String(present.count)])
    }
}
