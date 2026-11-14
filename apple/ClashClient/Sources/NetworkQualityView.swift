import Clash
import ClashClientUI
import SwiftUI

struct NetworkQualityView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var model: NetworkQualityModel
    @ObservedObject private var networkPath = NetworkPathObserver.shared
    @State private var pathDecision: NetworkPathPolicyDecision?

    var body: some View {
        ClashMacSettingsFormContainer {
            Section {
                if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
                     
                     
                     
                     
                     
                     
                     
                     
                    TextField(
                        text: $model.configURL,
                        prompt: Text(verbatim: ClashNetworkQualityDefaultConfigURL)
                    ) {
                        Text("URL")
                    }
                        .accessibilityIdentifier("networkQuality.configURL")
                    .disabled(model.isRunning)
                } else {
                TextField("URL", text: $model.configURL)
                    .accessibilityIdentifier("networkQuality.configURL.compact")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .disabled(model.isRunning)
                }
                Toggle("Serial", isOn: $model.serial)
                    .accessibilityIdentifier("networkQuality.serial")
                    .disabled(model.isRunning)
                Toggle("HTTP/3", isOn: $model.http3)
                    .accessibilityIdentifier("networkQuality.http3")
                    .disabled(model.isRunning || !model.http3Available)
                Picker("Maximum runtime", selection: $model.maxRuntime) {
                    ForEach(NetworkQualityRuntime.allCases) { option in
                        Text(clash: .copy(option.label)).tag(option)
                    }
                }
                    .accessibilityIdentifier("networkQuality.maxRuntime")
                .disabled(model.isRunning)
            } header: {
                Text("Configuration")
            } footer: {
                Text(model.http3Available
                    ? "HTTP/3 uses QUIC over UDP through the active VPN. Leave it off for the HTTP/1.1 and HTTP/2 path."
                    : "HTTP/3 is unavailable in this SDK build. HTTP/1.1 and HTTP/2 remain available.")
            }

            Section("Action") {
                 
                 
                 
                 
                if model.isRunning {
                    Button(role: .destructive) { model.cancel() } label: {
                        Text("Cancel Test")
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .clashSecondaryActionButtonStyle()
                    .clashCapsuleButtonBorderShape()
                    .controlSize(.regular)
                    .accessibilityIdentifier("networkQuality.cancel")
                } else {
                    Button { requestStart() } label: {
                        Text("Start Test")
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .clashPrimaryActionButtonStyle()
                    .clashCapsuleButtonBorderShape()
                    .controlSize(.regular)
                    .accessibilityIdentifier("networkQuality.start")
                }
            }

            Section("Current Network") {
                OverviewValueRow(title: "Path", value: .verbatim(networkPath.snapshot.summary(locale: locale)))
                    .accessibilityIdentifier("networkQuality.path.summary")
                OverviewValueRow(
                    title: "Address Families",
                    value: Self.addressFamilies(v4: networkPath.snapshot.supportsIPv4, v6: networkPath.snapshot.supportsIPv6)
                )
                .accessibilityIdentifier("networkQuality.path.addressFamilies")
                OverviewValueRow(
                    title: "System DNS",
                    value: Self.systemDNS(available: networkPath.snapshot.supportsDNS)
                )
                .accessibilityIdentifier("networkQuality.path.systemDNS")
            }

            if model.phase >= 0 || !model.lastError.isEmpty {
                Section("Results") {
                    if !model.lastError.isEmpty {
                        ClashStatusMessage(text: .verbatim(model.lastError), kind: .error)
                    }
                    ResultRow(title: "Idle latency", value: model.idleLatencyMs > 0 ? "\(model.idleLatencyMs) ms" : "—", active: model.phase == ClashNetworkQualityPhaseIdle && model.isRunning)
                    ResultRow(title: "Download", value: bitrate(model.downloadCapacity), active: downloadActive)
                        .accessibilityIdentifier("networkQuality.result.download")
                    ResultRow(title: "Download RPM", value: count(model.downloadRPM), active: downloadActive)
                    ResultRow(title: "Upload", value: bitrate(model.uploadCapacity), active: uploadActive)
                        .accessibilityIdentifier("networkQuality.result.upload")
                    ResultRow(title: "Upload RPM", value: count(model.uploadRPM), active: uploadActive)
                }
            }
        }
        
        .clashPageTitle("Network Quality")
        .onDisappear { if model.isRunning { model.cancel() } }
         
        .alert(
            LocalizedStringKey(pathDecision?.title ?? ""),
            isPresented: Binding(
                get: { pathDecision != nil },
                set: { if !$0 { pathDecision = nil } }
            ),
            presenting: pathDecision
        ) { decision in
             
             
             
             
             
            if decision.action == .confirm {
                Button("Continue", role: .destructive) { model.start() }
                    .accessibilityIdentifier("networkQuality.confirm.continue")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("networkQuality.confirm.cancel")
            } else {
                Button("OK", role: .cancel) {}
                    .accessibilityIdentifier("networkQuality.confirm.ok")
            }
        } message: { decision in
            Text(clash: .copy(decision.message))
        }
    }

    private var downloadActive: Bool {
        model.isRunning && model.phase >= ClashNetworkQualityPhaseDownload && model.phase < ClashNetworkQualityPhaseDone
    }

    private var uploadActive: Bool {
        model.isRunning && model.phase >= ClashNetworkQualityPhaseUpload && model.phase < ClashNetworkQualityPhaseDone
    }

    private func bitrate(_ value: Int64) -> String {
        value > 0 ? ClashFormatBitrate(value) : "—"
    }

    private func count(_ value: Int32) -> String {
        value > 0 ? "\(value)" : "—"
    }

     
    static func addressFamilies(v4: Bool, v6: Bool) -> ClashDisplayText {
        switch (v4, v6) {
        case (true, true): return .copy("IPv4 + IPv6")
        case (true, false): return .copy("IPv4-only")
        case (false, true): return .copy("IPv6-only")
        case (false, false): return .copy("None")
        }
    }

     
    static func systemDNS(available: Bool) -> ClashDisplayText {
        .copy(available ? "System DNS is available" : "Unavailable")
    }

    private func requestStart() {
        let decision = NetworkPathPolicy.fullTransfer(snapshot: networkPath.snapshot)
        switch decision.action {
        case .allow:
            model.start()
        case .confirm, .block:
            pathDecision = decision
        case .deferOperation:
            break
        }
    }
}



private struct ResultRow: View {
    let title: String
    let value: String
    let active: Bool

    var body: some View {
        HStack {
            Text(clash: .copy(title))
            Spacer()
            if active { ProgressView().controlSize(.small) }
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
