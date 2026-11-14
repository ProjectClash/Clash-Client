import Clash
import SwiftUI

 
 
 
struct ClashTVRemoteControlCore {
     
     
    var applyInApp: (String) -> String
     
    var generateCertificate: () -> String
     
     
    var askTunnel: () async -> ClashTVTunnelAnswer
}

 
enum ClashTVTunnelAnswer: Equatable {
     
    case notRunning
     
    case status(String)
     
     
     
    case unanswered(String)
}

extension ClashTVRemoteControlCore {
     
    @MainActor
    static func live(_ tunnel: ClashTVTunnelController) -> Self {
        Self(
            applyInApp: { ClashApplyRemoteControl($0) },
            generateCertificate: { ClashGenerateControllerCertificate() },
            askTunnel: { await tunnel.remoteControlStatus() }
        )
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashTVExternalControllerScreen: View {
    @Binding var state: ClashTVProductState
    let core: ClashTVRemoteControlCore
    var defaults: UserDefaults? = UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite)
     
    var hosts: () -> [String] = {
        ProxyShareModel.dialable(LANAddressInventory.current(), keepingSelfAssignedWhenAlone: false)
            .filter { !$0.contains(":") }
    }

    @State private var settings = ClashRemoteControlSettings.default
    @State private var status: ClashRemoteControlStatus?
    @State private var addresses: [String] = []
    @State private var portText = ""
     
     
     
    @FocusState private var editingPort: Bool
    @State private var asksForNewSecret = false
    @State private var asksForNewCertificate = false
     
     
    @State private var tunnelBehind = false
     
     
    @State private var askSerial = 0

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            List {
                Section {
                    ForEach(ClashRemoteControlSettings.Mode.choices(hasLocalConsumers: false), id: \.self) { mode in
                        Button {
                            choose(mode)
                        } label: {
                            HStack {
                                Text(clash: mode.title)
                                Spacer()
                                if settings.mode == mode {
                                    Image(systemName: ClashSymbol.checkmark.rawValue)
                                }
                            }
                        }
                        .accessibilityAddTraits(settings.mode == mode ? .isSelected : [])
                        .accessibilityIdentifier("tvos.externalController.mode.\(mode.rawValue)")
                    }
                } footer: {
                    if let feedback = state.feedback(for: [.remoteControl]) {
                        ClashTVFeedbackLine(presentation: feedback)
                    }
                }
                if settings.mode == .localNetwork {
                     
                     
                    Section {
                        TextField("Port", text: $portText)
                            .keyboardType(.numberPad)
                            .focused($editingPort)
                            .onSubmit(commitPort)
                            .accessibilityIdentifier("tvos.externalController.port")
                    } header: {
                        Text("Port")
                    } footer: {
                         
                        if let feedback = state.feedback(for: [.remoteControlPort]) {
                            ClashTVFeedbackLine(presentation: feedback)
                        }
                    }
                     
                     
                     
                    Section {
                        Button("Make New Secret…") { asksForNewSecret = true }
                            .accessibilityIdentifier("tvos.externalController.newSecret")
                        Button("Make New Certificate…") { asksForNewCertificate = true }
                            .accessibilityIdentifier("tvos.externalController.newCertificate")
                    } footer: {
                        if let feedback = state.feedback(for: [.remoteControlCertificate]) {
                            ClashTVFeedbackLine(presentation: feedback)
                        }
                    }
                }
            }
            .listStyle(.grouped)
            .safeAreaPadding(.horizontal, 44)
            .frame(maxWidth: .infinity)

            details
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.trailing, 44)
        }
        .navigationTitle("External Controller")
         
         
        .alert("Make a New Secret?", isPresented: $asksForNewSecret) {
            Button("Make New Secret", role: .destructive) { makeNewSecret() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Programs using the current secret stop working until they get the new one.")
        }
         
         
        .alert("Make a New Certificate?", isPresented: $asksForNewCertificate) {
            Button("Make New Certificate", role: .destructive) { makeNewCertificate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Devices that trusted the current fingerprint must confirm the new one before they can connect again.")
        }
        .task { load() }
        .onChange(of: editingPort) { _, editing in
            if !editing { commitPortIfTyped() }
        }
        .onDisappear(perform: commitPortIfTyped)
         
         
        .onChange(of: state.stage) { _, _ in askTunnelIfSet() }
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Lets clash-cli on a Mac control Clash on this Apple TV over the local network.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if settings.mode == .localNetwork {
                if let line = Self.statusLine(status, tunnelBehind: tunnelBehind) {
                    Text(clash: line.text)
                        .font(.body)
                        .foregroundStyle(line.failed ? Color.red : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("tvos.externalController.status")
                }
                labeled("Address") {
                    if addresses.isEmpty {
                        Text("Join a Wi-Fi or wired network to be reached.").font(.body).foregroundStyle(.secondary)
                    }
                    ForEach(ClashRemoteControlPresentation.addressLines(for: settings, hosts: addresses), id: \.self) { line in
                        Text(verbatim: line).font(.title3.monospaced())
                            .modifier(TypedWhole())
                            .accessibilityIdentifier("tvos.externalController.address")
                    }
                }
                labeled("Secret") {
                    Text(verbatim: settings.secret).font(.title3.monospaced())
                        .modifier(TypedWhole())
                        .accessibilityIdentifier("tvos.externalController.secret")
                }
                labeled("Certificate Fingerprint") {
                    Text(verbatim: settings.fingerprint).font(.caption.monospaced())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("tvos.externalController.fingerprint")
                }
                Text("On a Mac, give clash-cli this address and secret. The first time, it shows the certificate fingerprint: check it matches the one above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("While this is on, the configuration’s own controller address and secret are not used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func labeled<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).textCase(.uppercase).foregroundStyle(.secondary)
            content()
        }
    }

     
     
     
    private struct TypedWhole: ViewModifier {
        func body(content: Content) -> some View {
            content.lineLimit(1).minimumScaleFactor(0.5)
        }
    }

     

    private func load() {
        settings = ClashRemoteControlSettings.load(from: defaults)
        portText = String(settings.tlsPort)
        addresses = hosts()
        let record = ClashRemoteControlStatus(json: core.applyInApp(settings.coreJSON))
         
         
        status = state.isConnected && hasSetting ? nil : record
        askTunnelIfSet()


    }

     
     
    private func askTunnelIfSet() {
        guard hasSetting else { return }
        Task { await refreshFromTunnel() }
    }

    private var hasSetting: Bool {
        defaults?.string(forKey: ClashRemoteControlSettings.defaultsKey) != nil
    }

    private func choose(_ mode: ClashRemoteControlSettings.Mode) {
        state.beginOperation()
        guard mode != settings.mode else { return }
        var next = settings
        if let error = next.select(mode, certificate: core.generateCertificate) {
            state.post(ClashTVFeedback.couldNotMakeCertificate(reason: error), for: .remoteControl)
            return
        }
        commit(next)
    }

    private func makeNewSecret() {
        state.beginOperation()
        var next = settings
        next.regenerateSecret()
        commit(next)
    }

    private func makeNewCertificate() {
        state.beginOperation()
        switch Self.newCertificate(for: settings, certificate: core.generateCertificate) {
        case .failure(let refused):
            state.post(ClashTVFeedback.couldNotMakeCertificate(reason: refused.reason), for: .remoteControlCertificate)
        case .success(let next):
            commit(next)
        }
    }

    private func commitPort() {
        state.beginOperation()
        switch Self.portOutcome(portText, from: settings) {
        case .unchanged:
            portText = String(settings.tlsPort)
        case .refused:
            state.post(ClashTVFeedback.portOutOfRange, for: .remoteControlPort)
            portText = String(settings.tlsPort)
        case .changed(let next):
            commit(next)
        }
    }

     
     
     
    private func commitPortIfTyped() {
        guard settings.mode == .localNetwork, portText != String(settings.tlsPort) else { return }
        commitPort()
    }

     
     
    private func commit(_ next: ClashRemoteControlSettings) {
        settings = next
        next.save(to: defaults)
        let record = ClashRemoteControlStatus(json: core.applyInApp(next.coreJSON))
         
         
        if !state.isConnected { status = record }
         
         
         
         
        state.remoteControlPendingGeneration = state.stage == .connected || state.stage == .connecting
            ? next.generation : nil
        Task { await refreshFromTunnel() }
    }

    private func refreshFromTunnel() async {
        askSerial &+= 1
        let serial = askSerial
        let answer = await core.askTunnel()
        guard serial == askSerial else { return }
        let read = Self.read(answer, for: settings,
                             changePending: state.remoteControlPendingGeneration == settings.generation)
        if read.showsRecord {
            status = ClashRemoteControlStatus(json: core.applyInApp(settings.coreJSON))
        } else if let running = read.status {
            status = running
        }
        tunnelBehind = read.behind
        if read.settled { state.remoteControlPendingGeneration = nil }
         
         
         
         
        if let problem = read.problem {
            if state.remoteControlProblemNoted != problem {
                state.remoteControlProblemNoted = problem
                state.note(problem: Self.lastProblemLine(problem))
            }
        } else if read.status != nil {
             
            state.remoteControlProblemNoted = nil
        }
    }

     

     
     
    static func lastProblemLine(_ problem: String) -> String {
        ClashTVProvidersScreen.resultLine(String(localized: "External Controller"), problem)
    }

    struct CertificateRefused: Error, Equatable { let reason: String }

     
     
    static func newCertificate(for settings: ClashRemoteControlSettings,
                               certificate: () -> String) -> Result<ClashRemoteControlSettings, CertificateRefused> {
        var next = settings
        if let error = next.adoptCertificate(json: certificate()) { return .failure(CertificateRefused(reason: error)) }
        return .success(next)
    }

    enum PortOutcome: Equatable {
        case unchanged
        case refused
        case changed(ClashRemoteControlSettings)
    }

     
     
     
     
     
     
     
     
    static func portOutcome(_ text: String, from settings: ClashRemoteControlSettings) -> PortOutcome {
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return .unchanged }
         
        guard let port = Int(typed) else { return typed.allSatisfy(\.isNumber) ? .refused : .unchanged }
        guard port != settings.tlsPort else { return .unchanged }
        var next = settings
        next.tlsPort = port
        if next.httpPort == port { next.httpPort = port == 9090 ? 9091 : 9090 }
        next.generation += 1
        if next.portProblem != nil { return .refused }
        return .changed(next)
    }

    struct TunnelRead: Equatable {
         
        var status: ClashRemoteControlStatus?
         
        var showsRecord = false
         
        var behind = false
         
        var problem: String?
         
         
        var settled = false
    }

     
     
     
     
     
     
    static func read(_ answer: ClashTVTunnelAnswer, for settings: ClashRemoteControlSettings,
                     changePending: Bool) -> TunnelRead {
        switch answer {
        case .notRunning:
            return TunnelRead(showsRecord: true, settled: true)
        case .unanswered(let reason):
            return TunnelRead(behind: changePending, problem: changePending ? reason : nil)
        case .status(let json):
            guard let running = ClashRemoteControlStatus(json: json) else {
                return TunnelRead(behind: changePending, problem: changePending ? json : nil)
            }
            let behind = running.rejection == nil && running.generation != settings.generation
            return TunnelRead(status: running, behind: behind,
                              problem: running.rejection ?? running.tls?.error, settled: !behind)
        }
    }

     
     
     
    static func statusLine(_ status: ClashRemoteControlStatus?, tunnelBehind: Bool = false) -> (text: ClashDisplayText, failed: Bool)? {
         
         
         
         
         
        if tunnelBehind { return ("Not applied yet. Press STOP, then START, to apply it.", true) }
        guard let status else { return nil }
        if let rejection = status.rejection { return (.verbatim(rejection), true) }
        if !status.running { return ("Works while Clash is connected", false) }
        if let error = status.tls?.error { return (.verbatim(error), true) }
        return ("Listening.", false)
    }
}
