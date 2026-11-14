import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct TunnelSettingsView: View {
    @ObservedObject var vpn: VPNController
     
     
     
    @ObservedObject private var applying: TunnelSettingsApplying

    init(vpn: VPNController) {
        self.vpn = vpn
        _applying = ObservedObject(wrappedValue: vpn.tunnelSettingsApplying)
    }

     
    var sharedApplier: TunnelSettingsApplying { applying }
     
     
     
    @State private var moduleSets: [ModuleDeviceSettingKey: ModuleDeviceSettingNote] = [:]
    @Environment(\.locale) private var locale

    var body: some View {
        ClashMacSettingsFormContainer {
            Section {
                 
                 
                 
                Toggle("Enforce Routes", isOn: binding(\.enforceRoutes))
                    .tunnelSwitchWaiting(applying, \.enforceRoutes)
                    .accessibilityIdentifier("tunnel.enforceRoutes")
            } footer: {
                Text("If YES, route rules for this tunnel will take precedence over any locally-defined routes. The default is NO.")
            }

            Section {
                Toggle("Include All Networks", isOn: binding(\.includeAllNetworks))
                    .tunnelSwitchWaiting(applying, \.includeAllNetworks)
                    .accessibilityIdentifier("tunnel.includeAllNetworks")
            } header: {
                Text("Include All Networks")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("If YES, all network traffic is routed through the tunnel, with some exclusions.")
                     
                     
                     
                     
                     
                     
                     
                     
                    Text("While this is on, updating Clash can cut off the network until the device restarts. Turn it off before updating.")
                    moduleNote(.includeAllNetworks)
                }
            }

            Section {
                Toggle("Include Local Networks", isOn: binding(\.includeLocalNetworks))
                    .tunnelSwitchWaiting(applying, \.includeLocalNetworks)
                    .disabled(!(applying.draft.includeAllNetworks || applying.draft.enforceRoutes))
                    .accessibilityIdentifier("tunnel.includeLocalNetworks")
            } header: {
                Text("Include Local Networks")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("If YES, all traffic destined for local networks will be included from the tunnel.")
                    moduleNote(.includeLocalNetworks)
                }
            }

            if #available(iOS 16.4, *) {
                Section {
                    Toggle("Include APNs", isOn: binding(\.includeAPNs))
                        .tunnelSwitchWaiting(applying, \.includeAPNs)
                        .disabled(!applying.draft.includeAllNetworks)
                        .accessibilityIdentifier("tunnel.includeAPNs")
                } header: {
                    Text("Include APNs")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("If YES, the network traffic for the Apple Push Notification service (APNs) will be included from the tunnel.")
                        moduleNote(.includeAPNs)
                    }
                }

                Section {
                    Toggle("Include Cellular Services", isOn: binding(\.includeCellularServices))
                        .tunnelSwitchWaiting(applying, \.includeCellularServices)
                        .disabled(!applying.draft.includeAllNetworks)
                        .accessibilityIdentifier("tunnel.includeCellularServices")
                } header: {
                    Text("Include Cellular Services")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("If YES, The internet-routable network traffic for cellular services (VoLTE, Wi-Fi Calling, IMS, MMS, Visual Voicemail, etc.) will be included from the tunnel.")
                        moduleNote(.includeCellularServices)
                    }
                }
            }

             
             
            Section {
                Toggle("Hide VPN Icon", isOn: binding(\.hideVPNIcon))
                    .tunnelSwitchWaiting(applying, \.hideVPNIcon)
                    .accessibilityIdentifier("tunnel.hideVPNIcon")
            } header: {
                Text("Hide VPN Icon")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("If YES, the VPN badge stays off the status bar: the tunnel leaves 0.0.0.0/31 and ::/127 outside its routes. Takes effect on the next connection.")
                    moduleNote(.hideVPNIcon)
                }
            }

            Section {
                Toggle("HomeKit Compatibility", isOn: binding(\.homeKitCompatibility))
                    .tunnelSwitchWaiting(applying, \.homeKitCompatibility)
                    .accessibilityIdentifier("tunnel.homeKitCompatibility")
            } header: {
                Text("HomeKit Compatibility")
            } footer: {
                 
                 
                 
                 
                 
                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                    Text("If YES, the tunnel does not take the default route and installs a split route table instead, so HomeKit accessories on the local network keep answering. Internet Sharing does not work while this is on. Takes effect on the next connection.")
                    Text("Turn this on only if HomeKit accessories stop responding. Not needed when the configuration sets tun.strict-route.")
                    moduleNote(.homeKitCompatibility)
                }
            }

             
             
            Section {
                Toggle("Exclude APNs Route", isOn: binding(\.excludeAPNsRoute))
                    .tunnelSwitchWaiting(applying, \.excludeAPNsRoute)
                    .accessibilityIdentifier("tunnel.excludeAPNsRoute")
            } header: {
                Text("Exclude APNs Route")
            } footer: {
                Text("If YES, 17.0.0.0/8 stays outside the tunnel and push.apple.com resolves to its real address, so Apple push notifications reach this device directly instead of through the proxy. Takes effect on the next connection.")
            }

            if !applying.error.isEmpty {
                Section {
                    ClashStatusMessage(text: .copy(applying.error), kind: .error)
                        .accessibilityIdentifier("tunnel.error")
                }
            }
        }
        .onChange(of: vpn.tunnelSettings) { settings in
            applying.adopt(settings)
        }
        .task { moduleSets = await ModuleDeviceSettingNote.published() }
    }

     
     
    @ViewBuilder
    private func moduleNote(_ key: ModuleDeviceSettingKey) -> some View {
        if let set = moduleSets[key] {
            Text(clash: .format("Module “%@” sets “%@”, which runs over this.",
                               [set.module, ClashCopy.string(for: .copy(set.isOn ? "On" : "Off"), locale: locale)]))
                .accessibilityIdentifier("tunnel.module-note.\(key.rawValue)")
        }
    }

    private func binding(_ keyPath: WritableKeyPath<VPNTunnelSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { applying.draft[keyPath: keyPath] },
            set: { value in applying.flip(keyPath, to: value) }
        )
    }
}

extension View {
     
     
    fileprivate func tunnelSwitchWaiting(_ applying: TunnelSettingsApplying,
                                         _ keyPath: WritableKeyPath<VPNTunnelSettings, Bool>) -> some View {
        disabled(applying.isWaiting(keyPath))
    }
}

 
 
 
 
 
 
 
 
 
 
@MainActor
final class TunnelSettingsApplying: ObservableObject {
    @Published private(set) var draft: VPNTunnelSettings
     
    @Published private(set) var confirmed: VPNTunnelSettings
    @Published private(set) var error = ""
     
     
    private(set) var isApplying = false
    private let apply: (VPNTunnelSettings) async -> Bool
    private let current: () -> VPNTunnelSettings?
     
     
    let lastError: () -> String

    static let switches: [WritableKeyPath<VPNTunnelSettings, Bool>] = [
        \.enforceRoutes, \.includeAllNetworks, \.includeLocalNetworks, \.includeAPNs,
        \.includeCellularServices, \.hideVPNIcon, \.homeKitCompatibility, \.excludeAPNsRoute,
    ]

     
    init(settings: VPNTunnelSettings, apply: @escaping (VPNTunnelSettings) async -> Bool,
         current: @escaping () -> VPNTunnelSettings?, lastError: @escaping () -> String) {
        draft = settings
        confirmed = settings
        self.apply = apply
        self.current = current
        self.lastError = lastError
    }

    convenience init(vpn: VPNController) {
        self.init(settings: vpn.tunnelSettings,
                  apply: { [weak vpn] settings in await vpn?.updateTunnelSettings(settings) ?? false },
                  current: { [weak vpn] in vpn?.tunnelSettings },
                  lastError: { [weak vpn] in vpn?.reportableLastError ?? "" })
    }

     
     
    func adopt(_ settings: VPNTunnelSettings) {
        guard !isApplying, draft == confirmed else { return }
        draft = settings
        confirmed = settings
    }

    func isWaiting(_ keyPath: WritableKeyPath<VPNTunnelSettings, Bool>) -> Bool {
        draft[keyPath: keyPath] != confirmed[keyPath: keyPath]
    }

    func flip(_ keyPath: WritableKeyPath<VPNTunnelSettings, Bool>, to value: Bool) {
        guard draft[keyPath: keyPath] != value else { return }
        draft[keyPath: keyPath] = value
        error = ""
        guard !isApplying else { return }
        isApplying = true
        Task { await applyUntilSettled() }
    }

     
    private func applyUntilSettled() async {
        defer { isApplying = false }
        while draft != confirmed {
            let settings = draft
            let before = confirmed
            if await apply(settings) {
                confirmed = settings
                continue
            }
            error = lastError()
            let rolledBack = current() ?? before
            confirmed = rolledBack
             
             
            for keyPath in Self.switches where settings[keyPath: keyPath] != before[keyPath: keyPath]
                && draft[keyPath: keyPath] == settings[keyPath: keyPath] {
                draft[keyPath: keyPath] = rolledBack[keyPath: keyPath]
            }
        }
    }
}
