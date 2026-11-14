import SwiftUI
import ClashClientUI

 
 
 
 
 
struct GoldenFlowMoreAdapter: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.clashShellLayout) private var shellLayout

    @ObservedObject var vpn: VPNController
    @ObservedObject var command: ClashCommandClient
    @ObservedObject var preferences: AppPreferencesModel
    @Binding var destination:
        AppNavigationDestination.MoreDestination
    var ownsNavigationContainer = true
     
     
    var navigate: (AppNavigationDestination) -> Void = { _ in }
    @State private var attention: LegacySettingsAttention?
     
    @State private var movedNotice: ClashMoreAttention?

    var body: some View {
        Group {
            if ownsNavigationContainer {
                ClashFeatureNavigationContainer {
                    sharedRoot
                        .clashPageTitle("More")
                }
                .clashStackNavigationViewStyle()
            } else {
                sharedRoot
            }
        }
        .environment(
            \.clashUsesRegularDetailLayout,
            !ownsNavigationContainer
        )
        .onAppear { refreshAttention() }
        .onChange(of: vpn.legacySettingsMigration) { _ in refreshAttention() }
    }

    private var workingDirectory: URL? {
        ClashAppIdentifiers.appGroupContainer?.appendingPathComponent("working", isDirectory: true)
    }

     
     
    private func refreshAttention() {
        movedNotice = FlClashRuntimeConfig.movedIntoConfigurationsNoticePending() ? .settingsMovedIntoConfigurations : nil
        guard let result = vpn.legacySettingsMigration, let workingDirectory else {
            attention = nil
            return
        }
        let profiles = ProfileStore(
            fileURL: workingDirectory.appendingPathComponent("store/profiles.json")
        ).load()
        attention = LegacySettingsAttention.make(from: result, profiles: profiles)
    }

     
     
     
    private func performAttention(actionID: String) {
        if attention == nil, movedNotice?.actions.contains(where: { $0.id == actionID }) == true {
            FlClashRuntimeConfig.acknowledgeMovedIntoConfigurationsNotice()
            refreshAttention()
            return
        }
        guard let attention,
              let action = attention.actions.first(where: { $0.id == actionID })
        else { return }
        switch action.resolution {
        case .openProfile(let id):
            navigate(id.map { .profileDetail(id: $0) } ?? .profiles)
        case .openScripts:
             
             
            navigate(.profiles)
        default:
            guard let workingDirectory else { return }
            if let fresh = LegacySettingsResolver.perform(
                action.resolution,
                attentionID: attention.id,
                workingDirectory: workingDirectory
            ) {
                vpn.legacySettingsMigration = fresh
            }
            refreshAttention()
        }
    }

    private var sharedRoot: some View {
        ClashClientUI.ClashMoreView(
            snapshot: sharedSnapshot,
            destination: $destination,
            presentationClass:
                shellLayout == .regularSidebar
                    ? .regularTouch
                    : .compactTouch,
            palette: productPalette,
             
             
             
            omitting: shellLayout == .regularSidebar
                ? ClashMoreCatalog.regularHubExcludes
                : [],
            attentionAction: performAttention(actionID:),
            icon: { symbol in
                ClashSymbolImage(symbol: symbol)
            },
            destinationContent: { item in
                GoldenFlowMoreDestinationAdapter(
                    vpn: vpn,
                    command: command,
                    preferences: preferences,
                    destination: item,
                    usesRegularDetailLayout:
                        !ownsNavigationContainer
                )
            }
        )
    }

    private var productPalette: ClashClientUI.ClashProductPalette {
        ClashClientUI.ClashProductPalette.clashProduct
    }

    private var sharedSnapshot: AppleClientSnapshot {
        let onDemand = OnDemandSettings.configuration()
        let info = AppBuildInfo.current()
         
         
        let tunnelIncludeAllNetworks = vpn.tunnelSettings.includeAllNetworks
        return AppleClientSnapshot(
            revision: 0,
            connection: AppleClientConnectionSnapshot(
                phase: command.isConnected
                    ? .connected
                    : .disconnected
            ),
            more: ClashMoreSnapshot(
                onDemandEnabled: onDemand.enabled,
                onDemandRuleCount: onDemand.rules.count,
                tunnelIncludeAllNetworks: tunnelIncludeAllNetworks,
                showsDeveloperDestination:
                    showsDeveloperDestination,
                about: ClashAboutSnapshot(
                    appVersion: info.appVersion,
                     
                    buildNumber: info.buildNumber,
                    sourceRevision: info.sourceRevision,
                    coreVersion: info.coreVersion
                ),
                attention: attention?.snapshot ?? movedNotice
            )
        )
    }

    private var showsDeveloperDestination: Bool {

        false

    }

    private var developerModeBinding: Binding<Bool>? {

        nil

    }

}

 
struct GoldenFlowMoreDestinationAdapter: View {
    @ObservedObject var vpn: VPNController
    @ObservedObject var command: ClashCommandClient
    @ObservedObject var preferences: AppPreferencesModel
    let destination: AppNavigationDestination.MoreDestination
    var usesRegularDetailLayout: Bool
     
     
    let profileID: String?
    @StateObject private var profiles: ProfilesViewModel

    init(
        vpn: VPNController,
        command: ClashCommandClient,
        preferences: AppPreferencesModel,
        destination: AppNavigationDestination.MoreDestination,
        usesRegularDetailLayout: Bool,
        profileID: String? = nil
    ) {
        self.vpn = vpn
        self.command = command
        self.preferences = preferences
        self.destination = destination
        self.usesRegularDetailLayout = usesRegularDetailLayout
        self.profileID = profileID
        _profiles = StateObject(
            wrappedValue: ProfilesViewModel(vpn: vpn)
        )
    }

    private var sharedSnapshot: AppleClientSnapshot {
        let info = AppBuildInfo.current()
        return AppleClientSnapshot(
            revision: 0,
            connection: AppleClientConnectionSnapshot(
                phase: command.isConnected
                    ? .connected
                    : .disconnected
            ),
            more: ClashMoreSnapshot(
                showsDeveloperDestination:
                    showsDeveloperDestination,
                about: ClashAboutSnapshot(
                    appVersion: info.appVersion,
                     
                    buildNumber: info.buildNumber,
                    sourceRevision: info.sourceRevision,
                    coreVersion: info.coreVersion
                ),
                 
                 
                 
                 
                overrideCounts: OverrideEntryCount.moreCounts(
                    in: settingsProfile?.override.patchJSON ?? ""
                )
            )
        )
    }

    private var productPalette: ClashClientUI.ClashProductPalette {
        ClashClientUI.ClashProductPalette.clashProduct
    }

    private var showsDeveloperDestination: Bool {

        false

    }

    private var developerModeBinding: Binding<Bool>? {

        nil

    }

    var body: some View {
         
         
         
         
         
         
        pageBody
            .clashPageTitle(.copy(destination.title))
    }

    @ViewBuilder
    private var pageBody: some View {
        Group {
            switch destination {
            case .root:
                EmptyView()
            case .geoResources:
                ResourcesView()
            case .storage:
                StorageView(vpn: vpn, command: command, preferences: preferences)
            case .onDemand:
                OnDemandConfigView(
                    vpn: vpn,
                    usesRegularDetailLayout:
                        usesRegularDetailLayout
                )
            case .tunnel:
#if os(iOS)
                TunnelSettingsView(vpn: vpn)
#else
                 
                 
                 
                 
                ClashMacTunnelSettingsView(vpn: vpn)
#endif
             
             
            case .tunnelAndRoutes:
                if let profile = sourceProfile {
                    CurrentConfigurationSettingsHost(profiles: profiles, profile: profile) { settings, reread in
                        ProfileBaseDocumentHost(profiles: profiles, profile: settings.profile) { base in
                            ProfileRoutePresetView(
                                profile: settings.profile,
                                sourceYAML: base,
                                ownsNavigationContainer: false,
                                scopeFooter: settings.scopeSentence
                            ) {
                                try await profiles.updateRoutePreset($0, readAs: settings)
                                await reread()
                            }
                        }
                    }
                } else {
                    loadingCoreSettings
                }
            case .clientSettings:
                let guardProfile = settingsProfile
                ClientSettingsView(
                    command: command,
                    activeProfileUDPFallback: guardProfile?.udpFallbackPolicy,
                    activeProfileUDPFallbackGuardInput: { [profiles] in
                        guard let guardProfile else { return nil }
                        return await profiles.udpFallbackGuardInput(for: guardProfile)
                    }
                ) {
                    profiles.restageForClientRuntimeSetting()
                }
            case .appearance:
                AppearanceSettingsView(
                    preferences: preferences,
                    usesRegularDetailLayout:
                        usesRegularDetailLayout
                )
            case .about:
                ClashClientUI.ClashAboutView(
                    snapshot: sharedSnapshot.more.about,
                    palette: productPalette,
                    developerMode: developerModeBinding,
                     
                     
                    rate: AppStoreReviewLink.isConfigured ? { AppStoreReviewLink.requestReview() } : nil,
                    acknowledgements: { label in
                        ClashRoutedViewLink {
                            AcknowledgementsView()
                        } label: {
                            label
                        }
                    },
                    icon: { symbol in
                        ClashSymbolImage(symbol: symbol)
                    },
                    componentLogo: { component in
                        Image(
                            component == .clashCore
                                ? "clash.core.logo"
                                : "mihomo.logo"
                        )
                        .resizable()
                        .scaledToFit()
                    }
                )
                .clashInsetGroupedListStyle()
            case .developer:

                EmptyView()

            }
        }
        .environment(
            \.clashUsesRegularDetailLayout,
            usesRegularDetailLayout
        )
        .task {
            profiles.load()
        }
    }

    private var sourceProfile: Profile? {
        if let profileID { return profiles.profiles.first { $0.id == profileID } }
        if let activeProfileID = profiles.activeProfileID,
           let active = profiles.profiles.first(
               where: { $0.id == activeProfileID }
           )
        {
            return active
        }
        return profiles.profiles.first
    }

    private var settingsProfile: Profile? {
        sourceProfile.map {
            profiles.settingsProfile(for: $0)
        }
    }

    private var loadingCoreSettings: some View {
        VStack(spacing: ClashTheme.Spacing.standard) {
            ProgressView()
             
             
            Text("Loading")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("more.core-settings.loading")
    }

     
     
     
     
     
     
     
}



 
 
 
struct CurrentConfigurationSettingsHost<Content: View>: View {
    @ObservedObject var profiles: ProfilesViewModel
    let profile: Profile
    @ViewBuilder let content: (ProfilesViewModel.CurrentConfigurationSettings, @escaping () async -> Void) -> Content
    @State private var loaded: ProfilesViewModel.CurrentConfigurationSettings?
    @State private var failure: String?

    var body: some View {
        Group {
            if let loaded, loaded.profile.id == profile.id {
                content(loaded) { await read(reloading: true) }
            } else if let failure {
                ClashStatusMessage(text: .copy(failure), kind: .error)
                    .padding()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: profile) { await read(reloading: false) }
    }

    private func read(reloading: Bool) async {
        do {
            let value = try await profiles.loadCurrentConfigurationSettings(for: profile, reloading: reloading)
            guard !Task.isCancelled else { return }
            loaded = value
            failure = nil
        } catch is CancellationError {
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

extension ProfilesViewModel.CurrentConfigurationSettings {
     
     
    var scopeSentence: ClashDisplayText? {
        switch target {
        case .appLayer:
            return nil
        case .page(.own(_, let label, let count)) where count > 1:
            return .format("Changes here apply to all %@ configurations on rule scheme “%@”.", [String(count), label])
         
         
         
        case .ownLayer, .page:
            return .copy("Changes here apply to this configuration only.")
        }
    }

     
     
    var dnsScope: ClashDNSConfigurationScope? {
        guard let sentence = scopeSentence else { return nil }
        if case .page = target { return ClashDNSConfigurationScope(sentence: sentence, hasSwitch: false) }
        return ClashDNSConfigurationScope(sentence: sentence, hasSwitch: true)
    }
}

extension ClashMoreAttention {
     
     
     
    static let settingsMovedIntoConfigurations = ClashMoreAttention(
        id: "settings-moved-into-configurations",
        message: .copy("DNS, Local Mapping, Tunnel & Routes and Core Behavior are now edited in each configuration's editor; the certificate store is in Client Settings. Your settings were kept as they were; connections are unaffected."),
        actions: [ClashMoreAttentionAction(id: "settings-moved-into-configurations.acknowledge", title: .copy("Got It"))]
    )
}
