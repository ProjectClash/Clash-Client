import ClashClientUI
import SwiftUI

 
 
 
 
private enum ClientSettingsDoor: String, Identifiable {
    case udpFallback
    case externalController
    var id: String { rawValue }
}

struct ClientSettingsView: View {
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
    @State private var doorSelection: ClientSettingsDoor?
     
    @Environment(\.externalControllerCore) private var externalController
     
    @State private var externalControllerMode = ClashRemoteControlSettings.default.mode

    private var udpFallbackDestination: some View {
        UDPFallbackSettingsView(
            policy: Binding(
                get: { udpFallback },
                set: { newValue in
                     
                     
                    if let newValue { udpFallback = newValue }
                }
            ),
            offersInherit: false,
            overallPolicy: udpFallback,
             
             
             
             
            profileOverride: activeProfileUDPFallback,
            guardInput: activeProfileUDPFallbackGuardInput
        )
        .onChange(of: udpFallback) {
            UDPFallbackSettings.setPolicy($0)
            restageRuntime()
        }
    }

    @ObservedObject var command: ClashCommandClient
     
     
     
     
     
    var activeProfileUDPFallback: UDPFallbackPolicy?
     
     
     
     
     
     
     
     
     
    var activeProfileUDPFallbackGuardInput: () async -> ConfigTransforms.UDPFallbackGuardInput? = { nil }
     
     
     
     
     
    var restageRuntime: () -> Void = {}
    @State private var testURLText = DelayTestSettings.url()
    @FocusState private var editingURL: Bool
    @State private var rejected = false
    @State private var autoClose = NodeSwitchSettings.autoCloseOnSwitch()
    @State private var udpFallback = UDPFallbackSettings.policy()
    @State private var userAgentPreset = ClientUserAgent.preset()
    @State private var moduleUserAgent = ClientUserAgent.moduleOverride()
     
     
     
    @State private var certificateStore = UserDefaults(suiteName: ClashAppIdentifiers.appGroup)?
        .string(forKey: CertificateStorePolicy.defaultsKey) ?? CertificateStorePolicy.platform
    @AppStorage(
        TrafficStatisticsSettings.key,
        store: TrafficStatisticsSettings.appGroupDefaults
    ) private var onlyProxyTraffic = false
     
     
     
    @State private var throughputUnit = ClashThroughputUnit.stored(in: GlobalConfig.appGroupDefaults)
    @AppStorage(
        NetworkPathPolicySettings.allowExpensiveUpdatesKey,
        store: GlobalConfig.appGroupDefaults
    ) private var allowExpensiveUpdates = true
    @AppStorage(
        NetworkPathPolicySettings.allowConstrainedUpdatesKey,
        store: GlobalConfig.appGroupDefaults
    ) private var allowConstrainedUpdates = true

    var body: some View {
        ClashMacSettingsFormContainer {
            Section {
                Toggle("Close connections on node switch", isOn: $autoClose)
                    .accessibilityIdentifier("client.close-connections-on-switch")
                    .onChange(of: autoClose) { NodeSwitchSettings.setAutoCloseOnSwitch($0) }
            } footer: {
                Text("Moves live traffic to the newly selected node immediately.")
            }

            Section {
                ClashDoorLink(ClientSettingsDoor.udpFallback, selection: $doorSelection) {
                    udpFallbackDestination
                } label: {
                     
                     
                    HStack {
                        Text(clash: .copy("UDP Fallback"))
                        Spacer()
                        Text(clash: .copy(udpFallbackSummary))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("client.udpFallback")
            } footer: {
                Text(clash: .copy("HTTP and HTTPS proxies have no UDP transport. Without this, matched traffic the outbound cannot carry falls through every rule and leaves over DIRECT with your own address."))
            }

            Section {
                 
                 
                 
                Picker(
                    "Speed Unit",
                    selection: Binding(
                        get: { throughputUnit },
                        set: { unit in
                            throughputUnit = unit
                            ClashThroughputUnit.store(unit, in: GlobalConfig.appGroupDefaults)
                        }
                    )
                ) {
                    Text("Bits (Mbps)").tag(ClashThroughputUnit.bits)
                    Text("Bytes (MB/s)").tag(ClashThroughputUnit.bytes)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("client.throughputUnit")
                 
                 
                .onAppear { throughputUnit = ClashThroughputUnit.stored(in: GlobalConfig.appGroupDefaults) }
                .onReceive(NotificationCenter.default.publisher(for: ClashThroughputUnit.didChangeNotification)) { _ in
                    throughputUnit = ClashThroughputUnit.stored(in: GlobalConfig.appGroupDefaults)
                }
                Toggle("Count proxy traffic only", isOn: $onlyProxyTraffic)
                    .onChange(of: onlyProxyTraffic) { _ in
                        command.applyTrafficStatisticsPreference()
                    }
                    .accessibilityIdentifier("client.onlyProxyTraffic")
            } header: {
                Text("Traffic Statistics")
            } footer: {
                Text("Off shows all traffic. On hides traffic sent directly to the internet (final outbound DIRECT), so dashboard numbers reflect proxy use. The VPN stays connected while Clash refreshes statistics.")
            }

            Section {
                Toggle("Allow metered automatic updates", isOn: $allowExpensiveUpdates)
                    .accessibilityIdentifier("client.path.allowExpensiveUpdates")
                Toggle("Allow Low Data automatic updates", isOn: $allowConstrainedUpdates)
                    .accessibilityIdentifier("client.path.allowConstrainedUpdates")
            } header: {
                Text("Automatic Updates")
            } footer: {
                Text("Profile URLs and resources update on their own schedule over any connection. Turn one off to hold updates back on that kind of network.")
            }

            Section {
                Picker("Profile URL Compatibility", selection: $userAgentPreset) {
                    ForEach(ClientUserAgent.Preset.allCases) { preset in
                        Text(clash: .copy(preset.label)).tag(preset)
                    }
                }
                .onChange(of: userAgentPreset) {
                    ClientUserAgent.save(preset: $0)
                }
                .accessibilityIdentifier("client.user-agent-preset")
            } header: {
                Text("Download Identity")
            } footer: {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                Text("The app sends this when it downloads a Profile URL. Downloads the core makes for a configuration use that configuration’s Download User-Agent. Clash is recommended; FlClash is a compatibility fallback for panels that negotiate by client name.")
            }


            Section {
                Picker("Module Downloads", selection: $moduleUserAgent) {
                    Text(clash: .copy("Match the module’s platform")).tag(ClientUserAgent.Preset?.none)
                    ForEach(ClientUserAgent.Preset.allCases) { preset in
                        Text(clash: .copy(preset.label)).tag(ClientUserAgent.Preset?.some(preset))
                    }
                }
                .onChange(of: moduleUserAgent) {
                    ClientUserAgent.saveModuleOverride($0)
                }
                .accessibilityIdentifier("client.module-user-agent")
            } header: {
                Text("Module Download Identity")
            } footer: {
                Text("A module hub usually serves one platform only, so a module is fetched with the platform it belongs to — a Loon plugin with Loon’s name, a Surge module with Surge’s. Choose one here only if a hub asks for something else.")
            }

            if let externalController {
                Section {
                    ClashDoorLink(ClientSettingsDoor.externalController, selection: $doorSelection) {
                        ExternalControllerSettingsView(core: externalController)
                    } label: {
                        HStack {
                            Text(clash: .copy("External Controller"))
                            Spacer()
                            Text(clash: externalControllerMode.title)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("client.external-controller")
                } footer: {
                    Text("Lets clash-cli on a Mac and AI assistants control Clash on this device.")
                }
            }

            Section {
                Picker("Certificate store", selection: $certificateStore) {
                    ForEach([CertificateStorePolicy.platform] + CertificateStorePolicy.selectable, id: \.self) { value in
                        Text(clash: .copy(CertificateStorePolicy.title(for: value))).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: certificateStore) {
                    UserDefaults(suiteName: ClashAppIdentifiers.appGroup)?.set($0, forKey: CertificateStorePolicy.defaultsKey)
                }
                .accessibilityIdentifier("client-settings.certificate-store")
            } header: {
                Text("Trust")
            } footer: {
                Text(clash: .copy(CertificateStorePolicy.detail(for: certificateStore)))
            }

            Section {
                clashPromptField(
                    DelayTestSettings.defaultURL,
                    text: $testURLText
                )
                    .accessibilityIdentifier("client.delay-test-url")
                    .font(ClashPlatformLayout.pageUsesSystemSettingsIdiom ? ClashMacSettingsType.mono : .caption.monospaced())
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(save)
                    .focused($editingURL)
                if rejected {
                    ClashStatusMessage(
                        text: .copy("HTTPS URL with a host required; leave empty for the default."),
                        kind: .error
                    )
                }
            } header: {
                Text("Delay test URL")
            } footer: {
                Text("Used by node delay tests. Empty resets to the default endpoint.")
            }
        }
        
        .clashDoorPresenter(
            selection: $doorSelection,
            title: { door in door == .externalController ? "External Controller" : "UDP Fallback" }
        ) { door in
            switch door {
            case .udpFallback: udpFallbackDestination
            case .externalController:
                if let externalController { ExternalControllerSettingsView(core: externalController) }
            }
        }
        .onAppear {
            externalControllerMode = ClashRemoteControlSettings.load(
                from: UserDefaults(suiteName: ClashAppIdentifiers.appGroup)).mode
        }
        .onChange(of: doorSelection) { door in
            guard door == nil else { return }
            externalControllerMode = ClashRemoteControlSettings.load(
                from: UserDefaults(suiteName: ClashAppIdentifiers.appGroup)).mode
        }
        .clashPageTitle("Client Settings")
        .toolbar {
             
             
             
            ToolbarItem(placement: .confirmationAction) {
                if !insideProductModal {
                    if editingURL || testURLText != DelayTestSettings.url() {
                        Button("Save") {
                            save()
                            editingURL = false
                        }
                        .accessibilityIdentifier("client-settings.save")
                    }
                }
            }
        }
        .onDisappear(perform: save)
         
         
         
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if insideProductModal {
                 
                 
                 
                ClashModalActionBar(primaryTitle: "Save",
                    primaryDisabled: testURLText == DelayTestSettings.url(),
                    onPrimary: save)
            }
        }
    }

    private func save() {
        rejected = !DelayTestSettings.setURL(testURLText)
        if !rejected { testURLText = DelayTestSettings.url() }
    }

     
    private var udpFallbackSummary: String {
        switch udpFallback {
        case .quic: "Reject QUIC"
        case .quicAllPorts: "Reject QUIC on 443 and 80"
        case .allUDP: "Reject all fallthrough UDP"
        case .off: "Off"
        }
    }

}
