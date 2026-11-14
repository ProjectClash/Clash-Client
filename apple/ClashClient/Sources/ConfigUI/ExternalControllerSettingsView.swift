import Clash
import ClashClientUI
import SwiftUI
#if os(macOS)
import AppKit
#endif

 
 
struct ExternalControllerCore {
     
     
    var applyInApp: (String) -> String
     
    var generateCertificate: () -> String
     
     
    var askTunnel: () async -> String?
     
     
    var configurationSays: () -> (address: String, secret: String?)? = { nil }
}

extension ExternalControllerCore {
     
     
    static func configurationSays(in yaml: String) -> (address: String, secret: String?)? {
        var address: String?
        var secret: String?
        for line in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let first = line.first, first != " ", first != "\t", first != "#" else { continue }
            if let value = topLevelValue(of: "external-controller", in: line) { address = value }
            if let value = topLevelValue(of: "secret", in: line) { secret = value }
        }
        guard let address, !address.isEmpty else { return nil }
        return (address, secret)
    }

    private static func topLevelValue(of key: String, in line: Substring) -> String? {
        guard line.hasPrefix(key + ":") else { return nil }
        var value = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
        if let quote = value.first, quote == "\"" || quote == "'" {
            value.removeFirst()
            if let end = value.firstIndex(of: quote) { value = String(value[..<end]) }
        } else if let comment = value.range(of: " #") {
            value = String(value[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return value
    }
}

#if os(iOS)
extension ExternalControllerCore {
     
     
    @MainActor
    static func live(vpn: VPNController, profiles: ProfilesViewModel) -> Self {
        Self(
            applyInApp: { ClashApplyRemoteControl($0) },
            generateCertificate: { ClashGenerateControllerCertificate() },
            askTunnel: { [weak vpn] in
                guard let session = await vpn?.session else { return nil }
                 
                 
                 
                for _ in 0..<60 where session.status == .connecting || session.status == .reasserting {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                guard session.status == .connected,
                      let reply = await ClashClient(session: session).send(["cmd": "remoteControl"]) else { return nil }
                return String(data: reply, encoding: .utf8)
            },
            configurationSays: { [weak profiles] in
                guard let profiles,
                      let active = profiles.profiles.first(where: { $0.id == profiles.activeProfileID }),
                      let yaml = profiles.sourceYAML(for: active) else { return nil }
                return configurationSays(in: yaml)
            }
        )
    }
}
#endif

private struct ExternalControllerCoreKey: EnvironmentKey {
    static let defaultValue: ExternalControllerCore? = nil
}

extension EnvironmentValues {
     
     
    var externalControllerCore: ExternalControllerCore? {
        get { self[ExternalControllerCoreKey.self] }
        set { self[ExternalControllerCoreKey.self] = newValue }
    }
}

 
 
 
 
 
 
struct ExternalControllerSettingsView: View {
    let core: ExternalControllerCore
     
     
    var hasLocalConsumers = true
    var defaults: UserDefaults? = UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite)

    @Environment(\.clashFeedback) private var feedback
    @State private var settings = ClashRemoteControlSettings.default
    @State private var status: ClashRemoteControlStatus?
    @State private var hosts: [String] = []
    @State private var confirmsNewSecret = false
     
     
    @State private var confirmsNewCertificate = false
    @State private var certificateFailure: String?
    @State private var httpPortText = ""
    @State private var tlsPortText = ""
     
     
     
    @FocusState private var editingPort: Bool
     
     
    @State private var configurationSays: (address: String, secret: String?)?

    var body: some View {
        page
            .onAppear(perform: load)
            .onDisappear(perform: commitPorts)
            .onChange(of: editingPort) { editing in if !editing { commitPorts() } }
            .confirmationDialog(Text("Make a New Secret?"), isPresented: $confirmsNewSecret, titleVisibility: .visible) {
                Button("Make New Secret", role: .destructive) { regenerateSecret() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Programs using the current secret stop working until they get the new one.")
            }
            .confirmationDialog(Text("Make a New Certificate?"), isPresented: $confirmsNewCertificate,
                                titleVisibility: .visible) {
                Button("Make New Certificate", role: .destructive) { regenerateCertificate() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Devices that trusted the current fingerprint must trust the new one before they connect again.")
            }
    }

    @ViewBuilder
    private var page: some View {
#if os(macOS)
        macPage
#else
        touchPage
#endif
    }

    private var touchPage: some View {
        Form {
            Section {
                Picker(selection: Binding(get: { settings.mode }, set: { choose($0) })) {
                    ForEach(ClashRemoteControlSettings.Mode.choices(hasLocalConsumers: hasLocalConsumers), id: \.self) { mode in
                        Text(clash: mode.title).tag(mode)
                    }
                } label: {
                    Text("External Controller")
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .accessibilityIdentifier("external-controller.mode")
            } footer: {
                Text("Lets clash-cli on a Mac and AI assistants control Clash on this device.")
            }

            if settings.mode != .configuration {
                addressSection
                secretSection
                portsSection
                if let says = configurationSays {
                    Section {
                         
                        HStack {
                            Text("Configuration Says")
                            Spacer(minLength: 8)
                            Text(verbatim: says.address).font(.callout.monospaced()).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("external-controller.configuration-says")
                    } footer: {
                        Text("While this is on, the configuration’s own controller address and secret are not used.")
                    }
                }
            }
        }
        .clashPageTitle(.copy("External Controller"))
#if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editingPort = false }
                    .accessibilityIdentifier("external-controller.port.done")
            }
        }
#endif
    }

     

    private var addressSection: some View {
        Section {
            let lines = ClashRemoteControlPresentation.addressLines(for: settings, hosts: hosts)
            if lines.isEmpty {
                Text("Join a Wi-Fi or wired network to be reached.")
                    .foregroundStyle(.secondary)
            }
            ForEach(lines, id: \.self) { line in
                copyRow(Text(verbatim: line), value: line, identifier: "external-controller.address")
            }
            if settings.mode == .localNetwork, !settings.fingerprint.isEmpty {
                copyRow(Text(verbatim: settings.fingerprint).font(.caption.monospaced()), value: settings.fingerprint,
                        identifier: "external-controller.fingerprint", title: "Certificate Fingerprint")
                 
                 
                Button("Make New Certificate…") { confirmsNewCertificate = true }
                    .accessibilityIdentifier("external-controller.certificate.regenerate")
                if let certificateFailure {
                    ClashStatusMessage(text: .verbatim(certificateFailure), kind: .error)
                        .accessibilityIdentifier("external-controller.certificate.failure")
                }
            }
            Button {
                ClashClipboard.copy(ClashRemoteControlPresentation.command(for: settings, host: hosts.first),
                                    feedback: feedback, noun: "Terminal Command", operation: "external-controller.copy-command")
            } label: {
                Label("Copy Terminal Command", systemImage: ClashSymbol.docOnDoc.name)
            }
            .accessibilityIdentifier("external-controller.copy-command")
            if let status, let line = statusLine(status) {
                ClashStatusMessage(text: line.text, kind: line.kind)
                    .accessibilityIdentifier("external-controller.status")
            }
        } header: {
            Text("Address")
        } footer: {
            Text("Anyone with the secret can fully control Clash, including LAN sharing and the outbound mode.")
        }
    }

    private var secretSection: some View {
        Section {
             
            copyRow(Text(verbatim: settings.secret).font(.callout.monospaced()), value: settings.secret,
                    identifier: "external-controller.secret", oneLine: true)
            Button("Make New Secret…") { confirmsNewSecret = true }
                .accessibilityIdentifier("external-controller.secret.regenerate")
        } header: {
            Text("Secret")
        }
    }

#if os(macOS)
     

     
     
     
     
     
    private var macPage: some View {
        ClashMacSettingsFormContainer {
            Section {
                Picker(selection: Binding(get: { settings.mode }, set: { choose($0) })) {
                    ForEach(ClashRemoteControlSettings.Mode.choices(hasLocalConsumers: hasLocalConsumers), id: \.self) { mode in
                        Text(clash: mode.title).tag(mode)
                    }
                } label: {
                    Text("Controller")
                }
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("external-controller.mode")
            } footer: {
                Text(clash: macModeFooter)
            }

            if settings.mode != .configuration {
                Section {
                    let lines = ClashRemoteControlPresentation.addressLines(for: settings, hosts: hosts)
                    if lines.isEmpty {
                        LabeledContent("Address") {
                            Text("Join a Wi-Fi or wired network to be reached.").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(lines, id: \.self) { line in
                        macValueRow("Address", value: line, identifier: "external-controller.address")
                    }
                    if settings.mode == .localNetwork, !settings.fingerprint.isEmpty {
                         
                         
                        LabeledContent("Certificate Fingerprint") {
                            Text(verbatim: Self.fingerprintEnds(settings.fingerprint))
                                .foregroundStyle(.secondary)
                                .help(settings.fingerprint)
                            MacCopyButton(value: settings.fingerprint, identifier: "external-controller.fingerprint")
                            Button("Make New Certificate…") { confirmsNewCertificate = true }
                                .buttonStyle(.bordered)
                                .tint(.primary)
                                .accessibilityIdentifier("external-controller.certificate.regenerate")
                        }
                         
                        if let certificateFailure {
                            ClashStatusMessage(text: .verbatim(certificateFailure), kind: .error)
                                .accessibilityIdentifier("external-controller.certificate.failure")
                        }
                    }
                    LabeledContent("Secret") {
                        macValue(settings.secret)
                        MacCopyButton(value: settings.secret, identifier: "external-controller.secret")
                        Button("Make New Secret…") { confirmsNewSecret = true }
                            .buttonStyle(.bordered)
                            .tint(.primary)
                            .accessibilityIdentifier("external-controller.secret.regenerate")
                    }
                    if let status, let line = statusLine(status) {
                        LabeledContent("Status") {
                            ClashStatusMessage(text: line.text, kind: line.kind)
                        }
                        .accessibilityIdentifier("external-controller.status")
                    }
                    LabeledContent("Terminal Command") {
                        MacCopyButton(value: ClashRemoteControlPresentation.command(for: settings, host: hosts.first),
                                      identifier: "external-controller.copy-command", title: "Copy")
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Anyone with the secret can fully control Clash, including LAN sharing and the outbound mode.")
                }

                Section {
                    macPortRow("HTTP Port", text: $httpPortText, identifier: "external-controller.port.http")
                    if settings.mode == .localNetwork {
                        macPortRow("TLS Port", text: $tlsPortText, identifier: "external-controller.port.tls")
                    }
                } header: {
                    Text("Ports")
                } footer: {
                    if let problem = settings.portProblem {
                        ClashStatusMessage(text: problem == .same ? "The two ports must differ." : "Use a port from 1024 to 65535.",
                                           kind: .error)
                    }
                }

                if let says = configurationSays {
                    Section {
                        LabeledContent("Configuration Says") { macValue(says.address) }
                            .accessibilityIdentifier("external-controller.configuration-says")
                    } footer: {
                        Text("While this is on, the configuration’s own controller address and secret are not used.")
                    }
                }
            }

            commandLineToolSection
        }
        .navigationTitle(Text(clash: .copy("External Controller")))
        .clashDetailPageInsets()
    }

     
    private var macModeFooter: ClashDisplayText {
        switch settings.mode {
        case .configuration: return .copy("Clash uses the controller the configuration sets, if any.")
        case .thisDevice: return .copy("Programs on this Mac reach Clash at 127.0.0.1.")
        case .localNetwork: return .copy("Programs on this Mac and devices on this network reach Clash.")
        }
    }

     
     
     
    private var commandLineToolSection: some View {
        Section {
            let tool = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/clash-cli")
            if FileManager.default.isExecutableFile(atPath: tool.path) {
                LabeledContent("Location") {
                     
                     
                    Text(verbatim: tool.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 420, alignment: .trailing)
                        .help(tool.path)
                    MacCopyButton(value: tool.path, identifier: "external-controller.cli.path")
                }
                LabeledContent("Install Command") {
                    MacCopyButton(value: ClashRemoteControlPresentation.installCommand(toolPath: tool.path),
                                  identifier: "external-controller.cli.install", title: "Copy")
                }
            } else {
                Text("This build doesn’t include clash-cli.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("external-controller.cli.missing")
            }
        } header: {
            Text("Command-Line Tool")
        } footer: {
            Text("Paste the install command into Terminal once, then run clash-cli from any folder.")
        }
    }

    private func macValue(_ value: String) -> some View {
        Text(verbatim: value)
            .font(ClashMacSettingsType.mono)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }

     
    private func macValueRow(_ title: LocalizedStringKey, value: String, identifier: String) -> some View {
        LabeledContent(title) {
            macValue(value)
            MacCopyButton(value: value, identifier: identifier)
        }
    }

     
    static func fingerprintEnds(_ fingerprint: String) -> String {
        let bytes = fingerprint.split(separator: ":").filter { $0.count == 2 }
        guard bytes.count > 8 else { return fingerprint }
        return bytes.prefix(4).joined(separator: ":") + " … " + bytes.suffix(4).joined(separator: ":")
    }

    private func macPortRow(_ title: LocalizedStringKey, text: Binding<String>, identifier: String) -> some View {
        LabeledContent(title) {
            TextField(text: text, prompt: nil) { Text(title) }
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .font(ClashMacSettingsType.mono)
                .frame(width: 72)
                .focused($editingPort)
                .onSubmit(commitPorts)
                .accessibilityIdentifier(identifier)
        }
    }
#endif

    private var portsSection: some View {
        Section {
            portField("HTTP Port", text: $httpPortText, identifier: "external-controller.port.http")
            if settings.mode == .localNetwork {
                portField("TLS Port", text: $tlsPortText, identifier: "external-controller.port.tls")
            }
            if let problem = settings.portProblem {
                ClashStatusMessage(text: problem == .same ? "The two ports must differ." : "Use a port from 1024 to 65535.",
                                   kind: .error)
            }
        } header: {
            Text("Ports")
        }
    }

    private func portField(_ title: LocalizedStringKey, text: Binding<String>, identifier: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            TextField(title, text: text)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
#if os(iOS)
                .keyboardType(.numberPad)
#endif
                .focused($editingPort)
                .onSubmit(commitPorts)
                .accessibilityIdentifier(identifier)
        }
    }

     
     
    private func copyRow(_ content: Text, value: String, identifier: String, title: LocalizedStringKey? = nil,
                         oneLine: Bool = false) -> some View {
        Button {
            ClashClipboard.copy(value, feedback: feedback, operation: identifier)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let title { Text(title).font(.caption).foregroundColor(.secondary) }
                    content.foregroundColor(.primary)
                        .lineLimit(oneLine ? 1 : nil)
                        .minimumScaleFactor(oneLine ? 0.5 : 1)
                }
                Spacer(minLength: 8)
                Image(systemName: ClashSymbol.docOnDoc.name).foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Copies it"))
        .accessibilityIdentifier(identifier)
    }

     

    private func load() {
        settings = ClashRemoteControlSettings.load(from: defaults)
        httpPortText = String(settings.httpPort)
        tlsPortText = String(settings.tlsPort)
        hosts = ProxyShareModel.dialable(LANAddressInventory.current(), keepingSelfAssignedWhenAlone: false)
            .filter { !$0.contains(":") }
        configurationSays = core.configurationSays()
        status = ClashRemoteControlStatus(json: core.applyInApp(settings.coreJSON))
        Task { await refreshFromTunnel() }
    }

    private func choose(_ mode: ClashRemoteControlSettings.Mode) {
        var next = settings
        if let error = next.select(mode, certificate: core.generateCertificate) {
            feedback?.show(.error(title: .copy("Couldn’t Make a Certificate"), message: .verbatim(error),
                                  accessibilityIdentifier: "feedback.external-controller"),
                           operation: "external-controller.mode")
            return
        }
        commit(next)
    }

    private func regenerateCertificate() {
        var next = settings
        if let error = next.adoptCertificate(json: core.generateCertificate()) {
            certificateFailure = error
            return
        }
        certificateFailure = nil
        commit(next)
    }

    private func regenerateSecret() {
        var next = settings
        next.regenerateSecret()
        commit(next)
    }

    private func commitPorts() {
        var next = settings
        next.httpPort = Int(httpPortText) ?? settings.httpPort
        next.tlsPort = Int(tlsPortText) ?? settings.tlsPort
        guard next.httpPort != settings.httpPort || next.tlsPort != settings.tlsPort else { return }
        next.generation += 1
        if next.portProblem != nil {
            settings.httpPort = next.httpPort
            settings.tlsPort = next.tlsPort
            return
        }
        commit(next)
    }

     
    private func commit(_ next: ClashRemoteControlSettings) {
        settings = next
        next.save(to: defaults)
        status = ClashRemoteControlStatus(json: core.applyInApp(next.coreJSON))
        Task { await refreshFromTunnel() }
    }

    @MainActor
    private func refreshFromTunnel() async {
        guard let answer = await core.askTunnel(), let running = ClashRemoteControlStatus(json: answer) else { return }
        status = running
    }

    private func statusLine(_ status: ClashRemoteControlStatus) -> (text: ClashDisplayText, kind: ClashStatusKind)? {
        if let rejection = status.rejection { return (.verbatim(rejection), .error) }
        if !status.running { return (.copy("Starts with the tunnel."), .information) }
        if let error = status.http?.error ?? status.tls?.error { return (.verbatim(error), .error) }
        return (.copy("Listening."), .success)
    }
}

#if os(macOS)
 
 
 
private struct MacCopyButton: View {
    let value: String
    let identifier: String
     
     
    var title: LocalizedStringKey?
    @State private var copied = false
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: copy) {
            if let title {
                Text(copied ? "Copied" : title)
            } else {
                Image(systemName: copied ? "checkmark" : ClashSymbol.docOnDoc.name)
                    .foregroundStyle(copied ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                    .accessibilityLabel(Text(copied ? "Copied" : "Copy"))
            }
        }
        .buttonStyle(title == nil ? AnyButtonStyle(.borderless) : AnyButtonStyle(.bordered))
        .tint(.primary)
        .help(Text(copied ? "Copied" : "Copy"))
        .accessibilityIdentifier(identifier)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copied = true
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: ClashCopy.string("Copied", locale: locale),
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copied = false
        }
    }
}

 
private struct AnyButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: PrimitiveButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
#endif
