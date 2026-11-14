import Clash
import SwiftUI

 
 
 
 
 
 
struct ClashTVMoreHub: View {
    enum Row: Hashable, CaseIterable {
        case autoConnect
        case ipStack
        case dns
        case userAgent
        case proxyShare
        case externalController
        case speedUnit
        case diagnostics
        case logs
        case geodata
        case version

        var title: String {
            switch self {
            case .autoConnect: String(localized: "Connect automatically")
            case .dns: String(localized: "DNS")
            case .ipStack: "IP Stack"
            case .userAgent: String(localized: "User-Agent")
            case .proxyShare: String(localized: "Share on this network")
            case .externalController: String(localized: "External Controller")
            case .speedUnit: String(localized: "Speed Unit")
            case .diagnostics: String(localized: "Diagnostics")
            case .logs: String(localized: "Logs")
            case .geodata: String(localized: "Geo data")
            case .version: String(localized: "Version")
            }
        }

         
         
         
         
         
         
        var identifier: String {
            switch self {
            case .autoConnect: "autoConnect"
            case .dns: "dns"
            case .ipStack: "ipStack"
            case .userAgent: "userAgent"
            case .proxyShare: "proxyShare"
            case .externalController: "externalController"
            case .speedUnit: "speedUnit"
            case .diagnostics: "diagnostics"
            case .logs: "logs"
            case .geodata: "geodata"
            case .version: "version"
            }
        }

        var explanation: String {
            switch self {
            case .autoConnect:
                String(localized: "Clash connects by itself whenever the Apple TV is on and online — no need to open it first. STOP doesn't turn this off; it only disconnects until you press START again.")
            case .ipStack:
                String(localized: "Choose how Clash looks up IPs and whether it uses IPv6. Changing it reconnects Clash.")
            case .dns:
                ClashTVDNSScreen.explanation
            case .userAgent:
                String(localized: "The name Clash gives when it downloads profiles. Some profile URLs send back a different format depending on it — keep Clash unless yours works better with another.")
            case .proxyShare:
                String(localized: "Let other devices on your network use this Apple TV as an HTTP or SOCKS5 proxy, with the port, username and password set in your profile. Works while Clash is connected.")
            case .externalController:
                String(localized: "Lets clash-cli on a Mac control Clash on this Apple TV over the local network.")
            case .speedUnit:
                String(localized: "How Home shows download and upload speed. Select switches between bits (Mbps) and bytes (MB/s).")
            case .diagnostics:
                String(localized: "Whether Clash is connected, how much memory it uses, and what it has loaded.")
            case .logs:
                ClashTVLogsScreen.explanation
            case .geodata:
                String(localized: "Which copy of the GeoIP and GeoSite data Clash is using.")
            case .version:
                String(localized: "The app version and build, for a support report.")
            }
        }

         
        var isDoor: Bool {
            switch self {
            case .dns, .ipStack, .userAgent, .proxyShare, .externalController, .diagnostics, .logs: true
            case .autoConnect, .speedUnit, .geodata, .version: false
            }
        }
    }

    enum Door: Hashable { case dns, ipStack, userAgent, proxyShare, externalController, diagnostics, logs }

     
     
    static func externalControllerValue(defaults: UserDefaults? = UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite)) -> String {
        ClashTVFeedback.text(ClashRemoteControlSettings.load(from: defaults).mode.title)
    }

     
     
    static func userAgentValue(defaults: UserDefaults = ClientUserAgent.appGroupDefaults) -> String {
        ClientUserAgent.preset(from: defaults).label.localizedForTelevision
    }

     
     
    static func proxyShareValue(defaults: UserDefaults? = UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite)) -> String {
        ClashTVProxySharePresentation.rowValue(permitted: LocalNetworkPermission.isPermitted(defaults))
    }

     
    static func speedUnitValue(_ unit: ClashThroughputUnit) -> String {
        switch unit {
        case .bits: String(localized: "Bits (Mbps)")
        case .bytes: String(localized: "Bytes (MB/s)")
        }
    }

     
     
    @MainActor
    @discardableResult
    static func switchSpeedUnit(in defaults: UserDefaults?) -> ClashThroughputUnit {
        let next: ClashThroughputUnit = ClashThroughputUnit.stored(in: defaults) == .bits ? .bytes : .bits
        ClashThroughputUnit.store(next, in: defaults)
        return next
    }

    @Binding var state: ClashTVProductState
    @Binding var opened: Door?
    @Environment(\.clashThroughputUnit) private var throughputUnit
     
     
     
     
    var onAutoConnect: (Bool) -> Void = { _ in }

    @State private var explained: Row = .autoConnect


     
     
     
     
    private var autoConnectLine: ClashFeedbackPresentation? {
        if let feedback = state.feedback(for: [.autoConnect]) { return feedback }
        guard let issue = state.autoConnectIssue else { return nil }
        return .warning(title: .verbatim(issue), accessibilityIdentifier: "tvos.more.autoConnect.issue")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            List {
                Section {
                     
                     
                     
                     
                     
                     
                     
                     
                    ClashTVSwitch(isOn: Binding(
                        get: { state.autoConnect },
                        set: { wanted in
                            state.autoConnect = wanted
                            onAutoConnect(wanted)
                        }
                    ), identifier: "tvos.more.\(Row.autoConnect.identifier)") {
                        Text(Row.autoConnect.title)
                    }
                    .onClashTVFocus { explained = .autoConnect }
                     
                     
                     
                     
                    if let line = autoConnectLine {
                        ClashTVFeedbackLine(presentation: line)
                            .focusable(false)
                            .listRowBackground(Color.clear)
                    }
                    row(.ipStack, value: "") { opened = .ipStack }
                    row(.dns, value: Self.dnsValue(state)) { opened = .dns }
                    row(.userAgent, value: Self.userAgentValue()) { opened = .userAgent }
                    row(.proxyShare, value: Self.proxyShareValue()) { opened = .proxyShare }
                    row(.externalController, value: Self.externalControllerValue()) { opened = .externalController }
                } header: {
                    Text("Network")
                }
                 
                 
                Section("Throughput") {
                    row(.speedUnit, value: Self.speedUnitValue(throughputUnit)) {
                        Self.switchSpeedUnit(in: UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite))
                    }
                }
                Section("System") {
                    row(.diagnostics, value: "") { opened = .diagnostics }
                     
                     
                    row(.logs, value: "") { opened = .logs }
                    row(.geodata, value: state.geodataSource.localizedForTelevision) {}
                }
                Section("About") {
                    row(.version, value: Self.version(from: .main)) {}
                }
            }
            .listStyle(.grouped)
            .safeAreaPadding(.horizontal, 44)
            .frame(maxWidth: .infinity)

            ZStack {
                if explained == .version {
                     
                     
                     
                     
                     
                     
                     
                     
                    about
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(explained.title)
                            .font(.caption)
                            .textCase(.uppercase)
                            .foregroundStyle(.tertiary)
                        Text(Self.explanation(for: explained, state: state))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.18), value: explained)
        }
         
    }

     
     
     
     
    private var about: some View {
        VStack(spacing: 12) {
            ClashTVBrandMark(width: ClashTVBrandMark.aboutWidth)
                .padding(.bottom, 20)
            Text("Clash")
                .font(.title2)
            Text("Powered by Clash")
                .font(.body)
                .foregroundStyle(.secondary)
            Text(Self.versionLine(from: .main))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(Self.coreVersionLine(Self.coreVersion()))
                .font(.body.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tvos.more.about")
    }

    private func row(_ row: Row, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LabeledContent(row.title, value: value)
        }
        .onClashTVFocus { explained = row }
        .accessibilityIdentifier("tvos.more.\(row.identifier)")
    }

     

     
     
     
     
     
    static func explanation(for row: Row, state _: ClashTVProductState) -> String {
        row.explanation
    }

     
     
    static func dnsValue(_ state: ClashTVProductState) -> String {
        String(localized: "\(state.dnsNameservers.count) DNS servers · \(state.dnsEnhancedMode)")
    }

     
    static func versionLine(from bundle: Bundle) -> String {
        String(localized: "Version \(version(from: bundle))")
    }

     
     
     
     
     
     
     
     
    static func coreVersionLine(_ version: String) -> String {
        "Clash \(version.isEmpty ? "—" : version)"
    }

     
     
     
     
     
     
     
    static func coreVersion() -> String {
        ClashVersion()
    }

     
    static func version(from bundle: Bundle) -> String {
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }
}
