import SwiftUI
import ClashClientUI
#if canImport(AppKit) && !canImport(UIKit)
import AppKit
#endif

 
struct ProxyNodeInspection: Identifiable, Equatable {
    let name: String
    var id: String { name }
}

 
 
 
 
 
 
struct NodeConfigAnswer {
     
    let provider: String?
     
    let mapping: [String: Any]?
     
    let notLoaded: [String]
     
    let error: String?

    init?(json: String) {
        guard let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return nil }
        if root["found"] as? Bool == true, let config = root["config"] as? [String: Any] {
            provider = root["provider"] as? String ?? ""
            mapping = config
        } else {
            provider = nil
            mapping = nil
        }
        notLoaded = root["notLoaded"] as? [String] ?? []
        error = (root["error"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}

 
 
 
 
enum ProxyNodeDetailLookup {
     
     
     
    enum Source: Equatable {
        case main
        case provider(String)
         
         
         
         
         
        case presented
    }

    static func details(
        named name: String,
        yaml: String?,
        providersDir: URL?
    ) -> ProxyProtocolDetails? {
        locate(named: name, yaml: yaml, providersDir: providersDir)?.details
    }

    static func locate(
        named name: String,
        yaml: String?,
        providersDir: URL?
    ) -> (details: ProxyProtocolDetails, source: Source)? {
        locate(named: name, yaml: yaml, presentedYAML: nil, providersDir: providersDir)
    }

     
     
     
     
    static func locate(
        named name: String,
        yaml: String?,
        presentedYAML: String?,
        providersDir: URL?
    ) -> (details: ProxyProtocolDetails, source: Source)? {
        if let yaml,
           let found = ProxyConfigurationInspector.details(named: name, yaml: yaml) {
            return (found, .main)
        }
        if let presentedYAML,
           let found = ProxyConfigurationInspector.details(named: name, yaml: presentedYAML) {
            return (found, .presented)
        }
        guard let providersDir,
              let catalog = ProviderCatalog.load(providersDir: providersDir) else {
            return nil
        }
        for entry in catalog.entries where entry.kind == "proxy" {
            let url = providersDir.appendingPathComponent(entry.path)
            guard let payload = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if let found = details(named: name, inProviderPayload: payload) {
                return (found, .provider(entry.name))
            }
        }
        return nil
    }

     
    struct Resolution {
        var details: ProxyProtocolDetails?
        var source: Source?
         
         
        var notLoaded: [String] = []
    }

     
     
     
     
     
     
     
    static func resolve(
        named name: String,
        yaml: String?,
        presentedYAML: String?,
        providersDir: URL?,
        nodeConfig: (String) -> NodeConfigAnswer?
    ) -> Resolution {
        if let yaml, let found = ProxyConfigurationInspector.details(named: name, yaml: yaml) {
            return Resolution(details: found, source: .main)
        }
        if let presentedYAML, let found = ProxyConfigurationInspector.details(named: name, yaml: presentedYAML) {
            return Resolution(details: found, source: .presented)
        }
        guard let answer = nodeConfig(name) else {
            guard let located = locate(named: name, yaml: nil, presentedYAML: nil, providersDir: providersDir) else {
                return Resolution()
            }
            return Resolution(details: located.details, source: located.source)
        }
        if let mapping = answer.mapping, let details = ProxyProtocolCatalog.details(for: mapping) {
            let provider = answer.provider ?? ""
            return Resolution(details: details, source: provider.isEmpty ? .presented : .provider(provider))
        }
        return Resolution(notLoaded: answer.notLoaded)
    }

     
     
    static func details(
        named name: String,
        inProviderPayload payload: String
    ) -> ProxyProtocolDetails? {
         
         
        if payload.utf8.count > NodesInventoryProjection.wholeReadBytes {
            return ProxyConfigurationInspector.details(named: name, yaml: payload)
        }
        guard let parsed = ConfigTransforms.parsedRoot(forYAML: payload) else { return nil }
        return parsed.memo("proxies.protocolDetails") {
            ProxyConfigurationInspector.detailsByNodeName(root: parsed.root)
        }[name]
    }

     
     
     
    static func coveredValues(for details: ProxyProtocolDetails) -> [String: String] {
        guard let mapping = ProxyProtocolCatalog.mapping(from: details.configurationJSON) else {
            return [:]
        }
        var values: [String: String] = [:]
        for row in details.sections.flatMap(\.rows) {
            guard let key = row.key, let raw = mapping[key] else { continue }
            values[key] = asText(raw)
            if let nested = raw as? [String: Any] { collectLeaves(prefix: key, nested, into: &values) }
        }
        return values
    }

    private static func collectLeaves(prefix: String, _ nested: [String: Any], into values: inout [String: String]) {
        for (leaf, raw) in nested {
            if let deeper = raw as? [String: Any] { collectLeaves(prefix: "\(prefix).\(leaf)", deeper, into: &values) }
            else { values["\(prefix).\(leaf)"] = asText(raw) }
        }
    }

    private static func asText(_ raw: Any) -> String {
        switch raw {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        case let list as [Any]: return list.map(asText).joined(separator: ", ")
        default: return String(describing: raw)
        }
    }

     
     
     
     
    static func expandedRows(for details: ProxyProtocolDetails) -> [String: [ProxyProtocolDetailRow]] {
        guard let mapping = ProxyProtocolCatalog.mapping(from: details.configurationJSON) else {
            return [:]
        }
        var expanded: [String: [ProxyProtocolDetailRow]] = [:]
        for row in details.sections.flatMap(\.rows) where row.value == "Configured" {
            guard let key = row.key, let raw = mapping[key] else { continue }
            expanded[key] = leafRows(prefix: key, raw)
        }
        return expanded
    }

    private static func leafRows(prefix: String, _ raw: Any) -> [ProxyProtocolDetailRow] {
        if let nested = raw as? [String: Any] {
            return nested.keys.sorted().flatMap { leaf -> [ProxyProtocolDetailRow] in
                leafRows(prefix: "\(prefix).\(leaf)", nested[leaf] as Any)
            }
        }
        let text = asText(raw)
        let leaf = prefix.split(separator: ".").last.map(String.init) ?? prefix
        let covered = ProxyNodeDetailSheet.coveredKeys.contains(leaf.lowercased())
        return [.init(label: prefix, value: covered ? String(repeating: "•", count: 8) : text,
                      kind: covered ? .secret : .text, key: prefix)]
    }

     
     
    static func yaml(for details: ProxyProtocolDetails) -> String {
        (try? ConfigTransforms.jsonToYAML(details.configurationJSON))
            ?? details.configurationJSON
    }
}

 
 
 
 
 
struct ProxyNodeDetailSheet: View {
    let nodeName: String
    let yaml: String?
    let providersDir: URL?
     
     
    var suppliedDetails: ProxyProtocolDetails? = nil
     
     
     
     
    var resolved: ProxyNodeDetailLookup.Resolution? = nil
     
    var failureCategory: String? = nil
    var failureMessage: String? = nil

     
     
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
     
     
     
     
    @State private var loaded = false
    @State private var details: ProxyProtocolDetails?
    @State private var covered: [String: String] = [:]
    @State private var expanded: [String: [ProxyProtocolDetailRow]] = [:]
    @State private var revealed: Set<String> = []
    @State private var copied = false
     
    @State private var notLoaded = false

    var body: some View {
        ClashFeatureNavigationContainer {
            Form {
                if !loaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("proxy-detail.loading")
                } else if let details {
                    identity(details)
                    lastFailure
                    ForEach(details.sections) { section in
                        Section(ClashCopy.key(section.title)) {
                            ForEach(section.rows) { row in
                                detailRow(row)
                            }
                        }
                    }
                     
                     
                     
                    #if !os(macOS)
                    Section {
                        Button {
                            copyYAML(details)
                        } label: {
                            Label {
                                Text(ClashCopy.key(copied ? "Copied" : "Copy YAML"))
                            } icon: {
                                Image(systemName: ClashSymbol.docOnDoc.rawValue)
                            }
                        }
                        .accessibilityIdentifier("proxy-detail.copy-yaml")
                    }
                    #endif
                } else if notLoaded {
                     
                     
                     
                    ClashEmptyState(
                        title: ClashCopy.string("No Details", locale: .current),
                        message: ClashCopy.string(
                            "Not downloaded yet — downloads after you connect",
                            locale: .current
                        ),
                        symbol: .infoCircle
                    )
                    .accessibilityIdentifier("proxy-detail.not-loaded")
                } else {
                    ClashEmptyState(
                        title: ClashCopy.string("No Details", locale: .current),
                        message: ClashCopy.string(
                            "This node is not in the configuration or in any of its providers.",
                            locale: .current
                        ),
                        symbol: .infoCircle
                    )
                    .accessibilityIdentifier("proxy-detail.empty")
                }
            }
            .accessibilityIdentifier("proxy-detail.sheet")
             
             
             
             
            #if os(macOS)
            .formStyle(.grouped)
             
             
             
             
             
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if loaded {
                     
                     
                     
                    macActionBar(details)
                }
            }
            #endif
            .clashPageTitle("Node Details")
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) {
                    ClashSheetCloseButton { dismiss() }
                }
            }
            .clashProductModalRoot(title: "Node Details")
        }
        .task(id: nodeName) {
            let name = nodeName
            let source = yaml
            let directory = providersDir
            let supplied = suppliedDetails
            let handed = resolved
            let found = await Task.detached(priority: .userInitiated) { () -> (ProxyProtocolDetails, [String: String], [String: [ProxyProtocolDetailRow]])? in
                guard let details = supplied ?? handed?.details ?? (handed == nil ? ProxyNodeDetailLookup.details(
                    named: name, yaml: source, providersDir: directory
                ) : nil) else { return nil }
                return (
                    details,
                    ProxyNodeDetailLookup.coveredValues(for: details),
                    ProxyNodeDetailLookup.expandedRows(for: details)
                )
            }.value
            details = found?.0
            covered = found?.1 ?? [:]
            expanded = found?.2 ?? [:]
            notLoaded = found == nil && !(handed?.notLoaded.isEmpty ?? true)
            loaded = true
        }
        .clashCapturesDismiss(dismiss)
    }

#if os(macOS)
     
     
     
    private func macActionBar(_ details: ProxyProtocolDetails?) -> some View {
        HStack(spacing: ClashTheme.Spacing.compact) {
            Spacer(minLength: 0)
            if let details {
                Button {
                    copyYAML(details)
                } label: {
                    Text(ClashCopy.key(copied ? "Copied" : "Copy YAML"))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("proxy-detail.copy-yaml")
            }
            Button {
                closePanel()
            } label: {
                Text(ClashCopy.key("Done"))
            }
            .clashPrimaryActionButtonStyle()
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("proxy-detail.done")
        }
        .padding(.horizontal, ClashTheme.Spacing.standard)
        .padding(.vertical, ClashTheme.Spacing.compact)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Rectangle().fill(.bar)
                Divider()
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func closePanel() {
        dismiss.closeModalOrDismiss()
    }
#endif

    private func identity(_ details: ProxyProtocolDetails) -> some View {
        Section {
            valueRow(ClashCopy.key("Name")) {
                Text(verbatim: nodeName)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("proxy-detail.name")
            }
            valueRow(ClashCopy.key("Protocol")) {
                Text(verbatim: details.displayName)
                    .accessibilityIdentifier("proxy-detail.protocol")
            }
        } footer: {
             
             
             
            Text(ClashCopy.key(details.summary))
        }
    }

     
     
    @ViewBuilder
    private var lastFailure: some View {
        if let failureMessage {
            Section(ClashCopy.key("Latency Test")) {
                valueRow(ClashCopy.key("Latency")) {
                    Text(ClashCopy.key(ClashProbeFailureCopy.badge(for: failureCategory ?? "")))
                }
                Text(verbatim: failureMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("proxy-detail.failure")
            }
        }
    }

     
     
    private func valueText(_ row: ProxyProtocolDetailRow, _ written: String) -> Text {
        row.kind == .toggle ? Text(ClashCopy.key(written)) : Text(verbatim: written)
    }

     
     
     
     
    static let coveredKeys: Set<String> = [
        "password", "psk", "pre-shared-key", "private-key", "private-key-passphrase",
        "auth-key", "key", "obfs-password", "auth-str", "auth", "token", "secret",
        "tls-auth", "tls-crypt", "tls-crypt-v2",
    ]

    private func isCovered(_ row: ProxyProtocolDetailRow) -> Bool {
        guard let key = row.key else { return false }
        return Self.coveredKeys.contains(key.lowercased())
    }

     
     
    private func asWritten(_ row: ProxyProtocolDetailRow) -> String {
        row.key.flatMap { covered[$0] } ?? row.value
    }

    @ViewBuilder
    private func detailRow(_ row: ProxyProtocolDetailRow) -> some View {
        if row.value == "Configured", let key = row.key, let leaves = expanded[key], !leaves.isEmpty {
             
             
            ForEach(leaves) { leaf in
                leafRow(leaf)
            }
        } else if !isCovered(row) {
            valueRow(ClashCopy.key(row.label)) {
                valueText(row, asWritten(row))
                    .textSelection(.enabled)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("proxy-detail.row.\(row.id)")
            }
        } else {
            coveredRow(row)
        }
    }

    @ViewBuilder
    private func leafRow(_ leaf: ProxyProtocolDetailRow) -> some View {
        if leaf.kind == .secret {
            coveredRow(leaf)
        } else {
            valueRow(LocalizedStringKey(leaf.label)) {
                Text(verbatim: leaf.value)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("proxy-detail.row.\(leaf.id)")
            }
        }
    }

    @ViewBuilder
    private func coveredRow(_ row: ProxyProtocolDetailRow) -> some View {
        switch row.kind {
        case .text, .toggle:
             
             
             
            valueRow(ClashCopy.key(row.label)) {
                valueText(row, row.value)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("proxy-detail.row.\(row.id)")
            }
        case .secret, .privateText:
            let shown = revealed.contains(row.id)
            let written = asWritten(row)
            valueRow(ClashCopy.key(row.label)) {
                HStack(spacing: ClashTheme.Spacing.row) {
                    Text(verbatim: shown ? written : String(repeating: "•", count: 8))
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("proxy-detail.row.\(row.id)")
                    Button {
                        if shown { revealed.remove(row.id) } else { revealed.insert(row.id) }
                    } label: {
                        Image(systemName: (shown ? ClashSymbol.eyeSlash : ClashSymbol.eye).rawValue)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text(ClashCopy.key(shown ? "Hide" : "Show")))
                    .accessibilityIdentifier("proxy-detail.reveal.\(row.id)")
                }
            }
        }
    }

     
     
     
     
     
    @ViewBuilder
    private func valueRow<Value: View>(
        _ label: LocalizedStringKey,
        @ViewBuilder value: () -> Value
    ) -> some View {
#if os(macOS)
        LabeledContent {
            value()
        } label: {
            Text(label)
        }
#else
        if #available(iOS 16.0, *) {
            LabeledContent {
                value()
            } label: {
                Text(label)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.row) {
                Text(label)
                Spacer(minLength: ClashTheme.Spacing.row)
                value()
                    .foregroundStyle(.secondary)
            }
        }
#endif
    }

    private func copyYAML(_ details: ProxyProtocolDetails) {
        let text = ProxyNodeDetailLookup.yaml(for: details)
#if canImport(UIKit)
        CredentialPasteboardWrite.put(text)
#else
         
         
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#endif
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copied = false
        }
    }
}

 
 
 
 
struct ProxyNodeEditorSheet: View {
    let nodeName: String
     
    let sourceYAML: String?
     
     
    let cachedProjection: String?
    let profile: Profile
    let providersDir: URL?
     
    var failureCategory: String?
    var failureMessage: String?
    @ObservedObject var profiles: ProfilesViewModel

     
    @StateObject private var dismiss = ClashDismissHandle()
     
     
     
     
     
    @State private var loaded = false
    @State private var projected: String?
     
     
    @State private var presented: String?
    @State private var resolution: ProxyNodeDetailLookup.Resolution?
     
     
    @State private var overrideKey: String?

    private func closeModal() {
        dismiss.closeModalOrDismiss()
    }

    var body: some View {
        Group {
            if !loaded {
                ClashFeatureNavigationContainer {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("proxy-detail.loading")
                        .clashPageTitle("Node Details")
                        .clashToolbarUnlessInPanel {
                            ToolbarItem(placement: .cancellationAction) {
                                ClashSheetCloseButton { dismiss() }
                            }
                        }
                }
            } else if let resolution, resolution.source == .main, let details = resolution.details,
                      ProxyNodeEditPolicy.isEditable(hasStoredSource: sourceYAML != nil) {
                ClashFeatureNavigationContainer {
                    ProxyNodeDetailsView(
                        record: ProxyNodeRecord(
                            name: nodeName,
                            type: details.typeID,
                            delay: nil,
                            groupNames: [],
                            protocolDetails: details,
                            failureCategory: failureCategory,
                            failureMessage: failureMessage
                        ),
                        retest: {},
                        saveNode: { original, edited in
                            try await profiles.updateProxyNode(profileID: profile.id, originalJSON: original, editedJSON: edited)
                        },
                        allowsRename: false,
                        showsTesting: false,
                        subscriptionReset: overrideKey.map { key in
                            { try profiles.removeProxyNodeOverride(named: key, profileID: profile.id) }
                        },
                        onDone: { closeModal() },
                        drawsClose: true
                    )
                     
#if os(macOS)
                    .clashToolbarUnlessInPanel {
                        ToolbarItem(placement: .cancellationAction) {
                            ClashSheetCloseButton { dismiss() }
                        }
                    }
#endif
                }
            } else {
                ProxyNodeDetailSheet(
                    nodeName: nodeName,
                    yaml: resolution?.source == .presented ? presented : projected,
                    providersDir: providersDir,
                    resolved: resolution,
                    failureCategory: failureCategory,
                    failureMessage: failureMessage
                )
            }
        }
        .task(id: nodeName) {
            let name = nodeName
            let source = sourceYAML
            let cached = cachedProjection
            let current = profile
            let directory = providersDir
             
             
             
            let presentedDocument = await profiles.loadPresentedProxiesYAML(for: current)
            let result = await Task.detached(priority: .userInitiated) { () -> (String?, ProxyNodeDetailLookup.Resolution) in
                let yaml = cached ?? CustomNodesGroupMaterializer.projectForUI(sourceYAML: source, profile: current)
                 
                 
                return (yaml, ProxyNodeDetailLookup.resolve(
                    named: name, yaml: yaml, presentedYAML: presentedDocument, providersDir: directory,
                    nodeConfig: { OfflineProxyCatalogLoader.nodeConfig(named: $0, profileID: current.id) }
                ))
            }.value
            projected = result.0
            presented = presentedDocument
            resolution = result.1
            overrideKey = await profiles.proxyNodeOverrideKey(named: name, profileID: current.id)
            loaded = true
        }
        .clashCapturesDismiss(dismiss)
    }
}
