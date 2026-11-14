import ClashClientUI
import SwiftUI

 
 
struct OnDemandConfigView: View {
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @ObservedObject var vpn: VPNController
    @State private var draft = OnDemandConfiguration.disabled
    @State private var error = ""
    @State private var isSaving = false
    @State private var showingAddRule = false
     
     
     
    @State private var ruleDoor: ClashDoorPayload?
    @State private var hasLoaded = false
     
     
    @State private var newRule: OnDemandRuleSpec?
    @State private var showingNewRule = false
    let usesRegularDetailLayout: Bool

    var body: some View {
        shadowrocketBody
        .clashCapturesDismiss(dismiss)
    }

     
     
     
     
     
     

    private var shadowrocketBody: some View {
        ClashMacSettingsFormContainer {
            Section {
                Toggle("Always On", isOn: setting(\.alwaysOn))
                    .accessibilityIdentifier("onDemand.alwaysOn")
            } header: {
                Text("Always On")
            } footer: {
                Text("If YES, the VPN connection will be always on. The default is NO")
            }

             
             
             
             
             
             
             
             
             
            Section {
                Toggle("On Demand", isOn: setting(\.enabled))
                    .accessibilityIdentifier("onDemand.enabled")
                    .disabled(draft.alwaysOn)
            } header: {
                Text("On Demand")
            } footer: {
                if draft.alwaysOn {
                    Text("Always On is on, so On Demand and its rules do not apply.")
                } else {
                    Text("Toggles VPN On Demand.")
                }
            }

            Section {
                Toggle("Disconnect on Sleep", isOn: setting(\.disconnectOnSleep))
                    .accessibilityIdentifier("onDemand.disconnectOnSleep")
                Toggle("Show Disconnect Message", isOn: setting(\.showDisconnectMessage))
                    .accessibilityIdentifier("onDemand.showDisconnectMessage")
            } header: {
                Text("Other")
            } footer: {
                Text("If YES, the VPN connection will be disconnected when the device goes to sleep. The default is NO")
            }

            Section {
                ForEach($draft.rules) { $rule in
                    ClashPayloadDoorLink(
                        id: rule.id.uuidString,
                        title: rule.action.title,
                        selection: $ruleDoor
                    ) {
                        ClashLazyView {
                            OnDemandRuleEditor(
                                rule: rule,
                                usesRegularDetailLayout: usesRegularDetailLayout
                            ) { edited in
                                rule = edited
                                commit(draft)
                            }
                        }
                        .clashRegularDetailPageLayout(enabled: usesRegularDetailLayout)
                    } label: {
                        OnDemandRuleRowLabel(rule: rule)
                            .accessibilityElement(children: .combine)
                    }
                    .deleteDisabled(draft.alwaysOn)
                    .moveDisabled(draft.alwaysOn)
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
                        macRuleControls(for: rule.id)
                    }
                }
                .onDelete { offsets in
                    var next = draft
                    next.rules.remove(atOffsets: offsets)
                    commit(next)
                }
                .onMove { source, destination in
                    var next = draft
                    next.rules.move(fromOffsets: source, toOffset: destination)
                    commit(next)
                }
            } header: {
                HStack {
                    Text("On Demand Rules")
                    Spacer()
                    addRuleControl(iconOnly: true)
                        .accessibilityIdentifier("onDemand.rules.add")
                }
            }
            .disabled(draft.alwaysOn)

            if !error.isEmpty {
                Section {
                    ClashStatusMessage(text: .copy(error), kind: .error)
                        .accessibilityIdentifier("onDemand.error")
                }
            }
        }
        .clashDoorPresenter(payload: $ruleDoor)
        .background(newRuleDestination.opacity(0))
        .clashPageTitle("On Demand")
        .onAppear {
            guard !hasLoaded else { return }
            draft = OnDemandSettings.configuration()
            hasLoaded = true
        }
        .clashToolbarUnlessInPanel {
            ToolbarItemGroup(placement: .clashNavigationTrailing) {
                ClashEditButton()
                addRuleControl(iconOnly: false)
                    .accessibilityIdentifier("onDemand.addRule")
                    .disabled(draft.alwaysOn)
            }
        }
    }

    private func setting(_ keyPath: WritableKeyPath<OnDemandConfiguration, Bool>) -> Binding<Bool> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { value in
                var next = draft
                next[keyPath: keyPath] = value
                if keyPath == \.showDisconnectMessage, value {
                    VPNDisconnectNotice.requestAuthorization()
                }
                commit(next)
            }
        )
    }

     
     
     
    private func macRuleControls(for id: UUID) -> some View {
        let index = draft.rules.firstIndex { $0.id == id }
        let isFirst = index == draft.rules.startIndex
        let isLast = index.map { $0 == draft.rules.count - 1 } ?? true
        return HStack(spacing: 6) {
            Button {
                var next = draft
                OnDemandRuleSurgery.move(&next.rules, id: id, offset: -1)
                commit(next)
            } label: {
                ClashSymbolImage(symbol: .chevronUp)
            }
            .disabled(isFirst)
            .accessibilityIdentifier("onDemand.rule.moveUp")
            Button {
                var next = draft
                OnDemandRuleSurgery.move(&next.rules, id: id, offset: 1)
                commit(next)
            } label: {
                ClashSymbolImage(symbol: .chevronDown)
            }
            .disabled(isLast)
            .accessibilityIdentifier("onDemand.rule.moveDown")
            Button(role: .destructive) {
                var next = draft
                OnDemandRuleSurgery.remove(&next.rules, id: id)
                commit(next)
            } label: {
                ClashSymbolImage(symbol: .minusCircle)
            }
            .accessibilityIdentifier("onDemand.rule.remove")
        }
        .buttonStyle(.plain)
    }

    private func appendRule() {
        var next = draft
        next.rules.append(OnDemandRuleSpec(action: .connect))
        commit(next)
    }

     
     
     
     
    @ViewBuilder
    private func addRuleControl(iconOnly: Bool) -> some View {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            Button(action: appendRule) {
                addRuleLabel(iconOnly: iconOnly)
            }
        } else {
            Menu {
                ForEach(OnDemandRulePreset.platformCases) { preset in
                    Button {
                        newRule = preset.rule
                        showingNewRule = true
                    } label: {
                        Text(clash: .copy(preset.title))
                    }
                    .accessibilityIdentifier("onDemand.addRule.preset.\(preset.rawValue)")
                }
            } label: {
                addRuleLabel(iconOnly: iconOnly)
            }
        }
    }

    @ViewBuilder
    private func addRuleLabel(iconOnly: Bool) -> some View {
        if iconOnly {
            Label("Add Rule", systemImage: ClashSymbol.plus.name).labelStyle(.iconOnly)
        } else {
            Label("Add Rule", systemImage: ClashSymbol.plus.name)
        }
    }

     
     
     
    @ViewBuilder
    private var newRuleDestination: some View {
        if !ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            ClashRoutedViewDestination(isPresented: $showingNewRule) {
                if let newRule {
                    ClashLazyView {
                        OnDemandRuleEditor(rule: newRule, usesRegularDetailLayout: usesRegularDetailLayout) { edited in
                            var next = draft
                            next.rules.append(edited)
                            commit(next)
                        }
                    }
                    .clashRegularDetailPageLayout(enabled: usesRegularDetailLayout)
                }
            }
        }
    }

     
     
     
     
    private func commit(_ next: OnDemandConfiguration) {
        let previous = draft
        draft = next
        error = ""
        do {
            try OnDemandSettings.save(next)
        } catch {
            self.error = error.localizedDescription
            draft = previous
            return
        }
        isSaving = true
        Task {
            switch await vpn.applyOnDemandSettingsReportingOutcome() {
            case .applied:
                break
            case .refused(let reason):
                try? OnDemandSettings.save(previous)
                draft = previous
                self.error = reason
            case .indeterminate(let reason):
                self.error = reason
            }
            isSaving = false
        }
    }

}

 
 
 
 
 
struct OnDemandRuleRowLabel: View {
    @Environment(\.locale) private var locale
    let rule: OnDemandRuleSpec

    var body: some View {
        VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
            Text(verbatim: rule.title(locale: locale))
            if let conditions = rule.conditions(locale: locale) {
                Text(verbatim: conditions)
                    .font(ClashPlatformLayout.pageUsesSystemSettingsIdiom ? ClashMacSettingsType.value : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct OnDemandRuleEditor: View {
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
     
     
     
     
     
     
     
     
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
     
     
    private let openedWith: OnDemandRuleSpec
    @State private var draft: OnDemandRuleSpec
    @State private var error = ""
    @State private var showingAddConnectionRule = false
     
    @State private var pendingSSID = ""
    @State private var pendingSearchDomain = ""
    @State private var pendingServerAddress = ""
    let usesRegularDetailLayout: Bool
    let onSave: (OnDemandRuleSpec) -> Void

    init(
        rule: OnDemandRuleSpec,
        usesRegularDetailLayout: Bool,
        onSave: @escaping (OnDemandRuleSpec) -> Void
    ) {
        _draft = State(initialValue: rule)
        openedWith = rule
        self.usesRegularDetailLayout = usesRegularDetailLayout
        self.onSave = onSave
    }

    var body: some View {
        ClashMacSettingsFormContainer {
            Section("Action") {
                Picker("Action", selection: $draft.action) {
                    ForEach(OnDemandRuleAction.allCases) { action in
                        Text(clash: .copy(action.title)).tag(action)
                    }
                }
                .accessibilityIdentifier("onDemand.rule.action")
                Picker("Interface", selection: $draft.interface) {
                    ForEach(OnDemandInterface.platformCases) { interface in
                        Text(clash: .copy(interface.title)).tag(interface)
                    }
                }
                .accessibilityIdentifier("onDemand.rule.interface")
            }

            Section {
                StringListEditor(
                    items: $draft.ssids,
                    itemTitle: "SSID Match",
                    placeholder: "Wi-Fi SSID",
                    pending: $pendingSSID
                )
                .accessibilityIdentifier("onDemand.rule.ssids")
            } header: {
                Text("SSID Match")
            } footer: {
                Text("Leave empty to ignore SSID. Use Connect for inclusion or Disconnect for exclusion.")
            }

            Section("DNS Search Domain Match") {
                StringListEditor(
                    items: $draft.dnsSearchDomains,
                    itemTitle: "Domain",
                    placeholder: "example.com",
                    pending: $pendingSearchDomain
                )
                .accessibilityIdentifier("onDemand.rule.dnsSearchDomains")
            }

            Section {
                StringListEditor(
                    items: $draft.dnsServerAddresses,
                    itemTitle: "Address",
                    placeholder: "1.1.1.1",
                    pending: $pendingServerAddress
                )
                .accessibilityIdentifier("onDemand.rule.dnsServerAddresses")
            } header: {
                Text("DNS Server Address Match")
            } footer: {
                Text("IP addresses only.")
            }

            Section {
                clashPromptField(
                    "https://example.com/health",
                    text: $draft.probeURL
                )
                    .font(ClashPlatformLayout.pageUsesSystemSettingsIdiom ? ClashMacSettingsType.mono : .caption.monospaced())
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("onDemand.rule.probeURL")
            } header: {
                Text("Probe URL")
            } footer: {
                Text("Optional. Use a credential-free http or https probe; Apple requires HTTP 200 for a match.")
            }

            if draft.action == .evaluate {
                Section {
                    ForEach($draft.connectionRules) { $rule in
                        ClashRoutedViewLink {
                            ClashLazyView {
                                OnDemandEvaluateRuleEditor(rule: rule) { rule = $0 }
                            }
                                .clashRegularDetailPageLayout(enabled: usesRegularDetailLayout)
                        } label: {
                            VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                                 
                                 
                                 
                                Text(clash: .copy(rule.action.title))
                                (rule.matchDomains.isEmpty
                                     ? Text("Add match domains")
                                     : Text(verbatim: rule.matchDomains.joined(separator: ", ")))
                                    .font(ClashPlatformLayout.pageUsesSystemSettingsIdiom ? ClashMacSettingsType.value : .caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .onDelete { draft.connectionRules.remove(atOffsets: $0) }
                    .onMove { draft.connectionRules.move(fromOffsets: $0, toOffset: $1) }

                    ClashAddRow(Text("Add Connection Rule")) {
                        showingAddConnectionRule = true
                    } touchLabel: {
                        Label("Add Connection Rule", systemImage: ClashSymbol.plus.name)
                    }
                    .accessibilityIdentifier("onDemand.rule.addConnectionRule")
                } header: {
                    Text("Connection Rules")
                } footer: {
                    Text("Destination domains are evaluated in this order after the outer rule matches.")
                }
            }

            if !error.isEmpty {
                Section { ClashStatusMessage(text: .copy(error), kind: .error) }
            }
        }
        
         
         
         
         
         
         
         
         
        .clashRegistersDeparture(
            isDirty: draft != openedWith || hasPendingEntry,
            save: { completion in
                completion(commit())
            },
            discard: {
                draft = openedWith
                pendingSSID = ""; pendingSearchDomain = ""; pendingServerAddress = ""
            }
        )
        .clashPageTitle("On Demand Rule")
        .confirmationDialog("Add Connection Rule", isPresented: $showingAddConnectionRule) {
            ForEach(OnDemandEvaluateAction.allCases) { action in
                     
                     
                     
                     
                     
                     
                Button {
                    draft.connectionRules.append(OnDemandEvaluateRuleSpec(action: action))
                } label: {
                    Text(clash: .copy(action.title))
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .toolbar {
            ToolbarItemGroup(placement: .clashNavigationTrailing) {
                if draft.action == .evaluate { ClashEditButton() }
                 
                 
                 
                if !insideProductModal {
                    ClashSaveButton { save() }
                        .accessibilityIdentifier("onDemand.rule.save")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if insideProductModal {
                ClashModalActionBar(primaryTitle: "Save",
                    onPrimary: save)
            }
        }
         
         
         
         
        .clashPageProbe("on-demand-rule")
        .clashCapturesDismiss(dismiss)
    }

     
     
     
     
     
    private func save() { if commit() { closePage() } }

    private var hasPendingEntry: Bool {
        ![pendingSSID, pendingSearchDomain, pendingServerAddress]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    @discardableResult
    private func commit() -> Bool {
        let taken = draft.takingPending(ssid: pendingSSID, dnsSearchDomain: pendingSearchDomain,
                                        dnsServerAddress: pendingServerAddress)
        do {
            _ = try OnDemandSettings.rules(configuration: OnDemandConfiguration(
                enabled: true,
                rules: [taken]
            ))
            draft = taken
            pendingSSID = ""; pendingSearchDomain = ""; pendingServerAddress = ""
            onSave(taken.normalized())
            return true
        } catch {
            self.error = error.localizedDescription
        }
        return false
    }

     
     
    private func closePage() {
        dismiss.closeModalOrDismiss()
    }
}

private struct OnDemandEvaluateRuleEditor: View {
    @Environment(\.clashPopRoute) private var popRoute
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
     
     
     
     
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
     
     
    private let openedWith: OnDemandEvaluateRuleSpec
    @State private var draft: OnDemandEvaluateRuleSpec
    @State private var error = ""
     
    @State private var pendingMatchDomain = ""
    @State private var pendingDNSServer = ""
    let onSave: (OnDemandEvaluateRuleSpec) -> Void

    init(rule: OnDemandEvaluateRuleSpec, onSave: @escaping (OnDemandEvaluateRuleSpec) -> Void) {
        _draft = State(initialValue: rule)
        openedWith = rule
        self.onSave = onSave
    }

    var body: some View {
        ClashMacSettingsFormContainer {
            Section("Action") {
                Picker("Action", selection: $draft.action) {
                    ForEach(OnDemandEvaluateAction.allCases) { action in
                        Text(clash: .copy(action.title)).tag(action)
                    }
                }
                .accessibilityIdentifier("onDemand.evaluate.action")
            }
            Section {
                StringListEditor(
                    items: $draft.matchDomains,
                    itemTitle: "Domain",
                    placeholder: "example.com",
                    pending: $pendingMatchDomain
                )
                .accessibilityIdentifier("onDemand.evaluate.matchDomains")
            } header: {
                Text("Match Domains")
            } footer: {
                Text("Required. Destination host suffixes matched by this connection rule.")
            }
            Section {
                StringListEditor(
                    items: $draft.dnsServers,
                    itemTitle: "Address",
                    placeholder: "1.1.1.1",
                    pending: $pendingDNSServer
                )
                .accessibilityIdentifier("onDemand.evaluate.dnsServers")
            } header: {
                Text("Evaluation DNS Servers")
            } footer: {
                Text("Optional IP addresses used by Connect If Needed while checking direct reachability.")
            }
            Section {
                clashPromptField(
                    "https://example.com/health",
                    text: $draft.probeURL
                )
                .accessibilityIdentifier("onDemand.evaluate.probeURL")
                    .font(ClashPlatformLayout.pageUsesSystemSettingsIdiom ? ClashMacSettingsType.mono : .caption.monospaced())
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Evaluation Probe URL")
            } footer: {
                Text("Optional credential-free http or https URL used by Connect If Needed.")
            }
            if !error.isEmpty {
                Section { ClashStatusMessage(text: .copy(error), kind: .error) }
            }
        }
        
         
         
         
         
         
         
         
         
        .clashRegistersDeparture(
            isDirty: draft != openedWith
                || !(pendingMatchDomain + pendingDNSServer).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            save: { completion in
                completion(commit())
            },
            discard: {
                draft = openedWith
                pendingMatchDomain = ""; pendingDNSServer = ""
            }
        )
        .clashPageTitle("Connection Rule")
        .toolbar {
            ToolbarItem(placement: .clashNavigationTrailing) {
                 
                 
                 
                if !insideProductModal {
                    ClashSaveButton { save() }
                        .accessibilityIdentifier("onDemand.connectionRule.save")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if insideProductModal {
                ClashModalActionBar(primaryTitle: "Save",
                    onPrimary: save)
            }
        }
         
         
         
         
        .clashPageProbe("on-demand-connection-rule")
        .clashCapturesDismiss(dismiss)
    }

     
     
     
     
     
    private func save() { if commit() { closePage() } }

    @discardableResult
    private func commit() -> Bool {
        let taken = draft.takingPending(matchDomain: pendingMatchDomain, dnsServer: pendingDNSServer)
        let outer = OnDemandRuleSpec(action: .evaluate, connectionRules: [taken])
        do {
            _ = try OnDemandSettings.rules(configuration: OnDemandConfiguration(
                enabled: true,
                rules: [outer]
            ))
            draft = taken
            pendingMatchDomain = ""; pendingDNSServer = ""
            onSave(taken.normalized())
            return true
        } catch {
            self.error = error.localizedDescription
        }
        return false
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func closePage() {
#if os(macOS)
        if let popRoute {
            popRoute(ClashPopToken())
        } else {
            dismiss()
        }
#else
        dismiss()
#endif
    }
}
