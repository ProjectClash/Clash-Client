import ClashClientKit
import ClashClientUI
import SwiftUI

enum ProxyShareEndpointFormatter {
    static func format(address: String, port: Int32) -> String {
        address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)"
    }
}

 
 
 
 
 
 
 
 
 
enum ProxyShareAddressList {
    static let loopback = "127.0.0.1"

    private enum Listening { case everywhere, everyIPv4, only(String), nowhere }

    private static func listening(_ bindAddress: String?) -> Listening {
        let written = bindAddress?.trimmingCharacters(in: .whitespaces) ?? ""
        switch written {
        case "", "*", "[::]": return .everywhere
        case "0.0.0.0": return .everyIPv4
        case "localhost": return .only(loopback)
        default:
            if written.hasPrefix("["), written.hasSuffix("]") { return .only(String(written.dropFirst().dropLast())) }
            return written.contains(":") ? .nowhere : .only(written)
        }
    }

    static func hosts(lanAddresses: [String], bindAddress: String?) -> [String] {
        switch listening(bindAddress) {
        case .everywhere: [loopback] + lanAddresses
        case .everyIPv4: [loopback] + lanAddresses.filter { !$0.contains(":") }
        case .only(let address): [address]
        case .nowhere: []
        }
    }

     
     
    static func waitsForOtherDevices(bindAddress: String?) -> Bool {
        switch listening(bindAddress) {
        case .everywhere, .everyIPv4: true
        case .only, .nowhere: false
        }
    }

    static func isThisDeviceOnly(_ host: String) -> Bool {
        host == loopback || host == "::1"
    }

    enum Network: Equatable { case wifi, hotspot, thisDevice, other }

    struct Row: Equatable, Identifiable {
        let network: Network
        let address: String
        var id: String { address }
    }

     
     
     
     
     
    static func rows(hosts: [String], interfaces: [String: String]) -> [Row] {
        let lan = hosts.filter { !isThisDeviceOnly($0) }
        guard !lan.isEmpty else {
            return hosts.prefix(1).map { Row(network: .thisDevice, address: $0) }
        }
        var rows: [Row] = []
        var named = Set<String>()
        for preferIPv4 in [true, false] {
            for address in lan where address.contains(":") != preferIPv4 {
                let interface = interfaces[address] ?? address
                guard named.insert(interface).inserted else { continue }
                rows.append(Row(network: network(of: interfaces[address]), address: address))
            }
        }
         
        return rows.sorted { (lan.firstIndex(of: $0.address) ?? 0) < (lan.firstIndex(of: $1.address) ?? 0) }
    }

     
     
     
     
     
     
    static func reach(lanRows: [Row], allowsLAN: Bool, bindAddress: String? = nil) -> [Row] {
        guard allowsLAN else { return [Row(network: .thisDevice, address: loopback)] }
        let own: [Row]
        switch listening(bindAddress) {
        case .everywhere, .everyIPv4: own = [Row(network: .thisDevice, address: loopback)]
         
         
        case .only(let address): own = isThisDeviceOnly(address) ? [Row(network: .thisDevice, address: address)] : []
        case .nowhere: own = []
        }
        return own + lanRows.filter { $0.network != .thisDevice && !isThisDeviceOnly($0.address) }
    }

     
     
     
    static func everyRow(hosts: [String], interfaces: [String: String]) -> [Row] {
        hosts.filter { !isThisDeviceOnly($0) }.map { Row(network: network(of: interfaces[$0]), address: $0) }
    }

    private static func network(of interface: String?) -> Network {
        guard let interface else { return .other }
        if interface == "en0" { return .wifi }
        if interface.hasPrefix("bridge") { return .hotspot }
        return .other
    }
}

struct ProxyShareView: View {
    @ObservedObject var model: ProxyShareModel
#if os(iOS)
     
     
     
     
     
     
    var configuration: ConfigurationEditorSession? = nil
     
     
     
    var isRunningConfiguration = true
    @Environment(\.proxyShareProfiles) private var profiles
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
#else
     
     
     
    var isRunningConfiguration = true
     
     
     
     
    @Environment(\.proxyShareSettingsRows) private var settingsRows
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
#endif
    @Environment(\.clashFeedback) private var feedback

     
     
     
     
     
     
     
     
     
     
     
     
     
    @State private var deviations: ConfigDeviationReport?
    @AppStorage(ProxyEnvironmentShell.defaultsKey) private var environmentShellRaw = ProxyEnvironmentShell.bash.rawValue
    @State private var environmentCopied: EnvironmentCopy?

    private enum EnvironmentCopy {
        case local
        case external
    }
    @State private var portText = ""
     
     
     
    @State private var corePortText = ""
     
    @State private var coreHTTPPortText = ""
    @State private var coreSOCKSPortText = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmsReset = false
     
     
    @State private var lanExposureNotices: [String] = []
     
     
     
    @State private var tab: LANShareTab = .core

    enum LANShareTab: Hashable {
        case core
        case native
    }

    var body: some View {
         
         
         
         
         
         
         
#if os(iOS)
        if let configuration {
            page(access: configuration)
        } else if isRunningConfiguration, let profiles, let active = profiles.activeProfileID {
             
             
            ProxyShareActiveConfiguration(profiles: profiles, profileID: active) { page(access: $0) }
                .id(active)
        } else {
            page(access: nil)
        }
#else
        decorated(listenerContent)
#endif
    }

#if os(iOS)
     
    private func page(access: ConfigurationEditorSession?) -> some View {
        decorated(listenerContent(access: access))
            .task { await rereadAddressesWhileOpen() }
    }

     
     
     
    private func rereadAddressesWhileOpen() async {
        while !Task.isCancelled {
            guard (try? await Task.sleep(nanoseconds: 3_000_000_000)) != nil else { return }
            model.refreshAddresses()
        }
    }

     
     
    private var showsRunningFacts: Bool { isRunningConfiguration }
#else
    private var showsRunningFacts: Bool { isRunningConfiguration }
#endif

    private func decorated(_ content: some View) -> some View {
        content
        .clashPageTitle("LAN Proxy Share")
         
         
         
         
        .onChange(of: model.restartNotice) { notice in
            guard let notice, let feedback else { return }
            feedback.show(.information(title: .copy(notice), accessibilityIdentifier: "feedback.proxy-share.restart"),
                          operation: "proxy-share.restart")
            model.restartNotice = nil
        }
        .alert(
            Text(clash: .copy(model.restartNotice ?? "")),
            isPresented: Binding(get: { feedback == nil && model.restartNotice != nil },
                                 set: { if !$0 { model.restartNotice = nil } })
        ) {
            Button { model.restartNotice = nil } label: { Text(clash: .copy("OK")) }
        }
        .clashDetailPageInsets()
        .task {
            hydrateDraft(overwriteUsername: true)
            readCorePorts()
             
            model.refreshRunningListenerPorts()
            if showsRunningFacts {
                 
                 
                 
                 
                 
                lanExposureNotices = CoreLogExcerpt.lanExposureNotices()
                deviations = await Task.detached(priority: .utility) {
                    RunningCoreDeviations.activeProfileReport()
                }.value
            }
            await model.refresh()
            hydrateDraft(overwriteUsername: username.isEmpty)
        }
        .refreshable {
            await model.refresh()
            hydrateDraft(overwriteUsername: username.isEmpty)
        }
        .onChange(of: model.rememberedPort) { _ in
            if !isEditingPort { portText = String(model.rememberedPort) }
        }
         
         
         
         
         
        .onChange(of: tab) { _ in
            hydrateDraft(overwriteUsername: false)
        }
        .onReceive(model.terminalListenerDidChange) { _ in
            hydrateDraft(overwriteUsername: false)
            readCorePorts()
        }
        .confirmationDialog(
            "Reset LAN proxy credentials?",
            isPresented: $confirmsReset,
            titleVisibility: .visible
        ) {
            Button("Reset Credentials", role: .destructive) {
                Task {
                    if await model.reset() {
                        password = ""
                        hydrateDraft(overwriteUsername: true)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sharing stops first. The saved username and password are then removed from this device.")
        }
    }

    private var actionSection: some View {
        Section {
             
             
             
             
             
            Button {
                Task {
                    if model.status.enabled {
                        _ = await model.stop()
                    } else {
                        await submit()
                    }
                }
            } label: {
                 
                 
                 
                 
                 
                Text(model.status.enabled ? "Stop Sharing" : "Start Sharing")
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .clashPrimaryActionButtonStyle()
            .clashCapsuleButtonBorderShape()
            .controlSize(.regular)
            .tint(model.status.enabled ? .green : .blue)
            .disabled(model.phase == .unavailable || model.phase.isBusy)
            .accessibilityIdentifier("proxyShare.toggle")
            .accessibilityValue(Text(clash: .copy(model.phase.title)))

            if model.phase.isBusy {
                HStack(spacing: ClashTheme.Spacing.row) {
                    ProgressView()
                     
                    Text(clash: .copy(model.phase.title))
                        .font(ClashPlatformLayout.pageUsesSystemSettingsIdiom ? ClashMacSettingsType.value : .subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            if !model.errorMessage.isEmpty {
                ClashStatusMessage(text: .copy(model.errorMessage), kind: .error)
                    .accessibilityIdentifier("proxyShare.error")
            }
        } footer: {
            Text(clash: .copy(actionExplanation))
        }
    }

    private var connectSection: some View {
        Section {
            if reachableAddresses.isEmpty {
                ClashStatusMessage(
                    text: .copy("No usable Wi-Fi or Personal Hotspot address is available."),
                    kind: .information
                )
            } else {
                ForEach(reachableAddresses, id: \.self) { address in
                    Text(ProxyShareEndpointFormatter.format(
                        address: address,
                        port: model.status.port
                    ))
                    .font(ClashPlatformLayout.pageUsesSystemSettingsIdiom ? ClashMacSettingsType.mono : .subheadline.monospaced())
                    .textSelection(.enabled)
                     
                     
                     
                     
                    .id("share:\(address)")
                }
            }
            OverviewValueRow(title: "Username", value: .verbatim(model.savedUsername))
        } header: {
            Text("Connect From Another Device")
        } footer: {
            Text("Point the other device at one address above, over HTTP or SOCKS5, with this username and its saved password.")
        }
    }

    private var serverSection: some View {
        Section {
             
             
             
             
             
            ClashFieldRow(
                "Port",
                hint: "7890",
                text: $portText,
                monospaced: true,
                identifier: "proxyShare.port"
            )
            .keyboardType(.numberPad)
            .disabled(inputsDisabled)

            ClashFieldRow(
                "Username",
                hint: "Required",
                text: $username,
                identifier: "proxyShare.username"
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .disabled(inputsDisabled)

             
             
             
            ClashFieldRow(
                "Password",
                 
                 
                hint: ClashDisplayText.format("%@ bytes", [ProxyShareCredentialPolicy.passwordByteRange]).resolved(locale: locale),
                text: $password,
                secure: true,
                identifier: "proxyShare.password"
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .disabled(inputsDisabled)
        } header: {
            Text("Server")
        } footer: {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                 
                 
                 
                if !model.status.enabled, model.nativeSharePortSuggestion != nil {
                    Text(clash: .format(
                        "Port %@ is the profile's listener, so the next free port is suggested.",
                        [String(model.rememberedPort)]
                    ))
                    .accessibilityIdentifier("proxyShare.port.taken")
                }
                Text(clash: .copy(serverExplanation))
            }
        }
    }

    private var securitySection: some View {
        Section {
             
             
             
             
             
            Button(role: .destructive) {
                confirmsReset = true
            } label: {
                Text("Reset Saved Credentials")
            }
             
             
            .clashMacFormActionChrome()
            .disabled(model.phase.isBusy || !model.hasSavedPassword)
            .accessibilityIdentifier("proxyShare.reset")
        } header: {
            Text("Security")
        } footer: {
             
             
            Text("Only private, unique-local, and link-local source addresses are accepted. Sharing closes when the VPN stops, and credentials never enter profiles, backups, logs, or diagnostics.")
        }
    }

    private var kernelShare: KernelLANShare { model.kernelShare }

     
     
     
#if os(macOS)
     
     
    @ViewBuilder
    private var listenerContent: some View {
        if isRunningConfiguration {
            listenerTabs
        } else {
            ClashMacSettingsFormContainer { coreSections }
                .padding(ClashTheme.Spacing.standard)
        }
    }

    private var listenerTabs: some View {
        TabView(selection: $tab) {
            ClashMacSettingsFormContainer { coreSections }
                .tabItem {
                    Text(ClashCopy.key("Profile Port"))
                        .accessibilityIdentifier("proxyShare.tab.core")
                }
                .tag(LANShareTab.core)
            ClashMacSettingsFormContainer { nativeSections }
                .tabItem {
                    Text(ClashCopy.key("Native Share"))
                        .accessibilityIdentifier("proxyShare.tab.native")
                }
                .tag(LANShareTab.native)
        }
        .padding(ClashTheme.Spacing.standard)
    }
#else
    @ViewBuilder
    private func listenerContent(access: ConfigurationEditorSession?) -> some View {
        if #available(iOS 17.0, *) {
            touchListenerForm(access: access)
                .contentMargins(.top, ClashTheme.Spacing.row, for: .scrollContent)
        } else {
            touchListenerForm(access: access)
        }
    }

     
     
    private func touchListenerForm(access: ConfigurationEditorSession?) -> some View {
        ClashMacSettingsFormContainer {
            if isRunningConfiguration {
                Section {
                    Picker(ClashCopy.key("Listener"), selection: $tab) {
                        Text(ClashCopy.key("Profile Port")).tag(LANShareTab.core)
                        Text(ClashCopy.key("Native Share")).tag(LANShareTab.native)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("proxyShare.tab")
                    .frame(minHeight: 44)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            switch isRunningConfiguration ? tab : .core {
            case .core: coreSections(access: access)
            case .native: nativeSections
            }
        }
    }
#endif

#if os(macOS)
     
     
     
     
     
     
     
    @ViewBuilder
    private var coreSections: some View {
        coreSwitchSection
        listenSection(listener: kernelShare.listener, sharing: kernelShare.isOn)
        accessSection(listener: kernelShare.listener, sharing: kernelShare.isOn)
        if isRunningConfiguration {
            if model.displayedTerminalListener != nil {
                terminalSection
            }
            coreExposureSection
            listenerDeviationsSection
        }
    }
#else
     
     
     
     
     
     
     
    @ViewBuilder
    private func coreSections(access: ConfigurationEditorSession?) -> some View {
        coreSwitchSection
        listenSection(access: access, listener: kernelShare.listener, sharing: kernelShare.isOn)
        accessSection(access: access, listener: kernelShare.listener, sharing: kernelShare.isOn)
        if isRunningConfiguration {
            if model.displayedTerminalListener != nil {
                terminalSection
            }
            coreExposureSection
            listenerDeviationsSection
        }
    }

     
     
     
     
     
    private func listenSection(access: ConfigurationEditorSession?, listener: ProfileListenerPorts?,
                               sharing: Bool) -> some View {
        Section {
             
             
             
             
             
             
             
             
            ForEach(reachRows(access: access)) { row in
                OverviewValueRow(title: Self.title(of: row.network), value: .verbatim(row.address))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("proxyShare.core.address")
            }
            portField(.mixed, key: "mixed-port", text: $corePortText, hint: unsetWords("mixed-port"),
                      identifier: "proxyShare.core.port")
            portField(.http, key: "port", text: $coreHTTPPortText, hint: unsetWords("port"),
                      identifier: "proxyShare.core.httpPort")
            portField(.socks, key: "socks-port", text: $coreSOCKSPortText, hint: unsetWords("socks-port"),
                      identifier: "proxyShare.core.socksPort")
            if let access {
                 
                 
                ProxyShareListenAddressRow(session: access)
            }
        } header: {
            Text("Listener")
        } footer: {
            let rows = reachRows(access: access)
            let allowsLAN = model.kernelShareReach(running: isRunningConfiguration).allowsLAN
            if rows.contains(where: { $0.network != .thisDevice }) {
                Text("Point the other device at one address above, over HTTP or SOCKS5.")
            } else if allowsLAN, !rows.isEmpty || !model.kernelShareReach(running: isRunningConfiguration).ports.isEmpty,
                      ProxyShareAddressList.waitsForOtherDevices(bindAddress: bindAddress(access)) {
                Text("Once a device joins your Personal Hotspot or you join Wi-Fi, the address other devices use appears here.")
            } else if !rows.isEmpty {
                Text("Apps on this device use the address above, over HTTP or SOCKS5.")
            }
        }
    }

     
     
     
    private func bindAddress(_ access: ConfigurationEditorSession?) -> String? {
        ProxyShareListenAddressMenu.text(of: access?.settingsValue(at: [ProxyShareListenAddressRow.key]))
    }

     
     
    private func reachRows(access: ConfigurationEditorSession?) -> [ProxyShareAddressList.Row] {
        let reach = model.kernelShareReach(running: isRunningConfiguration)
        guard !reach.ports.isEmpty else { return [] }
        return ProxyShareAddressList.reach(
            lanRows: ProxyShareAddressList.rows(hosts: addressHosts(access), interfaces: model.localInterfaces),
            allowsLAN: reach.allowsLAN, bindAddress: bindAddress(access))
    }

     
     
    private func addressHosts(_ access: ConfigurationEditorSession?) -> [String] {
        ProxyShareAddressList.hosts(lanAddresses: reachableAddresses, bindAddress: bindAddress(access))
    }

     
     
     
     
    private func portField(_ port: KernelLANSharePort, key: String, text: Binding<String>, hint: String,
                           identifier: String) -> some View {
        let subtitle = portStatus(port, key: key, typed: text.wrappedValue)
        return ClashFieldRow(
            fieldCopy.entry(forPath: key, language: .init(locale: locale))?.title ?? key,
            hint: hint,
            text: text,
            monospaced: true,
            compactValue: true,
            identifier: identifier,
            subtitle: subtitle,
            onEditingEnded: {
                let typed = text.wrappedValue
                Task {
                    await model.setKernelSharePort(port, text: typed)
                    text.wrappedValue = model.kernelSharePortText(port)
                }
            }
        )
        .keyboardType(.numberPad)
    }

     
     
    private func unsetWords(_ key: String) -> String {
        fieldCopy.entry(forPath: key, language: .init(locale: locale))?.unset ?? ""
    }

     
     
    private func portStatus(_ port: KernelLANSharePort, key: String, typed: String) -> ClashDisplayText? {
        switch model.kernelSharePortStatus(port, typed: typed, running: isRunningConfiguration) {
        case .closed?: .verbatim(unsetWords(key))
        case .notListening?: .copy("Not listening")
        case .numberTakenByAnother?: .copy("Not listening: another port has this number")
        case nil: nil
        }
    }

     
     
     
     
    @ViewBuilder
    private func accessSection(access: ConfigurationEditorSession?, listener: ProfileListenerPorts?,
                               sharing: Bool) -> some View {
        if let access {
            Section {
                ProxyShareSettingRows(session: access,
                                      keys: ["authentication", "skip-auth-prefixes", "lan-allowed-ips", "lan-disallowed-ips"])
            } header: {
                Text("Access Control")
            } footer: {
                if sharing, let listener, listener.credentials == nil {
                    Text("No proxy account is set: anyone on this network can use this proxy.")
                }
            }
        }
    }

#endif

     
    private static func title(of network: ProxyShareAddressList.Network) -> ClashDisplayText {
        switch network {
        case .wifi: .verbatim("Wi-Fi")
        case .hotspot: .copy("Personal Hotspot")
        case .thisDevice: .copy("This Device")
        case .other: .verbatim("IP")
        }
    }

     
     
    private func readCorePorts() {
        corePortText = model.kernelSharePortText
        coreHTTPPortText = model.kernelSharePortText(.http)
        coreSOCKSPortText = model.kernelSharePortText(.socks)
    }

    @ViewBuilder
    private var nativeSections: some View {
        actionSection
        if model.status.enabled {
            connectSection
        }
        serverSection
        securitySection
        if model.displayedTerminalListener != nil {
            terminalSection
        }
    }

     
     
     
     
     
     
    private var coreSwitchSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { kernelShare.isOn },
                set: { model.pressKernelShare(on: $0) }
            )) {
                 
                 
                 
                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                    Text("Allow LAN Connections")
                    Text(clash: .copy(kernelShareSourceLine))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("proxyShare.allowLan.source")
                    if !kernelShare.isOn, !model.kernelShareReach(running: isRunningConfiguration).ports.isEmpty {
                        Text("When off, apps on this device can still use it (127.0.0.1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("proxyShare.allowLan.thisDevice")
                    }
                }
            }
            .accessibilityIdentifier("proxyShare.allowLan")

            if !model.errorMessage.isEmpty {
                ClashStatusMessage(text: .copy(model.errorMessage), kind: .error)
                    .accessibilityIdentifier("proxyShare.error")
            }
        } footer: {
            Text("Follows the configuration until you change it here. A change here applies to this configuration only. Leave a port empty or enter 0 to turn it off; enter the configuration's own port to follow it again. Takes effect the next time the tunnel starts.")
        }
    }

     
     
     
     
     
     
     
     
     
    @ViewBuilder
    private var coreExposureSection: some View {
        if !lanExposureNotices.isEmpty {
            Section {
                Label {
                    Text("At the last start, other devices on this network could use this proxy without an account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: ClashSymbol.exclamationmarkTriangleFill.rawValue)
                        .foregroundStyle(Color.orange)
                }
                .accessibilityIdentifier("proxyShare.lanExposure")
            } header: {
                Text("Last Start")
            } footer: {
                Text("Set a proxy account or allowed devices to limit who can use it.")
            }
        }
    }

     
     
     
    private var kernelShareSourceLine: String {
        kernelShare.source == .override ? "Changed here" : "From the profile"
    }

#if os(macOS)
     
     
     
     
     
    private func listenSection(listener: ProfileListenerPorts?, sharing: Bool) -> some View {
        Section {
            portField(.mixed, key: "mixed-port", text: $corePortText, hint: unsetWords("mixed-port"),
                      identifier: "proxyShare.core.port")
            portField(.http, key: "port", text: $coreHTTPPortText, hint: unsetWords("port"),
                      identifier: "proxyShare.core.httpPort")
            portField(.socks, key: "socks-port", text: $coreSOCKSPortText, hint: unsetWords("socks-port"),
                      identifier: "proxyShare.core.socksPort")
            if let settingsRows {
                settingsRows(["bind-address"])
            }
            reachRows(sharing: sharing)
        } header: {
            Text("Listener")
        } footer: {
            let reach = model.kernelShareReach(running: isRunningConfiguration)
            if !reach.ports.isEmpty {
                if reach.allowsLAN, !reachableAddresses.isEmpty {
                    Text("Point the other device at one address above, over HTTP or SOCKS5.")
                } else {
                    Text("Apps on this device use the address above, over HTTP or SOCKS5.")
                }
            }
        }
    }

     
     
     
     
     
    private func portField(_ port: KernelLANSharePort, key: String, text: Binding<String>, hint: String,
                           identifier: String) -> some View {
        ClashFieldRow(
            fieldCopy.entry(forPath: key, language: .init(locale: locale))?.title ?? key,
            hint: hint,
            text: text,
            monospaced: true,
            compactValue: true,
            identifier: identifier,
            subtitle: portStatus(port, key: key, typed: text.wrappedValue),
            onEditingEnded: {
                let typed = text.wrappedValue
                Task {
                    await model.setKernelSharePort(port, text: typed)
                    text.wrappedValue = model.kernelSharePortText(port)
                }
            }
        )
    }

     
     
    private func unsetWords(_ key: String) -> String {
        fieldCopy.entry(forPath: key, language: .init(locale: locale))?.unset ?? ""
    }

     
     
    private func portStatus(_ port: KernelLANSharePort, key: String, typed: String) -> ClashDisplayText? {
        switch model.kernelSharePortStatus(port, typed: typed, running: isRunningConfiguration) {
        case .closed?: .verbatim(unsetWords(key))
        case .notListening?: .copy("Not listening")
        case .numberTakenByAnother?: .copy("Not listening: another port has this number")
        case nil: nil
        }
    }

     
     
     
     
    @ViewBuilder
    private func accessSection(listener: ProfileListenerPorts?, sharing: Bool) -> some View {
        if let settingsRows {
            Section {
                 
                 
                settingsRows(Array(ConfigurationSectionKeys.lanShareAccessKeys.dropFirst()), saysScope: true)
            } header: {
                Text("Access Control")
            } footer: {
                if sharing, let listener, listener.credentials == nil {
                    Text("No proxy account is set: anyone on this network can use this proxy.")
                }
            }
        }
    }

     
     
     
     
    @ViewBuilder
    private func reachRows(sharing: Bool) -> some View {
        let reach = model.kernelShareReach(running: isRunningConfiguration)
        let rows = reach.ports.isEmpty ? [] : ProxyShareAddressList.reach(
            lanRows: ProxyShareAddressList.everyRow(hosts: reachableAddresses, interfaces: model.localInterfaces),
            allowsLAN: reach.allowsLAN, bindAddress: kernelShare.listener?.bindAddress)
        ForEach(rows) { row in
            OverviewValueRow(
                title: Self.title(of: row.network),
                value: .verbatim(reach.ports.map { ProxyShareEndpointFormatter.format(address: row.address, port: $0) }
                    .joined(separator: " · ")))
                .textSelection(.enabled)
                 
                .id("core:\(row.address)")
                .accessibilityIdentifier("proxyShare.core.address")
        }
        if reach.allowsLAN, !reach.ports.isEmpty, reachableAddresses.isEmpty {
            ClashStatusMessage(
                text: .copy("No usable Wi-Fi or Personal Hotspot address is available."),
                kind: .information
            )
        }
    }
#endif

     
     
     
     
     
    private var listenerDeviationsSection: some View {
        ConfigDeviationSection(
            report: deviations,
            fields: RunningCoreDeviations.fields(for: [.localProxyListeners]),
            identifierPrefix: "proxyShare.deviation",
            speaksCopy: true
        )
    }

     
     
    private var reachableAddresses: [String] {
        model.reachableAddresses
    }

     
     
     
     
     
     
     
     
     
     
    private var terminalSection: some View {
        Section {
            Picker("Shell", selection: environmentShell) {
                ForEach(ProxyEnvironmentShell.allCases) { shell in
                    Text(verbatim: shell.title).tag(shell)
                }
            }
            .accessibilityIdentifier("proxyShare.environment.shell")
            HStack {
                Text("Environment Variables")
                Spacer()
                Button(action: { copyEnvironment(externalIP: false) }) {
                    if environmentCopied == .local {
                        Text("Copied")
                    } else {
                        Text("Copy")
                    }
                }
                .disabled(model.phase.isBusy || !localLineIsAvailable)
                .accessibilityIdentifier("proxyShare.environment.copy")
#if os(macOS)
                Button(action: { copyEnvironment(externalIP: true) }) {
                    if environmentCopied == .external {
                        Text("Copied")
                    } else {
                        Text("Copy (External IP)")
                    }
                }
                .disabled(model.phase.isBusy || !externalLineIsAvailable)
                .accessibilityIdentifier("proxyShare.environment.copy-external")
#endif
            }
        } header: {
            Text("Terminal")
        }
    }

     
     
     
     
    private var externalLineIsAvailable: Bool {
        guard let listener = model.displayedTerminalListener else { return false }
        return listener.host(forExternalMachine: true, addresses: reachableAddresses) != nil
    }

    private var localLineIsAvailable: Bool {
        guard let listener = model.displayedTerminalListener else { return false }
        return environmentHost(for: listener, externalIP: false) != nil
    }

    private var environmentShell: Binding<ProxyEnvironmentShell> {
        Binding(
            get: { ProxyEnvironmentShell(rawValue: environmentShellRaw) ?? .bash },
            set: { environmentShellRaw = $0.rawValue }
        )
    }

    private func environmentHost(for listener: ProxyTerminalListener, externalIP: Bool) -> String? {
#if os(macOS)
        listener.host(forExternalMachine: externalIP, addresses: reachableAddresses)
#else
        listener.host(forExternalMachine: true, addresses: reachableAddresses)
#endif
    }

    private func copyEnvironment(externalIP: Bool) {
         
         
        guard let listener = model.terminalListener else { return }
        guard let host = environmentHost(for: listener, externalIP: externalIP) else { return }
        let text = ProxyEnvironmentCommand.text(
            shell: environmentShell.wrappedValue,
            endpoint: ProxyEnvironmentEndpoint(
                host: host,
                httpPort: listener.httpPort,
                socksPort: listener.socksPort,
                username: listener.username,
                password: model.terminalPassword(for: listener)
            )
        )
#if canImport(UIKit)
         
         
        CredentialPasteboardWrite.put(text)
#else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#endif
        environmentCopied = externalIP ? .external : .local
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            environmentCopied = nil
        }
    }

    private var actionExplanation: String {
        switch model.phase {
        case .unavailable:
            return "Connect Clash to make the authenticated local proxy available."
        case .failed:
            return "The last change was not confirmed. The Core status will be checked again when this page refreshes."
        case .running:
            return "The VPN stays connected while sharing runs."
        default:
            return "Starting may ask for Local Network access; Clash cannot accept nearby devices without it."
        }
    }

    private var serverExplanation: String {
        if model.status.enabled {
            return "Stop sharing to change the port or credentials."
        }
         
         
         
        return "Both HTTP and SOCKS5 always require the same username and password. Enter the password each time you start sharing — you need to know it to type it into the other device."
    }

     
     
    private var inputsDisabled: Bool {
        model.phase == .unavailable
            || model.phase.isBusy
            || model.status.enabled
    }

    private var isEditingPort: Bool {
        portText != String(model.rememberedPort)
    }

    private func hydrateDraft(overwriteUsername: Bool) {
        if portText.isEmpty || !isEditingPort {
             
            portText = String(model.nativeSharePortSuggestion ?? model.rememberedPort)
        }
        if overwriteUsername {
            username = model.savedUsername
        }
    }

    private func submit() async {
        let submittedPassword = password
        password = ""
        _ = await model.start(
            portText: portText,
            username: username,
            password: submittedPassword
        )
    }
}

#if os(iOS)
 
 
 
 
 
 
struct ProxyShareConfigurationView: View {
    @ObservedObject var profiles: ProfilesViewModel
    @ObservedObject var session: ConfigurationEditorSession
    @Environment(\.proxyShareAppModel) private var appModel

    var body: some View {
        Group {
            if let appModel, profiles.activeProfileID == session.profileID {
                ProxyShareView(model: appModel, configuration: session)
            } else {
                ProxyShareConfigurationPage(profiles: profiles, session: session)
            }
        }
        .configurationPushedAlertHost(session)
    }
}

 
 
private struct ProxyShareConfigurationPage: View {
    @ObservedObject var profiles: ProfilesViewModel
    let session: ConfigurationEditorSession
    @StateObject private var model = ProxyShareModel()
    @State private var bound = false

    private var profile: Profile? { profiles.profiles.first { $0.id == session.profileID } }

    var body: some View {
        ProxyShareView(model: model, configuration: session, isRunningConfiguration: false)
            .onAppear(perform: bind)
             
             
            .task(id: profile?.activeRevision ?? "") {
                if let profile { _ = await profiles.loadEffectiveYAML(for: profile) }
                model.objectWillChange.send()
            }
    }

    private func bind() {
        guard !bound else { return }
        bound = true
        let id = session.profileID
        model.bind(profileYAML: { [weak profiles] in
            guard let profiles, let profile = profiles.profiles.first(where: { $0.id == id }) else { return nil }
            return profiles.effectiveYAMLIfReady(for: profile)
        }, lanListenerPermitted: {
            LocalNetworkPermission.isPermitted(UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite))
        })
        model.bind(kernelShare: profiles.kernelLANShareBinding(for: id))
    }
}

 
 
 
private struct ProxyShareActiveConfiguration<Content: View>: View {
    @ObservedObject var profiles: ProfilesViewModel
    let content: (ConfigurationEditorSession) -> Content
    @StateObject private var session: ConfigurationEditorSession

    init(profiles: ProfilesViewModel, profileID: String, @ViewBuilder content: @escaping (ConfigurationEditorSession) -> Content) {
        _profiles = ObservedObject(wrappedValue: profiles)
        self.content = content
        _session = StateObject(wrappedValue: ConfigurationEditorSession(profileID: profileID, model: profiles))
    }

    private var revision: String { profiles.profiles.first { $0.id == session.profileID }?.activeRevision ?? "" }

    var body: some View {
        content(session)
            .configurationPushedAlertHost(session)
            .task(id: revision) { await session.reload() }
    }
}

 
 
 
 
private struct ProxyShareSettingRows: View {
    @ObservedObject var session: ConfigurationEditorSession
    let keys: [String]
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    var body: some View {
        if session.page == nil || session.awaitsCatalog {
            ProgressView().frame(maxWidth: .infinity)
        } else {
            ForEach(keys, id: \.self) { key in row(key) }
        }
    }

    @ViewBuilder
    private func row(_ key: String) -> some View {
        let document = session.settingsDocument
        let field = session.field(at: [.key(key)], in: document)
        let value = session.settingsValue(at: [key])
        let label = ConfigurationRowLabel(
            title: .verbatim(fieldCopy.entry(forPath: key, language: .init(locale: locale))?.title ?? key),
            value: ConfigurationValueWords.summary(value, field: field, locale: locale, copy: fieldCopy),
            isDefault: value == nil)
        if session.catalog?.platformReason(for: [key], in: document) != nil {
             
            label
        } else {
            ClashNativeNavigationLink {
                ConfigurationValueView(session: session, path: [key])
                    .configurationPushedAlertHost(session)
            } label: { label }
            .accessibilityIdentifier("configuration-editor.key.\(key)")
            .disabled(session.isSaving)
        }
    }
}

 
 
 
 
 
struct ProxyShareListenAddressMenu: Equatable {
    static let defaultTag = "\u{1F}default"
    static let customTag = "\u{1F}custom"

    struct Entry: Equatable, Identifiable {
        let tag: String
        let label: ClashDisplayText
        var id: String { tag }
    }

     
    enum Pick: Equatable { case write(OrderedJSON), useDefault, custom, nothing }

    let entries: [Entry]
     
     
     
     
     
    let selection: String

     
     
     
     
     
     
     
    init(value: OrderedJSON?, field: ConfigurationField?, copy: ConfigurationFieldCopy, locale: Locale, removable: Bool,
         underneath: OrderedJSON? = nil) {
        let written = Self.text(of: value)
        let presets = copy.entry(for: field, locale: locale)?.presets ?? []
        let chosen = written.flatMap {
            ConfigurationChoiceMatch.choice(for: $0, in: presets.map(\.value), caseInsensitive: field?.caseInsensitive == true)
        }
        var entries: [Entry] = []
        if written == nil || removable {
            let words = underneath.map { ConfigurationValueWords.summary($0, field: field, locale: locale, copy: copy, marksDefault: false).resolved(locale: locale) }
                ?? ConfigurationInlineFieldRow.menuDefault(field: field, defaultText: field?.defaultText, copy: copy, locale: locale)
            entries.append(Entry(tag: Self.defaultTag, label: ConfigurationPresetMenuRow.defaultEntry(words, unit: nil)))
        }
        entries += presets.map { Entry(tag: $0.value, label: .verbatim($0.label)) }
        if let written, chosen == nil {
             
            entries.append(Entry(tag: written, label: ConfigurationValueWords.summary(value, field: field, locale: locale, copy: copy)))
        }
        entries.append(Entry(tag: Self.customTag, label: .copy("Custom…")))
        self.entries = entries
        selection = written.map { chosen ?? $0 } ?? Self.defaultTag
    }

     
     
     
    func pick(_ tag: String) -> Pick {
        switch tag {
        case Self.defaultTag: return selection == Self.defaultTag ? .nothing : .useDefault
        case Self.customTag: return .custom
        default: return tag == selection ? .nothing : .write(.string(tag))
        }
    }

     
    static func text(of value: OrderedJSON?) -> String? {
        switch value {
        case .string(let text)?: return text
        case .scalar(let token)?: return ["null", "~", ""].contains(token) ? nil : token
        default: return nil
        }
    }
}

 
 
 
 
struct ProxyShareListenAddressRow: View {
    @ObservedObject var session: ConfigurationEditorSession
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
    @State private var showsCustom = false

    static let key = "bind-address"

    var body: some View {
        let field = session.field(at: [.key(Self.key)], in: session.settingsDocument)
        let title = fieldCopy.title(for: field, key: Self.key, locale: locale)
        if session.page == nil || session.awaitsCatalog {
            ProgressView().frame(maxWidth: .infinity)
        } else if session.catalog?.platformReason(for: [Self.key], in: session.settingsDocument) != nil {
             
            let value = session.settingsValue(at: [Self.key])
            ConfigurationRowLabel(title: .verbatim(title),
                                  value: ConfigurationValueWords.summary(value, field: field, locale: locale, copy: fieldCopy),
                                  isDefault: value == nil)
        } else {
            let menu = Self.menu(for: session, copy: fieldCopy, locale: locale)
            Picker(selection: Binding(get: { menu.selection }, set: { tag in
                if Self.choose(tag, in: session, menu: menu) { showsCustom = true }
            })) {
                ForEach(menu.entries) { Text(clash: $0.label).tag($0.tag) }
            } label: {
                Text(verbatim: title)
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("proxyShare.core.bindAddress")
            .disabled(session.isSaving)
             
            .background(ClashRoutedViewDestination(isPresented: $showsCustom) {
                Self.customPage(session: session)
            }.opacity(0))
        }
    }

     
     
     
     
    static func menu(for session: ConfigurationEditorSession, copy: ConfigurationFieldCopy,
                     locale: Locale) -> ProxyShareListenAddressMenu {
        let value = session.expectedSettingsValue(at: [key])
        let removable = value != nil && (session.page?.ownLayer == nil || session.ownLayerWrites([key]))
        return ProxyShareListenAddressMenu(value: value, field: session.field(at: [.key(key)], in: session.settingsDocument),
                                           copy: copy, locale: locale, removable: removable,
                                           underneath: session.page?.ownLayer == nil ? nil : session.value(at: [key]))
    }

     
     
     
    @discardableResult
    static func choose(_ tag: String, in session: ConfigurationEditorSession, menu: ProxyShareListenAddressMenu) -> Bool {
        switch menu.pick(tag) {
        case .write(let value): session.edit([.set(path: [key], to: value)])
        case .useDefault: session.edit([.remove(path: [key])])
        case .custom: return true
        case .nothing: break
        }
        return false
    }

     
     
    static func customPage(session: ConfigurationEditorSession) -> some View {
        ConfigurationValueView(session: session, path: [key])
            .configurationPushedAlertHost(session)
            .environment(\.configurationValueStartsOnCustom, true)
    }
}

private struct ProxyShareAppModelKey: EnvironmentKey {
    static var defaultValue: ProxyShareModel? { nil }
}

private struct ProxyShareProfilesKey: EnvironmentKey {
    static var defaultValue: ProfilesViewModel? { nil }
}

extension EnvironmentValues {
     
     
     
    var proxyShareAppModel: ProxyShareModel? {
        get { self[ProxyShareAppModelKey.self] }
        set { self[ProxyShareAppModelKey.self] = newValue }
    }

     
     
    var proxyShareProfiles: ProfilesViewModel? {
        get { self[ProxyShareProfilesKey.self] }
        set { self[ProxyShareProfilesKey.self] = newValue }
    }
}
#endif

#if os(macOS)
 
 
 
 
 
 
 
struct ProxyShareSettingsRows: Equatable {
    private let source: ObjectIdentifier
    private let profileID: String?
    private let rows: ([String], Bool) -> AnyView

     
     
     
    init(from source: AnyObject, profileID: String? = nil, rows: @escaping ([String], Bool) -> AnyView) {
        self.source = ObjectIdentifier(source)
        self.profileID = profileID
        self.rows = rows
    }

    func callAsFunction(_ keys: [String], saysScope: Bool = false) -> AnyView { rows(keys, saysScope) }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source && lhs.profileID == rhs.profileID
    }
}

private struct ProxyShareSettingsRowsKey: EnvironmentKey {
    static var defaultValue: ProxyShareSettingsRows? { nil }
}

 
 
 
extension ProxyShareView: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model && lhs.isRunningConfiguration == rhs.isRunningConfiguration
    }
}

extension EnvironmentValues {
     
     
     
    var proxyShareSettingsRows: ProxyShareSettingsRows? {
        get { self[ProxyShareSettingsRowsKey.self] }
        set { self[ProxyShareSettingsRowsKey.self] = newValue }
    }
}

 
 
 
struct ProxyShareMacConfigurationPage: View {
    @ObservedObject var profiles: ProfilesViewModel
    let profileID: String
    @StateObject private var model = ProxyShareModel()
    @State private var bound = false

    private var profile: Profile? { profiles.profiles.first { $0.id == profileID } }

    var body: some View {
        ProxyShareView(model: model, isRunningConfiguration: false).equatable()
            .onAppear(perform: bind)
             
             
            .task(id: profile?.activeRevision ?? "") {
                if let profile { _ = await profiles.loadEffectiveYAML(for: profile) }
                model.objectWillChange.send()
            }
    }

    private func bind() {
        guard !bound else { return }
        bound = true
        let id = profileID
        model.bind(profileYAML: { [weak profiles] in
            guard let profiles, let profile = profiles.profiles.first(where: { $0.id == id }) else { return nil }
            return profiles.effectiveYAMLIfReady(for: profile)
        }, lanListenerPermitted: {
            LocalNetworkPermission.isPermitted(UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite))
        })
        model.bind(kernelShare: profiles.kernelLANShareBinding(for: id))
    }
}
#endif

struct OverviewMoreSettingsCard: View {
    @ObservedObject var proxyShare: ProxyShareModel

    var body: some View {
        ClashOverviewCard {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.standard) {
                OverviewCardHeader(
                    title: "More Settings",
                    symbol: .gearshape,
                    tint: .blue
                )

                ClashRoutedViewLink {
                    ProxyShareView(model: proxyShare)
                } label: {
                    HStack(spacing: ClashTheme.Spacing.row) {
                        ClashIconWell(symbol: .network, tint: .green)
                        VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                            Text("LAN Proxy Share")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text("Authenticated HTTP and SOCKS5 for nearby devices")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: ClashTheme.Spacing.compact)
                        ClashStatusBadge(
                            title: proxyShare.phase == .running ? "On" : "Off",
                            tint: proxyShare.phase == .running ? .green : .gray
                        )
                        Image(systemName: ClashSymbol.chevronForward.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, ClashTheme.Spacing.tight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("overview.moreSettings.proxyShare")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.card.moreSettings")
    }
}


