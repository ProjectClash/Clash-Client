import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashMacTunnelSettingsView: View {
    @ObservedObject var vpn: VPNController
     
     
     
    @State private var moduleSets: [ModuleDeviceSettingKey: ModuleDeviceSettingNote] = [:]
    @Environment(\.locale) private var locale

    var body: some View {
        ClashMacSettingsFormContainer {
            Section {
                 
                 
                 
                Toggle("Enforce Routes", isOn: binding(\.enforceRoutes))
                    .accessibilityIdentifier("tunnel.enforceRoutes")
            } footer: {
                Text("If YES, route rules for this tunnel will take precedence over any locally-defined routes. The default is NO.")
            }

            Section {
                Toggle("Include All Networks", isOn: binding(\.includeAllNetworks))
                    .accessibilityIdentifier("tunnel.includeAllNetworks")
            } header: {
                Text("Include All Networks")
            } footer: {
                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                    Text("If YES, all network traffic is routed through the tunnel, with some exclusions.")
                    moduleNote(.includeAllNetworks)
                }
            }

            Section {
                Toggle("Include Local Networks", isOn: binding(\.includeLocalNetworks))
                    .disabled(!shown.localNetworksSwitchIsEnabled)
                    .accessibilityIdentifier("tunnel.includeLocalNetworks")
            } header: {
                Text("Include Local Networks")
            } footer: {
                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                    Text("If YES, all traffic destined for local networks will be included from the tunnel.")
                    moduleNote(.includeLocalNetworks)
                }
            }

            if #available(macOS 13.3, *) {
                Section {
                    Toggle("Include APNs", isOn: binding(\.includeAPNs))
                        .disabled(!shown.apnsSwitchIsEnabled)
                        .accessibilityIdentifier("tunnel.includeAPNs")
                } header: {
                    Text("Include APNs")
                } footer: {
                    VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                        Text("If YES, the network traffic for the Apple Push Notification service (APNs) will be included from the tunnel.")
                        moduleNote(.includeAPNs)
                    }
                }
            }

            Section {
                Toggle("Hide VPN Icon", isOn: binding(\.hideVPNIcon))
                    .accessibilityIdentifier("tunnel.hideVPNIcon")
            } header: {
                Text("Hide VPN Icon")
            } footer: {
                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                    Text("If YES, the VPN badge stays off the status bar: the tunnel leaves 0.0.0.0/31 and ::/127 outside its routes. Takes effect on the next connection.")
                    moduleNote(.hideVPNIcon)
                }
            }

            Section {
                Toggle("HomeKit Compatibility", isOn: binding(\.homeKitCompatibility))
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
                    .accessibilityIdentifier("tunnel.excludeAPNsRoute")
            } header: {
                Text("Exclude APNs Route")
            } footer: {
                Text("If YES, 17.0.0.0/8 stays outside the tunnel and push.apple.com resolves to its real address, so Apple push notifications reach this Mac directly instead of through the proxy. Takes effect on the next connection.")
            }

            if !vpn.tunnelSettingsRefusal.isEmpty {
                Section {
                    ClashStatusMessage(text: .copy(vpn.tunnelSettingsRefusal), kind: .error)
                        .accessibilityIdentifier("tunnel.error")
                }
            }
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

     
    private var shown: VPNTunnelSettings { vpn.waitingTunnelSettings ?? vpn.tunnelSettings }

    private func binding(_ keyPath: WritableKeyPath<VPNTunnelSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { shown[keyPath: keyPath] },
            set: { value in
                var next = shown
                next[keyPath: keyPath] = value
                vpn.flipTunnelSettings(to: next)
            }
        )
    }
}
