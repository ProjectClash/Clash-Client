import ClashClientUI
import SwiftUI

 
 
struct ProfilePreviewView: View {
    let title: ClashDisplayText
    private let loader: () async throws -> String?
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.locale) private var locale
    @State private var text = ""
    @State private var isAvailable = false
    @State private var isLoading = true
    @State private var failure: String?

    init(title: ClashDisplayText, load: @escaping () async throws -> String?) {
        self.title = title
        loader = load
    }

    var body: some View {
        ClashFeatureNavigationContainer {
            VStack(spacing: ClashTheme.Spacing.standard) {
                Group {
                    if isLoading {
                        ProgressView("Preparing local configuration")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("profile-preview.loading")
                    } else if let failure {
                        ScrollView {
                            VStack(alignment: .leading, spacing: ClashTheme.Spacing.standard) {
                                Text("Unable to Read Runtime Configuration").font(.headline)
                                Text(verbatim: failure).foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityIdentifier("profile-preview.error")
                    } else if isAvailable {
                        VStack(alignment: .leading, spacing: ClashTheme.Spacing.standard) {
                            CodeEditorPanel(text: $text, language: .yaml, minHeight: 360,
                                isEditable: false, expandsVertically: true)
                                .accessibilityIdentifier("profile-preview.document")
#if os(macOS)
                                .clashPageProbe("runtime-editor")
#endif
                        }
                    } else {
                        ClashEmptyState(
                            title: "Nothing to Show",
                            message: "This profile has no configuration document yet.",
                            symbol: .docTextMagnifyingglass)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(ClashTheme.Spacing.standard)
            .background(ClashTheme.canvas.ignoresSafeArea())
            .clashPageTitle(title, watchAs: "profile-preview")
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) {
                    ClashSheetCloseButton { dismiss() }
                }
            }
            .clashProductModalRoot(title: "Runtime Configuration")
            .task {
                do {
                    let loaded = try await loader()
                    guard !Task.isCancelled else { return }
                    text = loaded ?? ""
                    isAvailable = loaded != nil
                } catch {
                    guard !Task.isCancelled else { return }
                    failure = Self.failureMessage(for: error, locale: locale)
                }
                isLoading = false
            }
        }
        .clashStackNavigationViewStyle()
        .clashCapturesDismiss(dismiss)
    }

     
     
     
     
     
     
     
     
     
    static func failureMessage(for error: Error, locale: Locale) -> String {
        ClashErrorCopy.message(error, locale: locale)
    }
}

private enum FinalConfigurationPreviewKind: String, CaseIterable, Identifiable {
    case source = "Profile URL Source"
     
     
     
    case effective = "preview.kind.runtime"

    var id: String { rawValue }
}

 
 
 
 
struct ProfileFinalConfigurationView: View {
    let title: String
    let snapshot: ProfileFinalConfigurationSnapshot
    private let ownsNavigationContainer: Bool
     
     
    private let command: ClashCommandClient?
     
     
    private let sourceYAML: String?
     
     
     
     
     
     
     
    private let comparisonYAML: String?
    private let baseYAML: String?

     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.locale) private var locale
    @State private var previewKind: FinalConfigurationPreviewKind = .effective
     
     
    @State private var verdict: PreflightOutcome?
     
     
    @State private var deviations: ConfigDeviationReport?
     
     
     
     
    @State private var deviationsAreOffline = false
     
     
     
     
    @State private var blockedRuleSets: [ProviderCompileVerdicts.Blocked] = []
     
     
     
     
     
     
    @State private var planNotices: [String] = []
     
     
    @State private var planNoticesLoaded = false
    private let blockedRuleSetsLoader:
        (@Sendable () async -> [ProviderCompileVerdicts.Blocked])?

     
     
     
#if os(macOS)
     
    @ViewBuilder
    private var previewLabel: some View {
        disclosureLabel(
            title: previewKind == .source
                ? "View Captured Source"
                : "View Runtime Configuration",
            detail: selectedText == nil ? "Not available yet" : "Read-only",
            symbol: .docText,
            tint: .blue
        )
    }

     
     
    @ViewBuilder
    private var previewLink: some View {
        ClashRoutedViewLink {
            ClashLazyView {
                FinalConfigurationTextView(
                    title: .copy(previewKind.rawValue),
                    text: selectedText
                )
            }
        } label: {
            previewLabel
        }
        .disabled(selectedText == nil)
        .accessibilityIdentifier("final-configuration.open-preview")
    }

#endif

#if os(macOS)
    private let footerCopy =
        "The captured source is what you pasted. Runtime is the config macOS actually runs — overrides applied, with your own credentials shown. For a profile that is already running, it is the revision that was activated: later edits appear here once you activate it again."
    private let fixedTitle = "Fixed by macOS"
    private let unsupportedTitle = "Not Used on macOS"
    private let adaptedTitle = "Prepared for macOS"
    private let adaptedEmptyDetail =
        "The stored source and effective comparison does not contain a known macOS rewrite."
    private let unsupportedEmptyTitle = "No Desktop or Inbound Fields"
    private let adaptedEmptyTitle = "No Known macOS Rewrite"
#else
    private let footerCopy =
        "The captured source is what you pasted. Runtime is the config iOS actually runs — overrides applied and desktop-only surfaces removed — with your own credentials shown. For a profile that is already running, it is the revision that was activated: later edits appear here once you activate it again."
    private let fixedTitle = "Fixed by iOS"
    private let unsupportedTitle = "Not Used on iOS"
    private let adaptedTitle = "Prepared for iOS"
    private let adaptedEmptyDetail =
        "The stored source and effective comparison does not contain a known iOS rewrite."
    private let unsupportedEmptyTitle = "No Desktop or Inbound Fields"
    private let adaptedEmptyTitle = "No Known iOS Rewrite"
#endif
     
     
     
     
     
     
    private let textFirst: Bool
     
     
    @State private var sourceOpened = false
#if os(macOS)
     
    @State private var showsPreviewText = false
    @Environment(\.clashDoorMayPush) private var mayPush
#endif

    init(
        title: String,
        sourceYAML: String?,
        effectiveYAML: String?,
         
         
         
         
         
         
         
         
         
         
         
        baseYAML: String? = nil,
         
         
         
         
        comparisonYAML: String? = nil,
        ownsNavigationContainer: Bool = true,
        command: ClashCommandClient? = nil,
        blockedRuleSets:
            (@Sendable () async -> [ProviderCompileVerdicts.Blocked])? = nil
    ) {
        self.init(
            title: title,
            snapshot: ProfileFinalConfigurationSnapshot.make(
                sourceYAML: sourceYAML,
                effectiveYAML: effectiveYAML
            ),
            sourceYAML: sourceYAML,
            comparisonYAML: comparisonYAML ?? sourceYAML,
            baseYAML: baseYAML,
            ownsNavigationContainer: ownsNavigationContainer,
            command: command,
            blockedRuleSets: blockedRuleSets
        )
    }

    init(
        title: String,
        snapshot: ProfileFinalConfigurationSnapshot,
        sourceYAML: String? = nil,
        comparisonYAML: String? = nil,
        baseYAML: String? = nil,
        ownsNavigationContainer: Bool = true,
        command: ClashCommandClient? = nil,
        blockedRuleSets:
            (@Sendable () async -> [ProviderCompileVerdicts.Blocked])? = nil,
        textFirst: Bool = false
    ) {
        self.title = title
        self.textFirst = textFirst
        self.ownsNavigationContainer = ownsNavigationContainer
        self.command = command
        blockedRuleSetsLoader = blockedRuleSets
        self.snapshot = snapshot
        self.sourceYAML = sourceYAML
        self.comparisonYAML = comparisonYAML
        self.baseYAML = baseYAML
    }

    var body: some View {
        if textFirst {
            textFirstBody
        } else {
            fullBody
        }
    }

#if os(macOS)
     
     
     
     
    private var textFirstBody: some View {
        ClashDeferredPageContent {
             
             
             
             
             
            ZStack {
                residentPanel(.effective)
                if sourceOpened || previewKind == .source {
                    residentPanel(.source)
                }
            }
            .onChange(of: previewKind) { kind in
                if kind == .source { sourceOpened = true }
            }
        } placeholder: {
            ClashPageLoadingPlaceholder(title: .copy("Opening Configuration"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clashPageTitle(.copy(title))
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .principal) {
                Picker(selection: $previewKind) {
                    ForEach(FinalConfigurationPreviewKind.allCases.reversed()) { kind in
                        Text(clash: .copy(kind.rawValue)).tag(kind)
                    }
                } label: {
                    Text(clash: .copy("Configuration"))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("final-configuration.preview-kind")
            }
        }
    }
#else
     
     
     
     
     
     
    private var textFirstBody: some View {
        ClashFeatureNavigationContainer(
            ownsNavigationContainer: ownsNavigationContainer
        ) {
            VStack(spacing: ClashTheme.Spacing.compact) {
                Picker(selection: $previewKind) {
                    ForEach(FinalConfigurationPreviewKind.allCases.reversed()) { kind in
                        Text(clash: .copy(kind.rawValue)).tag(kind)
                    }
                } label: {
                    Text(clash: .copy("Configuration"))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("final-configuration.preview-kind")

                ClashDeferredPageContent {
                    ZStack {
                        residentPanel(.effective)
                        if sourceOpened || previewKind == .source {
                            residentPanel(.source)
                        }
                    }
                    .onChange(of: previewKind) { kind in
                        if kind == .source { sourceOpened = true }
                    }
                } placeholder: {
                    ClashPageLoadingPlaceholder(title: .copy("Opening Configuration"))
                }
            }
            .padding(.horizontal, ClashTheme.Spacing.standard)
            .padding(.top, ClashTheme.Spacing.compact)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ClashTheme.canvas.ignoresSafeArea())
            .clashPageTitle(.copy(title))
            .clashFeaturePresentation(
                ownsNavigationContainer: ownsNavigationContainer
            )
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) {
                    if ownsNavigationContainer {
                        ClashSheetCloseButton { dismiss() }
                            .accessibilityIdentifier("final-configuration.done")
                    }
                }
            }
        }
        .clashCapturesDismiss(dismiss)
    }
#endif

     
     
     
     
    @ViewBuilder
    private func residentPanel(_ kind: FinalConfigurationPreviewKind) -> some View {
        let shown = previewKind == kind
        let text: String? = kind == .source ? snapshot.sourceText : snapshot.effectiveText
        let fingerprint = kind == .source ? snapshot.sourceFingerprint : snapshot.effectiveFingerprint
        Group {
            if let text {
                CodeEditorPanel(
                    text: .constant(text),
                    language: .yaml,
                    minHeight: 360,
                    isEditable: false,
                    expandsVertically: true
                )
                 
                 
                 
                 
                .id("\(kind.rawValue)#\(fingerprint)")
            } else {
                ClashEmptyState(
                    title: "Configuration Unavailable",
                    message: "Activate or sync this profile first.",
                    symbol: .docTextMagnifyingglass
                )
            }
        }
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown)
        .accessibilityHidden(!shown)
    }

    private var fullBody: some View {
        ClashFeatureNavigationContainer(
            ownsNavigationContainer: ownsNavigationContainer
        ) {
            List {
                Section {
                    Picker("Configuration", selection: $previewKind) {
                        ForEach(FinalConfigurationPreviewKind.allCases) { kind in
                            Text(clash: .copy(kind.rawValue)).tag(kind)
                        }
                    }
                    .clashIdiomFormPickerStyle()
                    .accessibilityIdentifier("final-configuration.preview-kind")

#if os(macOS)
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    if mayPush {
                        previewLink
                    } else {
                        Button {
                             
                             
                             
                             
                             
                             
                            ClashPageProbe.markNavigation()
                            showsPreviewText = true
                        } label: {
                            HStack(spacing: ClashTheme.Spacing.compact) {
                                previewLabel
                                Spacer(minLength: ClashTheme.Spacing.compact)
                                 
                                 
                                 
                                 
                                Image(
                                    systemName: ClashSymbol.chevronForward.rawValue
                                )
                                .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedText == nil)
                         
                         
                         
                         
                         
                         
                         
                        .listRowSeparator(.visible, edges: .bottom)
                        .accessibilityIdentifier("final-configuration.open-preview")
                    }
#else
                    ClashRoutedViewLink {
                        ClashLazyView {
                            FinalConfigurationTextView(
                                title: .copy(previewKind.rawValue),
                                text: selectedText
                            )
                        }
                    } label: {
                        disclosureLabel(
                            title: previewKind == .source
                                ? "View Captured Source"
                                : "View Runtime Configuration",
                            detail: selectedText == nil
                                ? "Not available yet"
                                : "Read-only",
                            symbol: .docText,
                            tint: .blue
                        )
                    }
                    .disabled(selectedText == nil)
                    .accessibilityIdentifier("final-configuration.open-preview")
#endif

#if os(macOS)
                     
                     
                     
                     
                     
                     
                     
                     
                    VStack(alignment: .leading, spacing: ClashTheme.Spacing.compact) {
                        if previewKind == .effective, let text = selectedText {
                            kernelVerdictRow(for: text)
                        }
                        sectionExplanationRow(footerCopy)
                    }
                    .listRowInsets(
                        EdgeInsets(top: 6, leading: 20, bottom: 8, trailing: 20)
                    )
                    .listRowSeparator(.hidden)
#else
                    if previewKind == .effective, let text = selectedText {
                        kernelVerdictRow(for: text)
                    }
#endif
                } header: {
                    Text("Compare")
                } footer: {
                     
                     
                     
                     
                     
                     
                     
#if !os(macOS)
                    Text(clash: .copy(footerCopy))
#endif
                }

                disclosureSection(
                    title: fixedTitle,
                    items: snapshot.fixedItems,
                    symbol: .checkmarkShieldFill,
                    tint: .blue,
                    identifierFragment: "fixed"
                )

                if Self.saysAllClear(
                    items: snapshot.unsupportedItems,
                    planLoaded: planNoticesLoaded,
                    planNotices: planNotices
                ) {
                    Section {
                        disclosureLabel(
                             
                             
                             
                             
                            title: unsupportedEmptyTitle,
                            detail: "This source does not request a desktop or inbound server surface.",
                            symbol: .checkmarkCircle,
                            tint: .green
                        )
                        .accessibilityIdentifier("final-configuration.unsupported.empty")
                    } header: {
                        Text(clash: .copy(unsupportedTitle))
                            .accessibilityIdentifier(
                                "final-configuration.unsupported.heading"
                            )
                    }
                } else {
                    disclosureSection(
                        title: unsupportedTitle,
                        items: snapshot.unsupportedItems,
                        symbol: .xmarkCircle,
                        tint: .orange,
                        identifierFragment: "unsupported"
                    )
                }

                if Self.saysAllClear(
                    items: snapshot.adaptedItems,
                    planLoaded: planNoticesLoaded,
                    planNotices: planNotices
                ) {
                    Section {
                        disclosureLabel(
                            title: adaptedEmptyTitle,
                            detail: adaptedEmptyDetail,
                            symbol: .checkmarkCircle,
                            tint: .green
                        )
                        .accessibilityIdentifier("final-configuration.adapted.empty")
                    } header: {
                        Text(clash: .copy(adaptedTitle))
                            .accessibilityIdentifier(
                                "final-configuration.adapted.heading"
                            )
                    }
                } else {
                    disclosureSection(
                        title: adaptedTitle,
                        items: snapshot.adaptedItems,
                        symbol: .arrowTriangle2Circlepath,
                        tint: .green,
                        identifierFragment: "adapted"
                    )
                }

                blockedRuleSetsSection
                planNoticesSection

                coreDeviationsSection
            }
            .task(id: snapshot.effectiveText) {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                deviations = nil
                deviations = await command?.configDeviations()

                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                if deviations == nil {
                    deviations = Self.offlineDeviations(for: snapshot.effectiveText)
                    deviationsAreOffline = deviations != nil
                } else if let live = deviations, live.document != nil,
                          !live.describes(snapshot.effectiveText) {
                     
                     
                     
                     
                     
                     
                     
                    deviations = Self.offlineDeviations(for: snapshot.effectiveText)
                    deviationsAreOffline = deviations != nil
                } else {
                    deviationsAreOffline = false
                }

                 
                 
                 
                 
                if let report = deviations, let written = comparisonYAML, let base = baseYAML {
                    let spoken = Set(report.deviations.map(\.configKey))
                    deviations = report.appending(
                        ClientDocumentDeviations
                            .rows(written: written, running: base, locale: locale)
                            .filter { !spoken.contains($0.configKey) }
                    )
                }
            }
             
             
             
            .task(id: snapshot.effectiveText) {
                 
                 
                 
                guard let text = snapshot.effectiveText else {
                     
                     
                     
                    planNotices = []
                    planNoticesLoaded = false
                    return
                }
                planNoticesLoaded = false
                planNotices = await Task.detached(priority: .utility) {
                     
                     
                     
                     
                     
                     
                     
                     
                    (try? ConfigTransforms.planResources(mergedYAML: text).notices) ?? []
                }.value
                planNoticesLoaded = true
            }
             
             
             
             
             
             
            .task(id: snapshot.effectiveText) {
                guard let loader = blockedRuleSetsLoader else {
                    blockedRuleSets = []
                    return
                }
                 
                 
                blockedRuleSets = await Task.detached(priority: .utility) {
                    await loader()
                }.value
            }
            .clashInsetGroupedListStyle()
            .clashPageTitle(.copy(title))
            .clashFeaturePresentation(
                ownsNavigationContainer: ownsNavigationContainer
            )
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) {
                    if ownsNavigationContainer {
                        ClashSheetCloseButton { dismiss() }
                            .accessibilityIdentifier(
                                "final-configuration.done"
                            )
                    }
                }
            }
        }
#if os(macOS)
         
         
         
        .clashProductModal(
            isPresented: $showsPreviewText,
            role: .form,
            macOSPanelRole: .page
        ) {
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            ClashDeferredPageContent {
                FinalConfigurationTextView(
                    title: .copy(previewKind.rawValue),
                    text: selectedText
                )
            } placeholder: {
                ClashPageLoadingPlaceholder(
                    title: .copy("Opening Configuration")
                )
            }
            .clashProductModalRoot(title: .copy(previewKind.rawValue))
        }
#endif
        .clashCapturesDismiss(dismiss)
    }

    private var selectedText: String? {
        switch previewKind {
        case .source: return snapshot.sourceText
        case .effective: return snapshot.effectiveText
        }
    }

#if os(macOS)
     
     
     
    private func sectionExplanationRow(_ copy: String) -> some View {
        Text(clash: .copy(copy))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
#endif

    @ViewBuilder
    private func disclosureSection(
        title: String,
        items: [ProfileFinalConfigurationDisclosure],
        symbol: ClashSymbol,
        tint: Color,
         
         
         
         
         
        identifierFragment: String
    ) -> some View {
        Section {
            ForEach(items) { item in
                disclosureLabel(
                    title: item.title,
                    detail: item.detail,
                    strippedKeys: item.strippedKeys,
                    lines: item.lines,
                    symbol: symbol,
                    tint: tint
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("final-configuration.\(identifierFragment).\(item.id)")
            }
        } header: {
            Text(clash: .copy(title))
                .accessibilityIdentifier(
                    "final-configuration.\(identifierFragment).heading"
                )
        }
    }

     
     
     
     
     
     
     
     
     
    private func kernelVerdictRow(for finalYAML: String) -> some View {
         
         
         
         
        HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.compact) {
            Image(
                systemName: verdict?.ok ?? true
                    ? ClashSymbol.checkmarkCircleFill.rawValue
                    : ClashSymbol.exclamationmarkTriangleFill.rawValue
            )
            .foregroundStyle(verdict?.ok ?? true ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(clash: verdict == nil
                    ? "Checking with the core…"
                    : (verdict?.ok == true
                        ? "The core accepts this configuration"
                        : "The core refuses this configuration"))
                    .font(.subheadline)
                if let message = verdict?.errorMessage, !message.isEmpty {
                     
                     
                    Text(clash: .verbatim(message))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .accessibilityIdentifier("final-configuration.kernel-verdict")
         
         
         
         
         
         
         
        .accessibilityValue(
            verdict == nil ? "checking"
                : (verdict?.ok == true ? "accepted" : "refused")
        )
        .task(id: finalYAML) {
            let yaml = finalYAML
            verdict = await Task.detached(priority: .userInitiated) {
                PreflightService.checkApplication(finalYAML: yaml)
            }.value
        }
    }

     
     
     
     
     
    @ViewBuilder
    private var blockedRuleSetsSection: some View {
        if !blockedRuleSets.isEmpty {
            Section {
                ForEach(blockedRuleSets) { set in
                    HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.compact) {
                        Image(systemName: ClashSymbol.xmarkCircle.rawValue)
                            .foregroundStyle(Color.orange)
                        VStack(alignment: .leading, spacing: 2) {
                             
                             
                             
                            Text(clash: .verbatim(set.name))
                                .font(.subheadline.weight(.medium))
                            Text(clash: .verbatim(set.reason))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(
                        "final-configuration.mrs.\(set.name)"
                    )
                }
            } header: {
                Text(clash: .copy("Rule Sets Not in the Runtime"))
                    .accessibilityIdentifier(
                        "final-configuration.mrs.heading"
                    )
            } footer: {
                Text(clash: .copy("Rule sets run from their compiled MRS form. A set that cannot be compiled is left out of the runtime — its rules never match. Each line is the core's own sentence."))
            }
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func saysAllClear(
        items: [ProfileFinalConfigurationDisclosure],
        planLoaded: Bool,
        planNotices: [String]
    ) -> Bool {
        items.isEmpty && planLoaded && planNotices.isEmpty
    }

     
     
     
     
     
     
     
     
    @ViewBuilder
    private var planNoticesSection: some View {
        if !planNotices.isEmpty {
            Section {
                ForEach(Array(planNotices.enumerated()), id: \.offset) { index, notice in
                    Text(clash: .verbatim(notice))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("final-configuration.plan-notice.\(index)")
                }
            } header: {
                Text(clash: .copy("What the Client Adapted"))
                    .accessibilityIdentifier("final-configuration.plan-notices.heading")
            } footer: {
                Text(clash: .copy("Written while preparing this configuration, before the core started. Each line is the core's own sentence about one field."))
            }
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    private var coreDeviationsSection: some View {
        if let report = deviations {
            Section {
                if report.isEmpty, report.describes(snapshot.effectiveText) {
                     
                     
                     
                     
                     
                     
                     
                    disclosureLabel(
                        title: "The core honoured every field",
                        detail: "Nothing in this configuration was removed, replaced or left inert by the core that is running.",
                        symbol: .checkmarkCircle,
                        tint: .green
                    )
                    .accessibilityIdentifier("final-configuration.deviations.empty")
                } else if report.isEmpty {
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    EmptyView()
                } else {
                    ForEach(report.deviations) { deviation in
                        ConfigDeviationRow(
                            deviation: deviation,
                            identifierPrefix: "final-configuration.deviation"
                        )
                    }
                }
#if os(macOS)
                sectionExplanationRow(deviationsAreOffline
                    ? "The core read the configuration above and answered without starting anything. Nothing is running."
                    : "Reported by the core itself for the configuration it is running, not derived from the text above. A profile that is not the running one is not described here.")
#endif
            } header: {
                Text(deviationsAreOffline
                     ? "What the Core Would Do"
                     : "What the Running Core Did")
                    .accessibilityIdentifier(
                        "final-configuration.deviations.heading"
                    )
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    .accessibilityValue("\(deviations?.deviations.count ?? 0)")
            } footer: {
#if !os(macOS)
                Text(deviationsAreOffline
                     ? "The core read the configuration above and answered without starting anything. Nothing is running."
                     : "Reported by the core itself for the configuration it is running, not derived from the text above. A profile that is not the running one is not described here.")
#endif
            }
        }
    }


     
     
     
     
     
     
     
    static func offlineDeviations(for effectiveText: String?) -> ConfigDeviationReport? {
        guard let effectiveText, !effectiveText.isEmpty else { return nil }
        return try? ConfigTransforms.configDeviations(
            configContent: effectiveText,
            targetProfile: clashAppleRuntimeProfile.rawValue
        )
    }

    private func disclosureLabel(
        title: String,
        detail: String,
        strippedKeys: [String] = [],
        lines: [String] = [],
        symbol: ClashSymbol,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: ClashTheme.Spacing.row) {
            ClashIconWell(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                Text(clash: .copy(title))
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(clash: .copy(detail))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !strippedKeys.isEmpty {
                     
                     
                     
                    Text("Stripped: \(strippedKeys.joined(separator: ", "))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(
                            "Stripped keys: \(strippedKeys.joined(separator: ", "))"
                        )
                }
                 
                 
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, ClashTheme.Spacing.tight)
    }
}

private struct FinalConfigurationTextView: View {
    let title: ClashDisplayText
    private let isAvailable: Bool
    @State private var text: String

    init(title: ClashDisplayText, text: String?) {
        self.title = title
        isAvailable = text != nil
        _text = State(initialValue: text ?? "")
    }

    var body: some View {
        ZStack {
            ClashTheme.canvas.ignoresSafeArea()
            if isAvailable {
                CodeEditorPanel(
                    text: $text,
                    language: .yaml,
                    minHeight: 360,
                    isEditable: false,
                    expandsVertically: true
                )
                .padding(ClashTheme.Spacing.standard)
            } else {
                ClashEmptyState(
                    title: "Configuration Unavailable",
                    message: "Activate or sync this profile first.",
                    symbol: .docTextMagnifyingglass
                )
            }
        }
        .clashPageTitle(title, watchAs: "profile-preview")
        .clashDetailPageInsets()
    }
}
