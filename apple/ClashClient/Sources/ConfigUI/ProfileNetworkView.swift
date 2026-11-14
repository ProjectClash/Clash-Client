import ClashClientUI
import SwiftUI

 
struct ProfileNetworkSettingsView: View {
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
     
     
     
     
     
     
     
     
     
     
     
    @Environment(\.locale) private var locale
    let save: (ProfileNetworkDraft) throws -> Void

     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @State private var draft: ProfileNetworkDraft
     
     
     
    @State private var openedWith: ProfileNetworkDraft
    @State private var timePortText: String
    @State private var timeIntervalText: String
    @State private var error = ""
    private let profileName: String
    private let ownsNavigationContainer: Bool
     
     
     
     
    private let landsOnSniffer: Bool
     
     
    private let profileForDeviations: Profile
    @State private var deviations: ConfigDeviationReport?

     
     
     
     
    init(
        profile: Profile,
        draft: ProfileNetworkDraft? = nil,
        ownsNavigationContainer: Bool = true,
        landsOnSniffer: Bool = false,
        save: @escaping (ProfileNetworkDraft) throws -> Void
    ) {
        let draft = draft ?? ProfileNetworkDraft(profile: profile, sourceYAML: nil)
        self.landsOnSniffer = landsOnSniffer
        self.save = save
        profileForDeviations = profile
        profileName = profile.label
        self.ownsNavigationContainer = ownsNavigationContainer
        _draft = State(initialValue: draft)
        _openedWith = State(initialValue: draft)
        _timePortText = State(initialValue: draft.timePort.map(String.init) ?? "")
        _timeIntervalText = State(
            initialValue: draft.timeIntervalMinutes.map(String.init) ?? ""
        )
    }

     
     
     
    static func opening(
        profile: Profile,
        sourceYAML: String?,
        ownsNavigationContainer: Bool = true,
        landsOnSniffer: Bool = false,
        save: @escaping (ProfileNetworkDraft) throws -> Void
    ) -> some View {
        ProfileEditorDraftLoader(identifier: "profile-network.loading") {
            ProfileNetworkDraft(profile: profile, sourceYAML: sourceYAML)
        } content: { draft in
            ProfileNetworkSettingsView(profile: profile, draft: draft,
                                       ownsNavigationContainer: ownsNavigationContainer, landsOnSniffer: landsOnSniffer, save: save)
        }
    }

     
    private var hub: some View {
        ClashMacSettingsFormContainer {
            Section {
                sectionRow(.sniffer) {
                    DNSHubRow(title: "Sniffer",
                              detail: "Finds the domain behind each connection before rules run",
                              value: snifferSummary)
                }
                .accessibilityIdentifier("profile-network.traffic-recognition")
            } footer: {
                Text(
                    "Sniffer discovers domains before this profile's rules are evaluated."
                )
            }

            Section {
                sectionRow(.ntp) {
                    DNSHubRow(title: "NTP",
                              detail: "Trusted time for protocol handshakes",
                              value: ntpSummary)
                }
                .accessibilityIdentifier("profile-network.time-synchronization")
            }

            if !error.isEmpty {
                Section {
                    ClashStatusMessage(text: .copy(error), kind: .error)
                }
            }

             
             
             
             
             
             
             
            ConfigDeviationSection(
                report: deviations,
                fields: RunningCoreDeviations.fields(
                    for: [.trafficRecognition, .timeSynchronization]
                ),
                identifierPrefix: "profile-network.deviation"
            )
        }
        .clashPageTitle("Sniffer & NTP")
    }

     
     
     
     
     
     
     
     
     
    private var landedOnSniffer: some View {
        ProfileSnifferSettingsBody(draft: $draft, deviations: ConfigDeviationSection(
            report: deviations,
            fields: RunningCoreDeviations.fields(for: [.trafficRecognition]),
            identifierPrefix: "profile-network.deviation"
        ))
        .alert(Text(clash: .copy(error)), isPresented: Binding(get: { !error.isEmpty }, set: { if !$0 { error = "" } })) {
            Button("OK") { error = "" }
        }
    }

     
    @State private var sectionSelection: ProfileNetworkRoute?

     
     
     
    @ViewBuilder
    private func sectionRow<RowLabel: View>(
        _ route: ProfileNetworkRoute,
        @ViewBuilder label: () -> RowLabel
    ) -> some View {
#if os(macOS)
        Button {
            sectionSelection = route
        } label: {
             
             
             
            HStack(spacing: 6) {
                label()
                Image(systemName: ClashSymbol.chevronForward.rawValue)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
#else
        ClashStableNavigationLink(value: route) {
            routeDestination(route)
        } label: {
            label()
        }
#endif
    }

    private func modalTitle(for route: ProfileNetworkRoute) -> String {
        switch route {
        case .sniffer: "Sniffer"
        case .ntp: "NTP"
        }
    }

    @ViewBuilder
    private func routeDestination(_ route: ProfileNetworkRoute) -> some View {
        switch route {
        case .sniffer:
            ProfileSnifferSettingsView(draft: $draft)
        case .ntp:
            ProfileNTPSettingsView(
                draft: $draft,
                portText: $timePortText,
                intervalText: $timeIntervalText
            )
        }
    }

    var body: some View {
        ClashFeatureNavigationContainer(
            ownsNavigationContainer: ownsNavigationContainer
        ) {
            Group {
                if landsOnSniffer {
                    landedOnSniffer
                } else {
                    hub
                }
            }
             
             
             
             
             
             
             
             
            .clashStableNavigationDestination(for: ProfileNetworkRoute.self) { route in
                routeDestination(route)
            }
            .clashFeaturePresentation(
                ownsNavigationContainer: ownsNavigationContainer
            )
#if os(macOS)
             
             
             
             
            .clashProductModal(item: $sectionSelection, role: .form) { route in
                ClashFeatureNavigationContainer {
                     
                     
                     
                     
                     
                     
                    routeDestination(route)
                         
                         
                         
                         
                         
                         
                         
                         
                         
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            ClashModalActionBar(primaryTitle: "Save",
                                primaryDisabled: draft == openedWith,
                                onPrimary: { if commit() { sectionSelection = nil } })
                        }
                         
                         
                         
                         
                         
                         
                        .clashRegistersDeparture(
                            isDirty: draft != openedWith,
                            save: { completion in
                                completion(commit())
                            },
                            discard: { draft = openedWith }
                        )
                        .clashProductModalRoot(title: .copy(modalTitle(for: route)))
                }
                .clashPageSizedSheet()
            }
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if ownsNavigationContainer {
                        Button("Cancel") { closePage() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                     
                     
                    if !insideProductModal {
                        ClashSaveButton { persist() }
                            .accessibilityIdentifier("profile-network.save")
                    }
                }
            }
        }
        .task(id: RunningCoreDeviations.taskKey(for: profileForDeviations)) {
            let profile = profileForDeviations
             
             
             
             
            let derived = await Task.detached(priority: .userInitiated) {
                () -> (ConfigDeviationReport?, Set<String>?, String?) in
                let sidecar = RunningCoreDeviations.sidecarYAML(for: profile)
                let finished = sidecar.flatMap {
                    try? ProfileRuntimeConfigBuilder.buildProductionStages(
                        raw: $0, profile: profile, applyProxyChain: false, scripts: .silent
                    ).finished()
                }
                let report = finished.flatMap {
                    try? ConfigTransforms.configDeviations(
                        configContent: $0, targetProfile: clashAppleRuntimeProfile.rawValue
                    )
                }
                return (
                    report,
                    finished.map(ProfileNetworkDraft.sniffProtocols(in:)),
                    RunningCoreDeviations.baseDocument(profile: profile, sidecarYAML: sidecar)
                )
            }.value
            deviations = derived.0
            draft.mergedDocumentSniffProtocols = derived.1
             
             
             
            if let base = derived.2 { draft.reseedInheritedBases(fromBaseDocument: base) }
        }
        .clashMacProductModalBar {
            if insideProductModal {
                 
                ClashModalActionBar(primaryTitle: "Save",
                    primaryDisabled: draft == openedWith,
                    onPrimary: persist)
            }
        }
         
         
         
        .clashPageProbe("profile-network")
        .accessibilityIdentifier("profile-network.screen")
        .clashCapturesDismiss(dismiss)
    }

     
     
    private var snifferSummary: String {
         
         
        let resolved = InheritedBool(
            base: draft.inheritedBase("sniffer.enable"),
            override: draft.trafficRecognition.boolValue,
            upstreamDefault: UpstreamBoolDefault.value(for: "sniffer.enable")
        )
        let state = ClashCopy.string(resolved.primaryTitle.rawValue, locale: locale)
        let details = draft.customizedSnifferFieldCount
         
        return details == 0
            ? state
            : ClashCopy.format("%@ · %d modified", locale: locale, state, details)
    }

    private var ntpSummary: String {
        let count = (draft.timeSynchronization == .profileDefault ? 0 : 1)
            + (draft.timeServer == nil ? 0 : 1)
            + (timePortText.isEmpty ? 0 : 1)
            + (timeIntervalText.isEmpty ? 0 : 1)
            + (draft.timeDialerProxy == nil ? 0 : 1)
         
         
         
         
        return count == 0
            ? ClashCopy.string("Following the profile", locale: locale)
            : ClashCopy.format("%d overriding the profile", locale: locale, count)
    }

    private func persist() {
        if commit() { closePage() }
    }

     
     
     
     
    @discardableResult
    private func commit() -> Bool {
        do {
            draft.timePort = try Self.positiveNumber(
                timePortText,
                invalid: .invalidTimePort
            )
            draft.timeIntervalMinutes = try Self.positiveNumber(
                timeIntervalText,
                invalid: .invalidTimeInterval
            )
            try save(draft)
            openedWith = draft
            return true
        } catch let bounded as ProfileNetworkDraftError {
            error = bounded.localizedDescription
        } catch {
            self.error = "Network settings could not be saved. The previous configuration is still available."
        }
        return false
    }

    private static func positiveNumber(
        _ text: String,
        invalid error: ProfileNetworkDraftError
    ) throws -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed), value > 0 else { throw error }
        return value
    }

     
     
    private func closePage() {
        dismiss.closeModalOrDismiss()
    }
}

 
 
private struct ProfileNTPSettingsView: View {
    @Binding var draft: ProfileNetworkDraft
    @Binding var portText: String
    @Binding var intervalText: String

    var body: some View {
#if os(macOS)
         
         
         
        ProfileNTPDeferredHost(
            draft: $draft,
            portText: $portText,
            intervalText: $intervalText
        )
#else
        ProfileNTPSettingsBody(
            draft: $draft,
            portText: $portText,
            intervalText: $intervalText
        )
#endif
    }
}

#if os(macOS)
private struct ProfileNTPDeferredHost: View {
    @Binding var draft: ProfileNetworkDraft
    @Binding var portText: String
    @Binding var intervalText: String
    @State private var localDraft: ProfileNetworkDraft
    @State private var localPort: String
    @State private var localInterval: String

    init(
        draft: Binding<ProfileNetworkDraft>,
        portText: Binding<String>,
        intervalText: Binding<String>
    ) {
        _draft = draft
        _portText = portText
        _intervalText = intervalText
        _localDraft = State(initialValue: draft.wrappedValue)
        _localPort = State(initialValue: portText.wrappedValue)
        _localInterval = State(initialValue: intervalText.wrappedValue)
    }

    var body: some View {
        ProfileNTPSettingsBody(
            draft: $localDraft,
            portText: $localPort,
            intervalText: $localInterval
        )
        .onDisappear {
            draft = localDraft
            portText = localPort
            intervalText = localInterval
        }
    }
}
#endif

private struct ProfileNTPSettingsBody: View {
    @Binding var draft: ProfileNetworkDraft
    @Binding var portText: String
    @Binding var intervalText: String

    private static let keyPaths = ["ntp.enable", "ntp.server", "ntp.port", "ntp.interval", "ntp.dialer-proxy"]

    private var restoreDefaults: (() -> Void)? {
        guard draft.hasOverrides(keyPaths: Self.keyPaths) || !portText.isEmpty || !intervalText.isEmpty
        else { return nil }
        return {
            draft = draft.clearingOverrides(keyPaths: Self.keyPaths)
            portText = ""
            intervalText = ""
        }
    }

    var body: some View {
        ClashMacSettingsFormContainer(
            restoreDefaults: restoreDefaults
        ) {
            Section {
                DNSFieldRows.overrideMenuRow(
                    "NTP",
                    $draft.timeSynchronization,
                    inherited: draft.inheritedBase("ntp.enable"),
                    upstreamDefault: UpstreamBoolDefault.value(for: "ntp.enable"),
                    identifier: "profile-network.time.enabled"
                )
                optionalTextRow(
                    "Server",
                    value: $draft.timeServer,
                    inherited: draft.inheritedTextBase("ntp.server"),
                    upstreamDefault: UpstreamTextDefault.pinned(for: "ntp.server"),
                    identifier: "profile-network.time.server"
                )
                numberRow(
                    "Port",
                    text: $portText,
                    inherited: draft.inheritedNumberBase("ntp.port"),
                    upstreamDefault: UpstreamNumberDefault.pinned(for: "ntp.port"),
                    suffix: nil,
                    identifier: "profile-network.time.port"
                )
                numberRow(
                    "Sync every",
                    text: $intervalText,
                    inherited: draft.inheritedNumberBase("ntp.interval"),
                    upstreamDefault: UpstreamNumberDefault.pinned(for: "ntp.interval"),
                    suffix: "min",
                    identifier: "profile-network.time.interval"
                )
            } footer: {
                Text("Core applies the measured offset to protocol handshakes only.")
            }

            Section {
                optionalTextRow(
                    "Route",
                    value: $draft.timeDialerProxy,
                    inherited: draft.inheritedTextBase("ntp.dialer-proxy"),
                    upstreamDefault: UpstreamTextDefault.pinned(for: "ntp.dialer-proxy"),
                    identifier: "profile-network.time.route"
                )
            } footer: {
                Text("NTP dials its server directly, before rules — Route forces it through a named group or node instead.")
            }

            Section {
                OverviewValueRow(title: "System clock", value: "Never changed")
                    .accessibilityLabel(Text(ClashCopy.key("System clock")))
                    .accessibilityValue(Text(ClashCopy.key("Never changed")))
                    .accessibilityIdentifier("profile-network.time.write-system")
            } footer: {
                Text("The system does not grant that right.")
            }
        }
        
        .clashPageTitle("NTP")
        .clashDetailPageInsets()
        .accessibilityIdentifier("profile-network.time.screen")
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
struct ProfileSnifferSettingsView: View {
    @Binding var draft: ProfileNetworkDraft

    var body: some View {
#if os(macOS)
        ClashDeferredDraftHost(source: $draft) { local in
            ProfileSnifferSettingsBody(draft: local)
        }
#else
        ProfileSnifferSettingsBody(draft: $draft)
#endif
    }
}

private struct ProfileSnifferSettingsBody: View {
     
     
     
    @Environment(\.locale) private var locale
    @Binding var draft: ProfileNetworkDraft
     
     
     
    var deviations: ConfigDeviationSection? = nil

     
     
     
    private var overallOverrideDestination: Bool {
        InheritedBool(
            base: draft.inheritedBase("sniffer.override-destination"),
            override: draft.overrideDestination.boolValue,
            upstreamDefault: UpstreamBoolDefault.value(for: "sniffer.override-destination")
        ).resolved
    }

    private static let keyPaths = [
        "sniffer.enable", "sniffer.force-dns-mapping", "sniffer.parse-pure-ip", "sniffer.override-destination",
    ]

    private var restoreDefaults: (() -> Void)? {
        guard draft.hasOverrides(keyPaths: Self.keyPaths) else { return nil }
        return { draft = draft.clearingOverrides(keyPaths: Self.keyPaths) }
    }

    var body: some View {
        ClashMacSettingsFormContainer(
            restoreDefaults: restoreDefaults
        ) {
            Section {
                DNSFieldRows.overrideMenuRow(
                    "Sniffer",
                    $draft.trafficRecognition,
                    inherited: draft.inheritedBase("sniffer.enable"),
                    upstreamDefault: UpstreamBoolDefault.value(for: "sniffer.enable"),
                    identifier: "profile-network.sniffer.enable"
                )
            } footer: {
                Text("Finds the real domain, so rules match names instead of bare IPs.")
            }

            Section {
                DNSFieldRows.overrideMenuRow(
                    "Sniff DNS-mapped traffic",
                    $draft.forceDNSMapping,
                    inherited: draft.inheritedBase("sniffer.force-dns-mapping"),
                    upstreamDefault: UpstreamBoolDefault.value(for: "sniffer.force-dns-mapping"),
                    identifier: "profile-network.sniffer.force-dns-mapping"
                )
                DNSFieldRows.overrideMenuRow(
                    "Sniff pure-IP traffic",
                    $draft.parsePureIP,
                    inherited: draft.inheritedBase("sniffer.parse-pure-ip"),
                    upstreamDefault: UpstreamBoolDefault.value(for: "sniffer.parse-pure-ip"),
                    identifier: "profile-network.sniffer.parse-pure-ip"
                )
                DNSFieldRows.overrideMenuRow(
                    "Dial the sniffed domain",
                    $draft.overrideDestination,
                    inherited: draft.inheritedBase("sniffer.override-destination"),
                    upstreamDefault: UpstreamBoolDefault.value(for: "sniffer.override-destination"),
                    identifier: "profile-network.sniffer.override-destination"
                )
            } footer: {
                Text("Dialing the sniffed domain hands the outbound the name, not the IP it arrived with.")
            }

            protocolSection(
                title: "HTTP",
                draft: $draft.http,
                defaultPorts: "80, 8080-8880",
                builtInPorts: "80",
                identifierFragment: "http"
            )
            protocolSection(
                title: "TLS",
                draft: $draft.tls,
                defaultPorts: "443, 8443",
                builtInPorts: "443",
                identifierFragment: "tls"
            )
            protocolSection(
                title: "QUIC",
                draft: $draft.quic,
                defaultPorts: "443",
                builtInPorts: "443",
                identifierFragment: "quic"
            )

            Section {
                listRow(
                    "Always sniff · Domain",
                    items: $draft.forceDomains,
                    itemTitle: "Domain",
                    noun: "patterns",
                    placeholder: "+.example.com",
                    footer: "Wildcards work: +.example.com covers every name under it.",
                    identifier: "profile-network.sniffer.force-domains"
                )
                listRow(
                    "Never sniff · Domain",
                    items: $draft.skipDomains,
                    itemTitle: "Domain",
                    noun: "patterns",
                    placeholder: "+.private.example",
                    footer: "Wildcards work: +.example.com covers every name under it.",
                    identifier: "profile-network.sniffer.skip-domains"
                )
                listRow(
                    "Never sniff · Source range",
                    items: $draft.skipSourceAddresses,
                    itemTitle: "Address",
                    noun: "ranges",
                    placeholder: "192.0.2.0/24",
                    footer: "Connections from these addresses are never sniffed.",
                    validate: addressPrefixError,
                    identifier: "profile-network.sniffer.skip-source-addresses"
                )
                listRow(
                    "Never sniff · Destination range",
                    items: $draft.skipDestinationAddresses,
                    itemTitle: "Address",
                    noun: "ranges",
                    placeholder: "2001:db8::/32",
                    footer: "Connections to these addresses are never sniffed.",
                    validate: addressPrefixError,
                    identifier: "profile-network.sniffer.skip-destination-addresses"
                )
            }

            Section {
                StringListEditor(
                    items: $draft.legacySniffing,
                    itemTitle: "Protocol",
                    placeholder: "tls",
                    validate: ProfileNetworkDraft.snifferProtocolError,
                    identifier: "profile-network.sniffer.legacy-protocols"
                )
                StringListEditor(
                    items: $draft.legacyPortWhitelist,
                    itemTitle: "Port",
                    placeholder: "443",
                    validate: portError,
                    identifier: "profile-network.sniffer.legacy-ports"
                )
            } header: {
                Text("Legacy Compatibility")
            } footer: {
                 
                 
                 
                 
                if draft.modernSniffIsInPlay {
                    Text("Not in effect: the per-protocol settings above are in use.")
                } else if !draft.legacyPortWhitelist.isEmpty, draft.legacySniffing.isEmpty {
                    Text("Ports apply only to the protocols listed above them; with no protocol listed they are not in effect.")
                } else {
                    Text("Kept so older profiles round-trip safely; new profiles use the sections above.")
                }
            }

            if let deviations { deviations }
        }
        
        .clashPageTitle("Sniffer")
        .clashDetailPageInsets()
        .accessibilityIdentifier("profile-network.sniffer.screen")
    }

    @ViewBuilder
    private func protocolSection(
        title: String,
        draft: Binding<ProfileSnifferProtocolDraft>,
         
         
         
         
        defaultPorts: String,
         
         
         
         
         
         
        builtInPorts: String,
         
         
        identifierFragment: String
    ) -> some View {
        Section {
            ClashRoutedViewLink {
                 
                 
                 
                ClashDeferredDraftHost(source: draft.ports) { items in
                    SnifferListPage(
                        title: "\(title) Ports",
                        items: items,
                        itemTitle: "Port",
                        placeholder: defaultPorts,
                        footer: ClashCopy.string(
                            for: .formatCopy(
                                "Leave empty and %@ sniffs only port %@. Listing ports here replaces that, it does not add to it.",
                                [title, builtInPorts]
                            ),
                            locale: locale
                        ),
                        validate: portError,
                        identifier: "profile-network.sniffer.\(identifierFragment).ports"
                    )
                }
            } label: {
                DNSHubRow(
                    title: "Ports",
                    detail: "",
                     
                     
                     
                     
                    value: draft.ports.wrappedValue.isEmpty
                        ? ClashCopy.string(
                            for: .formatCopy("%@ · Core default", [builtInPorts]),
                            locale: locale
                        )
                        : draft.ports.wrappedValue.joined(separator: ", ")
                )
            }
            .accessibilityIdentifier("profile-network.sniffer.\(identifierFragment).ports.row")
            DNSFieldRows.overrideMenuRow(
                "Dial the sniffed domain",
                draft.overrideDestination,
                 
                 
                inherited: .overall(overallOverrideDestination),
                upstreamDefault: UpstreamBoolDefault.value(for: "sniffer.override-destination"),
                identifier: "profile-network.sniffer.\(identifierFragment).override-destination"
            )
        } header: {
            Text(clash: .copy(title))
        }
    }

    private func listRow(
        _ title: String,
        items: Binding<[String]>,
        itemTitle: String,
        noun: String,
        placeholder: String,
        footer: String,
        validate: ((String) -> String?)? = nil,
        identifier: String
    ) -> some View {
        ClashRoutedViewLink {
            ClashDeferredDraftHost(source: items) { local in
                SnifferListPage(
                    title: title,
                    items: local,
                    itemTitle: itemTitle,
                    placeholder: placeholder,
                    footer: footer,
                    validate: validate,
                    identifier: identifier
                )
            }
        } label: {
            DNSHubRow(title: title,
                      detail: "",
                      value: items.wrappedValue.isEmpty
                          ? nil
                          : "\(items.wrappedValue.count) \(noun)")
        }
        .accessibilityIdentifier("\(identifier).row")
    }

    private func portError(_ value: String) -> String? {
        ProfileNetworkDraft.isValidPortToken(value)
            ? nil
            : "Use a port from 1 to 65535, or a valid range such as 8080-8880."
    }

    private func addressPrefixError(_ value: String) -> String? {
        ProfileNetworkDraft.isValidAddressPrefix(value)
            ? nil
            : "Use IPv4 or IPv6 CIDR notation, such as 192.0.2.0/24."
    }
}

 
 
private struct SnifferListPage: View {
    let title: String
    @Binding var items: [String]
    let itemTitle: String
    let placeholder: String
    let footer: String
    var validate: ((String) -> String?)?
    let identifier: String

    var body: some View {
        Form {
            Section {
                StringListEditor(
                    items: $items,
                    itemTitle: itemTitle,
                    placeholder: placeholder,
                    validate: validate,
                    identifier: identifier
                )
            } footer: {
                Text(ClashCopy.key(footer))
            }
        }
        .navigationTitle(ClashCopy.key(title))
        .clashDetailPageInsets()
        .accessibilityIdentifier("\(identifier).screen")
    }
}

 
 
 
 
 
 
private func numberRow(
    _ title: String,
    text: Binding<String>,
    inherited: InheritedNumberBase,
    upstreamDefault: PinnedDefault<Int>,
    suffix: String?,
    identifier: String
) -> some View {
    let typed = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let state = InheritedNumber(base: inherited, override: Int(typed), upstreamDefault: upstreamDefault)
    return ClashFieldRow(
        title,
        hint: state.emptyHint,
        text: text,
        monospaced: true,
        suffix: suffix,
        subtitle: state.sourceLine
    )
    .keyboardType(.numberPad)
    .accessibilityIdentifier(identifier)
}

private func optionalTextRow(
    _ title: String,
    value: Binding<String?>,
    inherited: InheritedTextBase,
    upstreamDefault: PinnedDefault<String>,
    identifier: String
) -> some View {
    let state = InheritedText(base: inherited, override: value.wrappedValue, upstreamDefault: upstreamDefault)
    return ClashFieldRow(
        title,
        hint: state.emptyHint,
        text: Binding(
            get: { value.wrappedValue ?? "" },
            set: { value.wrappedValue = $0.isEmpty ? nil : $0 }
        ),
        monospaced: true,
        subtitle: state.sourceLine
    )
    .textInputAutocapitalization(.never)
    .autocorrectionDisabled()
    .accessibilityIdentifier(identifier)
}

 
 
 
 
 
 
 
enum ProfileNetworkRoute: Hashable, Identifiable {
    case sniffer
    case ntp

    var id: Self { self }
}
