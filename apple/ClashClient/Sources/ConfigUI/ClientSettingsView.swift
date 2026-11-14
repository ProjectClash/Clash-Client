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
            policy: Self.udpFallbackChoice(shown: $udpFallback, restage: restageRuntime),
            offersInherit: false,
            overallPolicy: udpFallback,
             
             
             
             
            profileOverride: activeProfileUDPFallback,
            guardInput: activeProfileUDPFallbackGuardInput
        )
    }

     
     
     
     
     
     
     
     
     
     
     
    static func udpFallbackChoice(
        shown: Binding<UDPFallbackPolicy>,
        in defaults: UserDefaults = UDPFallbackSettings.appGroupDefaults,
        restage: @escaping () -> Void
    ) -> Binding<UDPFallbackPolicy?> {
        Binding(
            get: { shown.wrappedValue },
            set: { newValue in
                 
                 
                guard let newValue else { return }
                shown.wrappedValue = newValue
                guard UDPFallbackSettings.policy(from: defaults) != newValue else { return }
                UDPFallbackSettings.setPolicy(newValue, in: defaults)
                restage()
            }
        )
    }

     
     
     
     
    let command: ClashCommandClient
     
     
     
     
     
    var activeProfileUDPFallback: UDPFallbackPolicy?
     
     
     
     
     
     
     
     
     
    var activeProfileUDPFallbackGuardInput: () async -> ConfigTransforms.UDPFallbackGuardInput? = { nil }
     
     
     
     
     
    var restageRuntime: () -> Void = {}
    @State private var testURLText = DelayTestSettings.url()
     
    @State private var moduleSets: [ModuleDeviceSettingKey: ModuleDeviceSettingNote] = [:]
    @FocusState private var editingURL: Bool
    @State private var rejected = false
    @State private var autoClose = NodeSwitchSettings.autoCloseOnSwitch()
    @State private var udpFallback = UDPFallbackSettings.policy()
    @State private var userAgentPreset = ClientUserAgent.preset()
     
     
     
    @State private var certificateStore = UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite)?
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

    #if os(macOS)
     
     
     
    @State private var loginItem = ClashMacLoginItem.State.off
    @Environment(\.locale) private var locale

     
     
    private var launchesAtLogin: Binding<Bool> {
        Binding(
            get: { loginItem == .on },
            set: { on in
                ClashMacLoginItem.change(to: on) { error in
                    ClashMacLoginItem.reportFailure(error, turningOn: on, on: NSApplication.shared.keyWindow, locale: locale)
                }
                loginItem = ClashMacLoginItem.state
            }
        )
    }

     
     
     
     
     
    @ViewBuilder
    private var generalSection: some View {
        Section {
            Toggle("Launch Clash at login", isOn: launchesAtLogin)
                .accessibilityIdentifier("client.launch-at-login")
            if loginItem == .needsApproval {
                Button("Open System Settings") { ClashMacLoginItem.openSystemSettings() }
                    .accessibilityIdentifier("client.launch-at-login.open-settings")
            }
        } header: {
            Text("General")
        } footer: {
            if loginItem == .needsApproval {
                Text("Clash will launch at login once it is allowed in System Settings › General › Login Items.")
            }
        }
        .onAppear { loginItem = ClashMacLoginItem.state }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem = ClashMacLoginItem.state
        }
    }
    #endif

    var body: some View {
        ClashMacSettingsFormContainer {
            #if os(macOS)
            generalSection
            #endif

            Section {
                Toggle("Close connections on node or mode switch", isOn: $autoClose)
                    .accessibilityIdentifier("client.close-connections-on-switch")
                    .onChange(of: autoClose) { NodeSwitchSettings.setAutoCloseOnSwitch($0) }
            } footer: {
                Text("After you switch a node or the outbound mode, connections in use move to the new route immediately.")
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
                .pickerStyle(.menu)
                .accessibilityIdentifier("client.user-agent-preset")
                .onChange(of: userAgentPreset) { preset in
                    changingIdentity { ClientUserAgent.save(preset: preset) }
                }
            } header: {
                Text("Download Identity")
            } footer: {
                 
                 
                 
                 
                 
                 
                 
                Text("Sent when Clash downloads a Profile URL, and with every download of a configuration that sets no Download User-Agent of its own. Clash is recommended; FlClash is a compatibility fallback for panels that negotiate by client name.")
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
                    UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite)?.set($0, forKey: CertificateStorePolicy.defaultsKey)
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
                        text: .copy("An http or https URL with a host is required; leave empty for the default."),
                        kind: .error
                    )
                }
            } header: {
                Text("Delay test URL")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Used by node delay tests. Empty resets to the default endpoint.")
                     
                     
                    if let set = moduleSets[.testURL] {
                        Text(clash: .format("Module “%@” sets “%@”, which runs over this.", [set.module, set.value]))
                            .accessibilityIdentifier("client.delay-test-url.module-note")
                    }
                }
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
                from: UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite)).mode
        }
        .task { moduleSets = await ModuleDeviceSettingNote.published() }
        .onChange(of: doorSelection) { door in
            guard door == nil else { return }
            externalControllerMode = ClashRemoteControlSettings.load(
                from: UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite)).mode
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

     
     
     
     
     
    private func changingIdentity(_ change: () -> Void) {
        let before = ClientUserAgent.downloadIdentity()
        change()
        if ClientUserAgent.downloadIdentity() != before { restageRuntime() }
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
