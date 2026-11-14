import ClashClientKit
import SwiftUI


 
 
 
 
struct ClashLibraryTabTitle: ViewModifier {
    let isCenterSection: Bool
    let standalone: ClashDisplayText

    @ViewBuilder
    func body(content: Content) -> some View {
        if !isCenterSection {
            content
                .clashPageTitle(standalone)
                .clashProductModalRoot(title: standalone)
        } else {
            content
        }
    }
}

public struct ClashConfigurationCenterSections<Profiles: View, Nodes: View, Rules: View>: View {
    @Environment(\.clashShellDrawsRootHeading) private var railOwnsHeading
    @State private var section = 0
    @Environment(\.locale) private var locale
    @Environment(\.clashRootDepartureGuard) private var departureGuard
    private let profiles: () -> Profiles
    private let nodes: () -> Nodes
    private let rules: () -> Rules
     
     
     
     
    private let revealsConfigurations: Int
     
     
     
     
     
     
     
     
    @State private var addedElsewhere = false
    public init(revealsConfigurations: Int = 0,
                @ViewBuilder profiles: @escaping () -> Profiles,
                @ViewBuilder nodes: @escaping () -> Nodes,
                @ViewBuilder rules: @escaping () -> Rules) {
        self.revealsConfigurations = revealsConfigurations
        self.profiles = profiles; self.nodes = nodes; self.rules = rules
    }
    public var body: some View {
         
         
         
         
         
         
         
         
         
         
         
        Group {
            switch section {
            case 1: nodes()
            case 2: rules()
            default: profiles()
            }
        }
        .clashRegularStripPage {
            ClashFullWidthSegmentedPicker(selection: Binding(get: { section }, set: { next in
                guard next != section else { return }
                ClashDeparture.request(departureGuard) { section = next }
            }), options: ["Configuration Library", "Node Library", "Rule Library"].enumerated().map { index, title in
                ClashFullWidthSegmentedOption(selection: index, title: ClashCopy.string(title, locale: locale),
                    accessibilityIdentifier: "configuration.center.tab.\(index)")
            }, role: .pageStrip)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, ClashTheme.Spacing.standard)
        }
         
         
         
         
         
        .clashRootHeading("Profile Center")
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .principal) {
                if !railOwnsHeading { Text("Profile Center").font(.headline) }
            }
        }
        .onChange(of: revealsConfigurations) { _ in
            if section != 0 { addedElsewhere = true }
        }
        .onChange(of: section) { next in
            if next == 0 { addedElsewhere = false }
        }
         
         
         
         
        .safeAreaInset(edge: .bottom) {
            if addedElsewhere {
                Button {
                    ClashDeparture.request(departureGuard) { section = 0 }
                } label: {
                    Text("View Added Configuration")
                }
                 
                .clashPrimaryActionButtonStyle()
                .controlSize(.large)
                .padding(.bottom, ClashTheme.Spacing.standard)
                .accessibilityIdentifier("configuration.center.view-added")
            }
        }
    }
}

public enum ClashConfigurationSourceKind: String, Identifiable, Sendable {
    case subscription, file, customNodes
    public var id: String { rawValue }
}

public struct ClashConfigurationLegacySource: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let nodeCount: Int
    public let providerCount: Int
    public var isSelectable: Bool { nodeCount > 0 || providerCount > 0 }
    public init(id: String, label: String, nodeCount: Int = 0, providerCount: Int = 0) {
        self.id = id; self.label = label; self.nodeCount = nodeCount; self.providerCount = providerCount
    }
}

 
 
public struct ClashConfigurationCreationView: View {
    @Binding private var draft: ConfigurationCreationDraft
    private let library: ConfigurationLibrarySnapshot
    private let palette: ClashProductPalette
    private let presentationClass: ClashPresentationClass
    private let icon: (ClashSymbol) -> AnyView
    private let legacy: [ClashConfigurationLegacySource]
    private let isBusy: Bool
    private let isReady: Bool
    private let reload: () -> Void
    private let error: String?
    private let addSource: (ClashConfigurationSourceKind) -> Void
    private let selectLegacy: (String) -> Void
    private let finish: (@escaping (Bool) -> Void) -> Void
    private let cancel: () -> Void
    private let editingStep: ConfigurationCreationDraft.Step?
    private let isEditing: Bool
     
    private let editingProfileID: String?
    private let baseline: ConfigurationCreationDraft
    private let sourceDetails: (String) -> Void
    private let manageSources: () -> Void
    private let manageRules: () -> Void
     
     
    private let completionNodes: ((ConfigurationCreationDraft) -> AnyView)?
    private let completionRules: ((ConfigurationCreationDraft) -> AnyView)?
    @State private var confirmsDiscard = false
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.clashInsideProductModalPresentation) private var insideProductModal

    public init(draft: Binding<ConfigurationCreationDraft>, library: ConfigurationLibrarySnapshot,
                palette: ClashProductPalette, presentationClass: ClashPresentationClass, icon: @escaping (ClashSymbol) -> AnyView,
                legacy: [ClashConfigurationLegacySource], isBusy: Bool, isReady: Bool, error: String?,
                reload: @escaping () -> Void,
                addSource: @escaping (ClashConfigurationSourceKind) -> Void,
                selectLegacy: @escaping (String) -> Void,
                finish: @escaping (@escaping (Bool) -> Void) -> Void,
                cancel: @escaping () -> Void,
                isEditing: Bool = false, editingProfileID: String? = nil, baseline: ConfigurationCreationDraft = .init(),
                editingStep: ConfigurationCreationDraft.Step? = nil,
                sourceDetails: @escaping (String) -> Void = { _ in },
                manageSources: @escaping () -> Void = {},
                manageRules: @escaping () -> Void = {},
                completionNodes: ((ConfigurationCreationDraft) -> AnyView)? = nil, completionRules: ((ConfigurationCreationDraft) -> AnyView)? = nil) {
        self.palette = palette; self.presentationClass = presentationClass; self.icon = icon
        self.completionNodes = completionNodes; self.completionRules = completionRules
        self.editingStep = editingStep
        self.isEditing = isEditing; self.editingProfileID = editingProfileID; self.baseline = baseline; self.sourceDetails = sourceDetails; self.manageSources = manageSources; self.manageRules = manageRules
        _draft = draft; self.library = library; self.legacy = legacy
        self.isBusy = isBusy; self.isReady = isReady; self.reload = reload; self.error = error; self.addSource = addSource
        self.selectLegacy = selectLegacy
        self.finish = finish; self.cancel = cancel
    }

    private var pageTitle: String {
        if editingStep == .sources { return "Node Sources" }
        if editingStep == .rules { return "Rule Scheme" }
        return switch draft.step {
        case .sources: "Select Nodes"
        case .rules: "Select Rules"
        case .finish: "Done"
        }
    }

    private var sources: [ConfigurationSourceRecord] { draft.sources(in:library).filter { $0.suppliesNodes && ($0.isListedInLibrary || draft.selectedSourceIDs.contains($0.id)) } }
    private var rules: [ConfigurationRuleScheme] { ClashConfigurationRuleChoices.schemes(draft: draft, library: library, profileID: editingProfileID) }
    private var canAdvance: Bool {
        guard isReady else { return false }
        return switch draft.step {
        case .sources: !draft.selectedSourceIDs.isEmpty
        case .rules: draft.selectedRuleID != nil
        case .finish: draft.originalSourceID != nil || (!draft.selectedSourceIDs.isEmpty && draft.selectedRuleID != nil)
        }
    }
    private var dirty: Bool {
        var value = draft
        value.step = baseline.step
        return value != baseline
    }
    private var usesWizard: Bool { editingStep == nil }
    private var isFinalStep: Bool { !usesWizard || draft.step == .finish }

    public var body: some View {
        Group {
            if usesWizard && draft.step == .finish {
                 
                 
                 
                 
                 
                ClashProductRootPage(palette: palette, accessibilityIdentifier: "configuration.create.completion") {
                    if let error {
                        Text(error).foregroundStyle(.red)
                        Button("Try Again") { finish { _ in } }
                            .disabled(isBusy || !canAdvance)
                            .accessibilityIdentifier("configuration.create.retry")
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .task(id: draft.originalSourceID) {
                    if error == nil, !isBusy, canAdvance { nameIfUnnamed(); finish { _ in } }
                }
            } else if draft.step == .sources {
                sourceList
            } else if draft.step == .rules {
                ruleList
            } else {
        Form {
            if let error {
                Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("configuration.create.error") }
            }
            if !isReady && !isBusy {
                Section { Button("Retry") { reload() }.accessibilityIdentifier("configuration.create.reload") }
            }
            if isBusy && !isReady { Section { ProgressView().accessibilityIdentifier("configuration.create.busy") } }
            switch draft.step {
            case .sources: sourceSections
            case .rules: ruleSections
            case .finish: finishSections
            }
        }
        .clashConfigurationFormSpacing()
            }
        }
        .id(draft.step)
        .onChange(of: draft.selectedSourceIDs) { _ in selectDefaultRule() }
        .onChange(of: isReady) { ready in if ready { selectDefaultRule() } }
        .clashPageTitle(usesWizard && draft.step != .finish ? .verbatim(ClashCopy.string(pageTitle, locale: locale) + (draft.step == .sources ? "  1/2" : "  2/2")) : .copy(pageTitle))
        .clashProductModalRoot(title: .copy(pageTitle))
        .accessibilityIdentifier("configuration.create.screen")
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement:.cancellationAction) {
                Button(ClashCopy.key(usesWizard && draft.step == .rules ? "Back" : "Cancel")) {
                    if draft.originalSourceID != nil { confirmsDiscard = true }
                    else if usesWizard && draft.step == .rules {
                        draft.step = .sources
                    } else if dirty { confirmsDiscard = true } else { cancel() }
                }
                    .disabled(isBusy)
                    .accessibilityIdentifier("configuration.create.cancel")
            }
            ToolbarItem(placement:.confirmationAction) {
                Button(action: advance) { ClashActionProgressLabel(.copy(primaryTitle), isBusy: isBusy) }
                    .disabled(isBusy || !canAdvance)
                    .accessibilityIdentifier("configuration.create.finish")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if insideProductModal {
                ClashModalActionBar(primaryTitle: primaryTitle,
                    primaryDisabled: isBusy || !canAdvance, isBusy: isBusy) { advance() }
            }
        }
         
        .clashRegistersDeparture(isDirty:dirty,isBusy:isBusy,whySaveIsBlocked: {
            isFinalStep && (draft.originalSourceID != nil || (draft.selectedRuleID != nil && !draft.selectedSourceIDs.isEmpty))
                ? nil : ClashDepartureSaveAnswer.incomplete
        },save: { completion in
            guard isFinalStep, draft.originalSourceID != nil || (draft.selectedRuleID != nil && !draft.selectedSourceIDs.isEmpty) else {
                completion(false); return
            }
            finish(completion)
        },discard: { draft = baseline })
        .interactiveDismissDisabled(dirty || isBusy)
        .clashUnsavedChangesAlert(
            isPresented: $confirmsDiscard,
            message: .copy("This profile has changes that have not been saved."),
            isBusy: isBusy,
            saveTitle: primaryTitle,
            saveDisabled: !canAdvance,
            save: { advance() },
            discard: { draft = baseline; cancel() }
        )
    }

    private var selectableLegacy: [ClashConfigurationLegacySource] {
        let known = Set(library.sources.map(\.id))
        return legacy.filter { item in item.isSelectable && !known.contains("legacy-" + item.id) }
    }

    private var sourceSelection: Binding<Set<String>> {
        Binding(get: { Set(draft.selectedSourceIDs) }, set: { selected in
             
            let existing = draft.selectedSourceIDs.filter { selected.contains($0) }
            let added = sources.map(\.id).filter { selected.contains($0) && !existing.contains($0) }
            draft.selectedSourceIDs = existing + added
            for item in selectableLegacy where selected.contains("legacy-" + item.id)
                && !draft.selectedSourceIDs.contains("legacy-" + item.id) {
                selectLegacy(item.id)
            }
        })
    }

    private func toggleSource(_ id: String) {
        var selected = sourceSelection.wrappedValue
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        sourceSelection.wrappedValue = selected
    }

    private var sourceList: some View {
        List {
            if let error { Section { Text(verbatim: error).foregroundStyle(.red) } }
            if isBusy && !isReady { Section { ProgressView() } }
            if !isReady && !isBusy { Section { Button("Retry", action: reload) } }
            sourceSections
        }
        .clashConfigurationFormSpacing()
    }

    private var sourceSections: some View {
         
         
         
        let availableLegacy = selectableLegacy
        let legacyIDs = Set(availableLegacy.map { "legacy-" + $0.id })
        let sources = self.sources.filter { !legacyIDs.contains($0.id) }
        return Group {
            sourceSelectionSection("From Profile URLs", items: sources.filter {
                if case .subscription = $0.origin { return $0.nodeChain == nil }; return false
            })
            sourceSelectionSection("From Files", items: sources.filter {
                guard $0.nodeChain == nil else { return false }
                switch $0.origin { case .file, .bundled: return true; default: return false }
            })
            sourceSelectionSection("Custom Nodes", items: sources.filter { $0.origin == .customNodes && $0.nodeChain == nil })
            sourceSelectionSection("Proxy Chains", items: sources.filter { $0.nodeChain != nil })
            if !availableLegacy.isEmpty {
                Section {
                    ForEach(availableLegacy) { item in
                        let id = "legacy-" + item.id
                        let chosen = draft.selectedSourceIDs.contains(id)
                        Button { toggleSource(id) } label: {
                            HStack(spacing: ClashTheme.Spacing.row) {
                                ClashSelectionCircle(isSelected: chosen)
                                selectionLabel(item.label, detail: sourceSummary(.init(id: id,
                                    label: item.label, origin: .file(item.label), nodeCount: item.nodeCount,
                                    providerCount: item.providerCount)), chosen: chosen)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                        .clashSelectionRowFill(chosen)
                        .accessibilityIdentifier("configuration.create.legacy.\(item.id)")
                    }
                } header: { Text("Existing Profiles") }
            }
             
             
             
             
             
            ClashConfigurationLibraryAddCard(kind: .nodes, palette: palette, nativeList: true,
                showsHeader: false, disabled: isBusy, action: { addSource(.subscription) })
                .accessibilityIdentifier("configuration.create.add.subscription")
             
             
             
             
        }.disabled(isBusy || !isReady)
    }

    @ViewBuilder
    private func sourceSelectionSection(_ title: String, items: [ConfigurationSourceRecord]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { source in
                    let chosen = draft.selectedSourceIDs.contains(source.id)
                    HStack(spacing: ClashTheme.Spacing.row) {
                        Button { toggleSource(source.id) } label: {
                            HStack(spacing: ClashTheme.Spacing.row) {
                                ClashSelectionCircle(isSelected: chosen)
                                selectionLabel(source.displayLabel(locale: locale), detail: sourceSummary(source), chosen: chosen)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                        Button { sourceDetails(source.id) } label: {
                            Image(systemName: "info.circle").foregroundStyle(.tint)
                                .frame(minWidth: 44, minHeight: 44)
                        }.buttonStyle(.borderless).accessibilityLabel("Source Details")
                            .accessibilityIdentifier("configuration.create.info.\(source.id)")
                    }
                    .clashSelectionRowFill(chosen)
                    .accessibilityIdentifier("configuration.create.source.\(source.id)")
                }
            } header: { Text(ClashCopy.key(title)) }
        }
    }

     
     
     
     
     
     
    private var ruleList: some View {
        List {
            if let error { Section { Text(verbatim: error).foregroundStyle(.red) } }
            if isBusy && !isReady { Section { ProgressView() } }
            if !isReady && !isBusy { Section { Button("Retry", action: reload) } }
            ruleSections
        }
        .clashConfigurationFormSpacing()
    }

    private var ruleSections: some View {
        Group {
            ForEach(ClashConfigurationRuleLibrarySection.allCases, id: \.self) { group in
                let items = rules.filter { group.contains($0, library: library) }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { rule in
                             
                             
                            let baseID = rule.plainViewBaseID ?? rule.id
                            let chosen = draft.selectedRuleID == rule.id
                            Button {
                                draft.selectedRuleID = chosen ? nil : rule.id
                            } label: {
                                HStack(spacing: ClashTheme.Spacing.row) {
                                    ClashSelectionMark(isSelected: chosen)
                                    selectionLabel(rule.displayLabel, detail: baseID == ConfigurationBuiltins.basicRuleID
                                        ? ClashCopy.string("China and local traffic use Direct; other traffic uses your selected nodes.", locale: locale)
                                        : baseID == ConfigurationBuiltins.lazyRuleID
                                            ? ClashCopy.string("Ready-made routing for AI, streaming, social and gaming services.", locale: locale) : nil,
                                        chosen: chosen)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(chosen ? .isSelected : [])
                            .accessibilityIdentifier("configuration.create.rule.\(baseID == ConfigurationBuiltins.basicRuleID ? "basic" : baseID == ConfigurationBuiltins.lazyRuleID ? "lazy" : rule.id)")
                        }
                    } header: { Text(ClashCopy.key(group.title)) }
                }
            }
            Section {
                Button("Manage Rule Schemes", action: manageRules)
                    .accessibilityIdentifier("configuration.create.manage-rules")
            }
        }.disabled(isBusy || !isReady)
    }

    private var finishSections: some View {
        Group {
            ClashProfileGroup(title: "Identity", palette: palette, presentationClass: presentationClass) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                            Text("Name").font(.caption).foregroundStyle(.secondary)
                            completionName
                        }
                    } else {
                        HStack(spacing: ClashTheme.Spacing.standard) {
                            Text("Name")
                            completionName.multilineTextAlignment(.trailing)
                        }
                    }
                }
                .padding(.vertical, ClashMacSettingsMetrics.rowVerticalInset(touch: ClashTheme.Spacing.row))
            }
            if draft.originalSourceID != nil {
                ClashProfileGroup(title: "Original Configuration", palette: palette, presentationClass: presentationClass) {
                    VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                        Text(verbatim: draft.newSources.first.map { $0.record.displayLabel(locale: locale) } ?? draft.label)
                        Text("Keep the document's nodes, rules and settings.").font(.footnote).foregroundStyle(.secondary)
                    }.padding(.vertical, ClashMacSettingsMetrics.rowVerticalInset(touch: ClashTheme.Spacing.row))
                }
            } else {
            ClashProfileGroup(title: "Configuration", palette: palette, presentationClass: presentationClass) {
                ClashRoutedViewLink(showsDisclosureIndicator: false) {
                    if let completionNodes { completionNodes(draft) }
                } label: {
                    ClashProfileActionRow(title: "Nodes",
                        symbol: .serverRack, tint: .primary, icon: icon)
                }.buttonStyle(.plain).disabled(completionNodes == nil)
                    .accessibilityIdentifier("configuration.create.review.sources")
                ClashRowDivider()
                ClashRoutedViewLink(showsDisclosureIndicator: false) {
                    if let completionRules { completionRules(draft) }
                } label: {
                    ClashProfileActionRow(title: "Rules",
                        subtitle: .verbatim(draft.selectedRuleID == ConfigurationBuiltins.basicRuleID
                            ? ClashCopy.string("Default Configuration", locale: locale)
                            : rules.first(where: { $0.id == draft.selectedRuleID })?.displayLabel ?? ""),
                        symbol: .ruleDomain, tint: .primary, icon: icon)
                }.buttonStyle(.plain).disabled(completionRules == nil)
                    .accessibilityIdentifier("configuration.create.review.rules")
            }
            }
        }.disabled(isBusy || !isReady)
    }

    private var completionName: some View {
        TextField("Name", text: $draft.label,
            prompt: Text(verbatim: draft.selectedSourceIDs.first.flatMap { id in sources.first(where: { $0.id == id }) }
                .map { $0.displayLabel(locale: locale) } ?? ""))
            .clashLabelsHiddenInSettingsIdiom()
            .submitLabel(.done)
            .accessibilityIdentifier("configuration.create.name")
    }

    private var primaryTitle: String {
        if usesWizard {
            if draft.step == .sources { return "Next" }
            if draft.step == .rules { return "Done" }
        }
        return "Save"
    }
     
     
     
     
     
    private func nameIfUnnamed() {
        guard draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let fromSource = ((draft.newSources.first?.record
            ?? draft.selectedSourceIDs.first.flatMap { id in sources.first { $0.id == id } })
            .map { $0.displayLabel(locale: locale) }
            ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        draft.label = fromSource.isEmpty ? ClashCopy.string("Profile", locale: locale) : fromSource
    }

    private func advance() {
        guard canAdvance, !isBusy else { return }
        if usesWizard && draft.step == .sources {
            draft.step = .rules
        } else if usesWizard && draft.step == .rules {
             
             
            nameIfUnnamed()
            finish { _ in }
        } else if !usesWizard, !dirty {
             
             
             
            cancel()
        } else {
            finish { _ in }
        }
    }
    private func selectDefaultRule() {
        guard !isEditing, draft.selectedRuleID == nil, !draft.selectedSourceIDs.isEmpty else { return }
        draft.selectedRuleID = ConfigurationBuiltins.basicRuleID
    }
    private func selectionLabel(_ label: String, detail: String?, chosen: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                Text(verbatim: label).font(.body.weight(chosen ? .semibold : .regular)).foregroundStyle(.primary).lineLimit(2)
                if let detail { Text(verbatim: detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
    private func sourceSummary(_ source: ConfigurationSourceRecord) -> String {
        source.isRetainedSnapshot == true ? ClashCopy.string("Saved Copy", locale: locale) : ClashConfigurationSourceCopy.summary(source, locale: locale)
    }
}

 
 
 
struct ClashConfigurationUpdateButton: View {
    let title: String
     
    var updatingTitle: String = "Updating Sources…"
    let isUpdating: Bool
    let disabled: Bool
    let action: () -> Void
    var body: some View {
        Button { if !isUpdating { action() } } label: {
            HStack(spacing: 10) {
                if isUpdating {
                    ProgressView().controlSize(.small).transition(.identity)
                } else {
                    Image(systemName: "arrow.clockwise").transition(.identity)
                }
                Text(ClashCopy.key(isUpdating ? updatingTitle : title))
                    .foregroundStyle(isUpdating ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
                Spacer(minLength: 0)
            }
            .frame(minHeight: 32)
            .padding(.vertical, ClashMacSettingsMetrics.rowVerticalInset(touch: ClashTheme.Spacing.row))
            .contentShape(Rectangle())
        }
         
         
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .disabled(disabled)
         
         
        .listRowInsets(ClashPlatformLayout.pageUsesSystemSettingsIdiom ? nil :
            EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
    }
}

struct ClashConfigurationUpdateStatus: View {
    let progress: String?
    let status: String?
    let error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let progress { Text(verbatim: progress).lineLimit(1).truncationMode(.middle) }
            if let status { Text(verbatim: status) }
            if let error { Text(verbatim: error).foregroundStyle(.red) }
        }.font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

public struct ClashConfigurationSourceDetailView: View {
     
    public var deletionUndoable = false
    public func deletingWithUndo(_ undoable: Bool = true) -> Self { var copy = self; copy.deletionUndoable = undoable; return copy }
    public let source: ConfigurationSourceRecord
    public let configurations: [String]
    public let isBusy: Bool
    public let isUpdating: Bool
    public let updateStatus: String?
    public let error: String?
    public let update: () -> Void
    public let close: () -> Void
    private let save: (String, ConfigurationSourceSettingsDraft?, @escaping (Bool) -> Void) -> Void
    private let deleteSource: (() -> Void)?
    private let editSource: (() -> Void)?
    @State private var confirmsDeletion = false
     
     
     
     
    @State private var draft: String?
    @State private var baseline: String?
    @State private var subscriptionDraft: ConfigurationSourceSettingsDraft
    @State private var subscriptionBaseline: ConfigurationSourceSettingsDraft
    @State private var confirmsDiscard = false
    @Environment(\.clashInsideProductModalPresentation) private var insideProductModal
    @Environment(\.locale) private var locale
    private var shownName: String { source.displayLabel(locale: locale) }
    private var nameField: Binding<String> { Binding(get: { draft ?? shownName }, set: { draft = $0 }) }
    private var isSubscription: Bool { if source.isRetainedSnapshot == true { return false }; if case .subscription = source.origin { return true }; return false }
    private var dirty: Bool { (draft ?? shownName) != (baseline ?? shownName) || (isSubscription && subscriptionDraft != subscriptionBaseline) }
    private var subscriptionValid: Bool {
        guard isSubscription else { return true }
        let url = URLComponents(string: subscriptionDraft.url.trimmingCharacters(in: .whitespacesAndNewlines))
        return url?.scheme != nil && !(url?.host?.isEmpty ?? true) && url?.url != nil
    }
    private var canSave: Bool { !isBusy && subscriptionValid && !(draft ?? shownName).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public init(source: ConfigurationSourceRecord, configurations: [String], isBusy: Bool,
                error: String?, isUpdating: Bool = false, updateStatus: String? = nil, update: @escaping () -> Void,
                save: @escaping (String, ConfigurationSourceSettingsDraft?, @escaping (Bool) -> Void) -> Void, close: @escaping () -> Void,
                deleteSource: (() -> Void)? = nil, editSource: (() -> Void)? = nil) {
        self.isUpdating = isUpdating; self.updateStatus = updateStatus
        self.editSource = editSource
        self.source = source; self.configurations = configurations; self.isBusy = isBusy
        self.error = error; self.update = update; self.close = close; self.save = save; self.deleteSource = deleteSource
        let settings = ConfigurationSourceSettingsDraft(source: source)
        _subscriptionDraft = State(initialValue: settings); _subscriptionBaseline = State(initialValue: settings)
    }
    public var body: some View {
        Form {
            Section {
                HStack {
                    Text("Name")
                    TextField("Name", text: nameField).disabled(isBusy || source.isRetainedSnapshot == true)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("Name")
                        .accessibilityIdentifier("configuration.source.name")
                }
                switch source.origin {
                case .subscription: EmptyView()
                case .file(let name), .bundled(let name):
                    if name != source.label { Text(verbatim: name).foregroundStyle(.secondary) }
                case .customNodes: Text("Custom Nodes")
                }
            }
            if let usage = source.subscriptionUsage {
                Section("Data Usage") { ClashConfigurationSubscriptionUsageView(usage: usage, detailed: true) }
            }
            if isSubscription {
                ClashConfigurationSubscriptionFields(draft: $subscriptionDraft).disabled(isBusy)
            }
            if source.isRetainedSnapshot == true {
                Section { Text("This saved copy no longer receives source updates.").foregroundStyle(.secondary) }
            }
            if let editSource, source.isRetainedSnapshot != true {
                Section {
                    Button("Edit Nodes Source", action: editSource).buttonStyle(.plain).foregroundStyle(.primary).disabled(isBusy || dirty)
                        .accessibilityIdentifier("configuration.source.editSource")
                } footer: {
                    if case .subscription = source.origin {
                        Text("Profile URL updates replace local node edits.")
                    }
                }
            }
            if !configurations.isEmpty {
                Section("Used by Profiles") {
                    ForEach(Array(configurations.enumerated()), id: \.offset) { _, name in Text(verbatim: name) }
                }
            }
            if case .subscription = source.origin {
                Section {
                    ClashConfigurationUpdateButton(title: "Update Source", isUpdating: isUpdating,
                        disabled: dirty || (isBusy && !isUpdating), action: update)
                        .accessibilityIdentifier("configuration.source.update")
                } footer: {
                    ClashConfigurationUpdateStatus(progress: isUpdating ? "1 / 1 · " + source.displayLabel(locale: locale) : nil,
                        status: updateStatus, error: error)
                        .accessibilityIdentifier("configuration.source.update-status")
                }
            }
            if deleteSource != nil, canDelete, source.isRetainedSnapshot != true {
                Section {
                    Button("Delete Source", role: .destructive) { if deletionUndoable { deleteSource?() } else { confirmsDeletion = true } }
                        .disabled(isBusy || dirty)
                        .accessibilityIdentifier("configuration.source.delete")
                }
            }
            if case .subscription = source.origin {} else if let error {
                Section { Text(verbatim: error).foregroundStyle(.red).accessibilityIdentifier("configuration.source.error") }
            }
        }
        .clashPageTitle("Source Details")
        .clashProductModalRoot(title: "Source Details")
        .accessibilityIdentifier("configuration.source.detail")
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { if dirty { confirmsDiscard = true } else { close() } }
                    .disabled(isBusy).accessibilityIdentifier("configuration.source.close")
            }
            ToolbarItem(placement: .confirmationAction) {
                if dirty {
                    Button { submit { _ in } } label: { ClashActionProgressLabel(.copy("Save"), isBusy: isBusy) }.disabled(!canSave)
                        .accessibilityIdentifier("configuration.source.save")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if insideProductModal && dirty {
                ClashModalActionBar(primaryTitle: "Save", primaryDisabled: !canSave, isBusy: isBusy) {
                    submit { _ in }
                }
            }
        }
        .clashRegistersDeparture(isDirty: dirty, isBusy: isBusy, whySaveIsBlocked: {
            subscriptionValid && !(draft ?? shownName).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : ClashDepartureSaveAnswer.incomplete
        }, save: submit, discard: { restoreDraft() })
        .interactiveDismissDisabled(dirty || isBusy)
        .clashDeleteConfirmation(shownName, isPresented: $confirmsDeletion,
            actionTitle: .copy("Delete Source"),
             
             
            message: source.suppliesNodes
                ? .copy("Configurations that use this source lose its nodes.")
                : .copy("Saved profiles keep their current content and stop following this source."),
            identifier: "configuration.source.delete.confirm") { deleteSource?() }
        .confirmationDialog("Discard Changes?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { restoreDraft(); close() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var canDelete: Bool {
        if case .bundled = source.origin { return false }
        return true
    }

    private func restoreDraft() {
        draft = baseline; subscriptionDraft = subscriptionBaseline
    }

    private func submit(_ completion: @escaping (Bool) -> Void) {
        guard canSave else { completion(false); return }
        let name = (draft ?? shownName).trimmingCharacters(in: .whitespacesAndNewlines)
        let settings = isSubscription ? subscriptionDraft : nil
         
         
         
         
        let saved = ClashConfigurationSourceCopy.nameToStore(name, origin: source.origin, locale: locale)
        save(saved, settings) { succeeded in
            if succeeded {
                 
                 
                 
                 
                 
                 
                 
                 
                let kept: String? = ConfigurationSourceRecord.isBuiltinName(saved, origin: source.origin) ? nil : name
                baseline = kept; draft = kept
                if let settings { subscriptionBaseline = settings }
            }
            completion(succeeded)
        }
    }
}

private extension View {
    @ViewBuilder
    func clashConfigurationResolverInput() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never).keyboardType(.URL).disableAutocorrection(true)
        #else
        self.disableAutocorrection(true)
        #endif
    }
}

 
public struct ClashConfigurationSourceLibraryView: View {
    @Environment(\.locale) private var locale
    @AppStorage("configuration.library.expandedSources") private var expandedSourceIDs = ""
    @Environment(\.clashInsideProductModalPresentation) private var insideProductModal
    public let library: ConfigurationLibrarySnapshot
    public let isReady: Bool
    public let isBusy: Bool
    public let error: String?
    public let palette: ClashProductPalette
    public let status: String?
    public let updateProgress: String?
    public let add: (ClashConfigurationSourceKind) -> Void
    public let open: (String) -> Void
    public let reload: () -> Void
    public let close: () -> Void
    public let isCenterSection: Bool
    public let showsClose: Bool
    public let collections: [ConfigurationCollectionEntry]
    public let openCollection: (ConfigurationCollectionEntry) -> Void
    public let updateAll: (() -> Void)?
     
    public let refreshAll: (() async -> Void)?
     
     
    public let quickAdd: (() -> AnyView)?
     
     
    public let addMenu: (() -> AnyView)?
     
     
    public let refusals: [String: String]
     
     
     
    public let updateSource: ((String) -> Void)?
    public let copySourceLink: ((String) -> Void)?
    public let deleteSource: ((String) -> Void)?
    public init(library: ConfigurationLibrarySnapshot, palette: ClashProductPalette, isReady: Bool, isBusy: Bool, error: String?,
                add: @escaping (ClashConfigurationSourceKind) -> Void, open: @escaping (String) -> Void,
                reload: @escaping () -> Void, close: @escaping () -> Void, updateAll: (() -> Void)? = nil, refreshAll: (() async -> Void)? = nil, status: String? = nil, updateProgress: String? = nil, isCenterSection: Bool = false, showsClose: Bool = true,
                collections: [ConfigurationCollectionEntry] = [], openCollection: @escaping (ConfigurationCollectionEntry) -> Void = { _ in },
                quickAdd: (() -> AnyView)? = nil, addMenu: (() -> AnyView)? = nil,
                refusals: [String: String] = [:], updateSource: ((String) -> Void)? = nil,
                copySourceLink: ((String) -> Void)? = nil, deleteSource: ((String) -> Void)? = nil) {
        self.collections = collections; self.openCollection = openCollection; self.quickAdd = quickAdd
        self.addMenu = addMenu
        self.refusals = refusals
        self.updateSource = updateSource; self.copySourceLink = copySourceLink; self.deleteSource = deleteSource
        self.palette = palette
        self.updateAll = updateAll; self.refreshAll = refreshAll; self.status = status; self.updateProgress = updateProgress
        self.isCenterSection = isCenterSection; self.showsClose = showsClose
        self.library = library; self.isReady = isReady; self.isBusy = isBusy; self.error = error
        self.add = add; self.open = open; self.reload = reload; self.close = close
    }
    public var body: some View {
        let _ = ClashPerf.count("nodes.tab.body")
        ClashConfigurationLibraryList(palette: palette, accessibilityIdentifier: "configuration.library.sources.content") {
            if !isReady {
                ClashConfigurationLibraryCard(palette: palette, nativeList: true) {
                    if isBusy {
                        ProgressView("Loading Sources…")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    } else {
                        if let error { Text(verbatim: error).foregroundStyle(.red) }
                        Button("Retry", action: reload)
                    }
                }
            }
            let sources = library.availableSources.filter { $0.suppliesNodes }
             
             
             
             
             
            if isReady && quickAdd == nil && sources.isEmpty
                && !collections.contains(where: { $0.source.isListedInLibrary }) {
                ClashConfigurationLibraryCard(palette: palette, nativeList: true) { Text("No Sources Yet").foregroundStyle(.secondary) }
            }
            sourceSection("From Profile URLs", sources: sources.filter {
                if case .subscription = $0.origin { return true }; return false
            })
            sourceSection("From Files", sources: sources.filter {
                switch $0.origin { case .file, .bundled: return true; default: return false }
            })
            sourceSection("Custom Nodes", sources: sources.filter { $0.origin == .customNodes && $0.nodeChain == nil })
            sourceSection("Proxy Chains", sources: sources.filter { $0.nodeChain != nil })
            if isReady {
                if !hasUpdates, let error { ClashConfigurationLibraryCard(palette: palette, nativeList: true) { Text(verbatim: error).foregroundStyle(.red) } }
                if let updateAll, hasUpdates {
                    Section {
                         
                         
                        ClashConfigurationUpdateButton(title: "Update All", isUpdating: isBusy, disabled: false, action: updateAll)
                            .accessibilityIdentifier("configuration.library.update-all")
                    } footer: {
                         
                         
                        if updateProgress != nil || status != nil || error != nil {
                            ClashConfigurationUpdateStatus(progress: updateProgress, status: status, error: error)
                                .accessibilityIdentifier("configuration.library.update-status")
                        }
                    }
                }
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                if let quickAdd { quickAdd() } else {
                    ClashConfigurationLibraryAddCard(kind: .nodes, palette: palette, nativeList: true,
                        disabled: isBusy || !isReady, action: { add(.subscription) })
                        .accessibilityIdentifier("configuration.library.sources.add-card")
                }
                Section {} footer: {
                    Text(clash: .copy("These nodes are a source of their own. A configuration uses them once it turns this source on, under Node Sources."))
                        .accessibilityIdentifier("configuration.library.sources.what-this-is")
                }
            }
        }
         
         
         
         
        .modifier(ClashLibraryPullToUpdate(action: isReady && hasUpdates ? (refreshAll ?? updateAll.map { run in { run() } }) : nil))
        .modifier(ClashLibraryTabTitle(isCenterSection: isCenterSection, standalone: .copy("Manage Sources")))
        .accessibilityIdentifier("configuration.library.sources")
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .primaryAction) {
                 
                 
                 
                if let addMenu { addMenu() }
                else { addButton.disabled(isBusy || !isReady) }
            }
            ToolbarItem(placement: .cancellationAction) {
                if showsClose { ClashSheetCloseButton(dismiss: close).disabled(isBusy) }
            }
        }
        .clashRegistersDeparture(isDirty: false, isBusy: isBusy, save: { $0(false) }, discard: {})
        .interactiveDismissDisabled(isBusy)
    }
     
     
    private var hasUpdates: Bool {
        let sources = library.availableSources.filter { $0.suppliesNodes }
        return updateAll != nil && (sources.contains(where: { if case .subscription = $0.origin { return true }; return false })
            || collections.contains(where: { $0.id.kind == .nodes && $0.collection.type == "http" && $0.source.isRetainedSnapshot != true }))
    }

    @ViewBuilder
    private func sourceSection(_ title: String, sources: [ConfigurationSourceRecord]) -> some View {
        if !sources.isEmpty {
            ClashConfigurationLibraryCard(title: .copy(title), count: sources.count, palette: palette, nativeList: true, systemRowInsets: true) {
                ForEach(sources) { source in
                    let children = collections.filter { $0.source.id == source.id && $0.id.kind == .nodes }
                    let usage = source.subscriptionUsage
                     
                     
                     
                     
                     
                     
                    if children.isEmpty {
                        sourceRow(source, usage: usage, showsInfo: true)
                    } else {
                        DisclosureGroup(isExpanded: expansion(source.id)) {
                            ForEach(children) { entry in
                                Button { openCollection(entry) } label: {
                                     
                                     
                                     
                                    ClashConfigurationLibraryRow(title: entry.collection.name,
                                        count: ClashConfigurationCollectionCopy.summary(entry), usage: entry.subscriptionUsage)
                                }.buttonStyle(.plain)
                                    .accessibilityIdentifier("configuration.collection.\(source.id).proxy-providers.\(entry.collection.name)")
                            }
                        } label: {
                            sourceRow(source, usage: usage, showsInfo: false)
                        }
                    }
                }
            }
        }
    }

    private func sourceRow(_ source: ConfigurationSourceRecord, usage: ConfigurationSubscriptionUsage?, showsInfo: Bool) -> some View {
        Button { if !isBusy { open(source.id) } } label: {
             
             
             
            ClashConfigurationLibraryRow(title: source.displayLabel(locale: locale),
                count: .verbatim(ClashConfigurationSourceCopy.summary(source, locale: locale)),
                showsInfo: showsInfo, usage: usage, failure: refusals[source.id])
        }
        .buttonStyle(.plain)
         
         
         
        .accessibilityIdentifier("configuration.library.source.\(source.id)")
        .contextMenu { sourceMenu(source) }
         
         
        .clashSwipeToDelete(identifier: "configuration.library.source.swipe-delete", disabled: isBusy,
                           deleteSource != nil && Self.rowActions(source).contains(.delete) ? { deleteSource?(source.id) } : nil)
    }

     
     
     
     
    public enum RowAction: Hashable, Sendable { case update, copyLink, delete }

    public static func rowActions(_ source: ConfigurationSourceRecord) -> [RowAction] {
        var actions: [RowAction] = []
        if case .subscription = source.origin {
            if source.isRetainedSnapshot != true { actions.append(.update) }
            actions.append(.copyLink)
        }
        if source.isRetainedSnapshot != true {
            if case .bundled = source.origin {} else { actions.append(.delete) }
        }
        return actions
    }

     
     
     
    @ViewBuilder
    private func sourceMenu(_ source: ConfigurationSourceRecord) -> some View {
        let actions = Self.rowActions(source)
        if actions.contains(.update), let updateSource {
            Button { updateSource(source.id) } label: {
                Label { Text("Update") } icon: { Image(systemName: ClashSymbol.arrowClockwise.rawValue) }
            }
            .disabled(isBusy)
            .accessibilityIdentifier("configuration.library.source.update")
        }
        if actions.contains(.copyLink), let copySourceLink {
            Button { copySourceLink(source.id) } label: {
                Label { Text("Copy Link") } icon: { Image(systemName: ClashSymbol.link.rawValue) }
            }
            .accessibilityIdentifier("configuration.library.source.copy-link")
        }
        if actions.contains(.delete), let deleteSource {
            Button(role: .destructive) { deleteSource(source.id) } label: {
                Label { Text("Delete") } icon: { Image(systemName: ClashSymbol.trash.rawValue) }
            }
            .disabled(isBusy)
            .accessibilityIdentifier("configuration.library.source.delete")
        }
    }

     
     
    private func expansion(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expandedSourceIDs.split(separator: "\n").contains { $0 == id } },
            set: { open in
                 
                 
                let live = Set(library.sources.map(\.id))
                var ids = expandedSourceIDs.split(separator: "\n").map(String.init)
                    .filter { $0 != id && live.contains($0) }
                if open { ids.append(id) }
                expandedSourceIDs = ids.joined(separator: "\n")
            }
        )
    }

    private var addButton: some View {
        Button { add(.subscription) } label: { Image(systemName: ClashSymbol.plusCircle.rawValue).clashToolbarGlyph() }
        .disabled(isBusy || !isReady)
        .accessibilityLabel(ClashCopy.key(ClashConfigurationAddition.nodes.entryTitle))
        .accessibilityIdentifier("configuration.library.add")
    }

}

public struct ClashConfigurationRuleLibraryView: View {
    public let library: ConfigurationLibrarySnapshot
    public let isReady: Bool
    public let isBusy: Bool
    public let error: String?
    public let newRule: () -> Void
    public let importRules: () -> Void
    public let open: (String) -> Void
    public let reload: () -> Void
    public let close: () -> Void
    public let isCenterSection: Bool
    public let showsClose: Bool
    @Environment(\.clashInsideProductModalPresentation) private var insideProductModal
    public init(library: ConfigurationLibrarySnapshot, isReady: Bool, isBusy: Bool, error: String?,
                importRules: @escaping () -> Void, newRule: @escaping () -> Void, open: @escaping (String) -> Void,
                reload: @escaping () -> Void, close: @escaping () -> Void, isCenterSection: Bool = false, showsClose: Bool = true) {
        self.isCenterSection = isCenterSection; self.showsClose = showsClose
        self.library = library; self.isReady = isReady; self.isBusy = isBusy; self.error = error
        self.newRule = newRule; self.importRules = importRules; self.open = open; self.reload = reload; self.close = close
    }
    private var schemes: [ConfigurationRuleScheme] {
        library.availableRules + ConfigurationBuiltins.schemes.filter { item in !library.rules.contains { $0.id == item.id } }
    }
    public var body: some View {
        Form {
            if let error { Section { Text(verbatim: error).foregroundStyle(.red) } }
            if !isReady { Section { Button("Retry", action: reload).disabled(isBusy) } }
            if isBusy { ProgressView() }
            if isReady {
                ForEach(ClashConfigurationRuleLibrarySection.allCases, id: \.self) { group in
                    let items = schemes.filter { group.contains($0, library: library) }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { scheme in
                                Button { open(scheme.id) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        if scheme.id == ConfigurationBuiltins.basicRuleID { Text("Default Configuration") }
                                        else { Text(verbatim: scheme.displayLabel) }
                                        Text(clash: .format("Used by %@ profiles", [String(library.recipes.filter { $0.ruleSchemeID == scheme.id }.count)]))
                                            .font(.footnote).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityIdentifier("configuration.rules.item.\(scheme.id)")
                            }
                        } header: { Text(ClashCopy.key(group.title)) }
                    }
                }
                if insideProductModal { Section { addMenu } }
            }
        }
        .disabled(isBusy)
        .modifier(ClashLibraryTabTitle(isCenterSection: isCenterSection, standalone: .copy("Manage Rule Schemes")))
        .accessibilityIdentifier("configuration.rules.library")
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .primaryAction) { addMenu.disabled(isBusy || !isReady) }
            ToolbarItem(placement: .cancellationAction) {
                if showsClose { ClashSheetCloseButton(dismiss: close) }
            }
        }
        .clashRegistersDeparture(isDirty: false, isBusy: isBusy, save: { $0(false) }, discard: {})
        .interactiveDismissDisabled(isBusy)
    }
    private var addMenu: some View {
        Menu {
            Button("New Rule Scheme", action: newRule).accessibilityIdentifier("configuration.rules.new")
            Button("Import Rules", action: importRules).accessibilityIdentifier("configuration.rules.import")
            Button("Copy Default Configuration") { open(ConfigurationBuiltins.basicRuleID) }
                .accessibilityIdentifier("configuration.rules.copy-basic")
        } label: { Image(systemName: ClashSymbol.plusCircle.rawValue).clashToolbarGlyph() }
        .accessibilityLabel("Add Rule Scheme")
        .accessibilityIdentifier("configuration.rules.add")
    }

}

public struct ClashConfigurationRuleSchemeDetailView: View {
     
    public var deletionUndoable = false
    public func deletingWithUndo(_ undoable: Bool = true) -> Self { var copy = self; copy.deletionUndoable = undoable; return copy }
    public let scheme: ConfigurationRuleScheme
    public let source: ConfigurationSourceRecord
    public let configurations: [String]
    public let isBusy: Bool
    public let error: String?
    public let browseGroups: () -> Void
    public let browseRules: (() -> Void)?
    public let edit: (() -> Void)?
    public let copy: (String) -> Void
    public let update: (() -> Void)?
    public let delete: () -> Void
    public let close: () -> Void
    @State private var confirmsDeletion = false
    @Environment(\.locale) private var locale
    public init(scheme: ConfigurationRuleScheme, source: ConfigurationSourceRecord, configurations: [String],
                isBusy: Bool, error: String?, browseGroups: @escaping () -> Void, edit: (() -> Void)? = nil, copy: @escaping (String) -> Void, update: (() -> Void)? = nil,
                delete: @escaping () -> Void, close: @escaping () -> Void, browseRules: (() -> Void)? = nil) {
        self.scheme = scheme; self.source = source; self.configurations = configurations
        self.browseRules = browseRules
        self.browseGroups = browseGroups; self.isBusy = isBusy; self.error = error; self.edit = edit; self.copy = copy; self.update = update; self.delete = delete; self.close = close
    }
    private var name: String { scheme.id == ConfigurationBuiltins.basicRuleID ? ClashCopy.string("Default Configuration", locale: locale) : scheme.displayLabel }
    private var readOnly: Bool { scheme.kind == .builtin || scheme.kind == .community || scheme.isRetainedSnapshot == true }
    public var body: some View {
        Form {
            Section {
                Text(verbatim: name)
                Button(action: browseGroups) {
                    HStack {
                        Text("Policy Groups").foregroundStyle(.primary)
                        Spacer()
                        Text(verbatim: String(source.groupCount)).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("configuration.rule.groups.open")
                if let browseRules {
                    Button(action: browseRules) {
                        HStack { Text("Rules"); Spacer(); Text(verbatim: String(source.ruleCount)); Image(systemName: "chevron.right") }
                    }.accessibilityIdentifier("configuration.rule.contents")
                } else {
                HStack { Text("Rules"); Spacer(); Text(verbatim: String(source.ruleCount)) }
                }
                if case .subscription(let url) = source.origin { Text(verbatim: url).font(.footnote).textSelection(.enabled) }
            }
            if !configurations.isEmpty {
                Section("Used by Profiles") {
                    ForEach(Array(configurations.enumerated()), id: \.offset) { _, name in Text(verbatim: name) }
                }
            }
            Section {
                if let edit, scheme.isRetainedSnapshot != true { Button("Edit", action: edit).accessibilityIdentifier("configuration.rule.edit") }
                Button("Copy Rule Scheme") { copy(ClashCopy.string("Copy", locale: locale) + " · " + name) }
                    .accessibilityIdentifier("configuration.rule.copy")
                if let update, scheme.isRetainedSnapshot != true {
                    Button("Update", action: update).accessibilityIdentifier("configuration.rule.update")
                }
            } footer: { if edit == nil { Text("Copy this rule scheme to make changes.") } }
            if !readOnly {
                Section {
                    Button("Delete Rule Scheme", role: .destructive) { if deletionUndoable { delete() } else { confirmsDeletion = true } }
                        .accessibilityIdentifier("configuration.rule.delete")
                }
            }
            if let error { Section { Text(verbatim: error).foregroundStyle(.red) } }
        }
        .disabled(isBusy)
        .clashPageTitle("Rule Scheme")
        .clashProductModalRoot(title: "Rule Scheme")
        .accessibilityIdentifier("configuration.rule.detail")
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: close).disabled(isBusy).accessibilityIdentifier("configuration.rule.close")
            }
        }
        .interactiveDismissDisabled(isBusy)
        .clashDeleteConfirmation(name, isPresented: $confirmsDeletion,
            actionTitle: .copy("Delete Rule Scheme"),
            message: .copy("Saved profiles keep their current rules and stop following this scheme."),
            identifier: "configuration.rule.delete.confirm", action: delete)
    }
}

 
 
public struct ClashConfigurationRuleEditingView: View {
    @State private var draft: ConfigurationRuleDraft
    @State private var baseline: ConfigurationRuleDraft
    @State private var editing: RuleRoute?
    @State private var editingGroup: GroupRoute?
    @State private var groupError: String?
    @State private var confirmsDiscard = false
    private let isBusy: Bool
    private let error: String?
    private let save: (ConfigurationRuleDraft, @escaping (Bool) -> Void) -> Void
    private let close: () -> Void
    private let ruleEditor: (String, ConfigurationRuleDraft, @escaping (String, Bool, String) -> Void, (() -> Void)?) -> AnyView
    private let groupEditor: (ConfigurationRuleDraft, UUID?, @escaping (OrderedJSON) -> Void) -> AnyView
    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.clashInsideProductModalPresentation) private var insideProductModal
    private struct GroupRoute: Identifiable { let id = UUID(); let groupID: UUID? }
    private struct RuleRoute: Identifiable {
        let id = UUID()
        let rowID: UUID?
        let raw: String
    }
    public init(draft: ConfigurationRuleDraft, isBusy: Bool, error: String?,
                save: @escaping (ConfigurationRuleDraft, @escaping (Bool) -> Void) -> Void,
                close: @escaping () -> Void,
                ruleEditor: @escaping (String, ConfigurationRuleDraft, @escaping (String, Bool, String) -> Void, (() -> Void)?) -> AnyView,
                groupEditor: @escaping (ConfigurationRuleDraft, UUID?, @escaping (OrderedJSON) -> Void) -> AnyView) {
        _draft = State(initialValue: draft); _baseline = State(initialValue: draft)
        self.isBusy = isBusy; self.error = error; self.save = save; self.close = close; self.ruleEditor = ruleEditor; self.groupEditor = groupEditor
    }
    private var dirty: Bool { draft != baseline }
    private var canSave: Bool { dirty && !isBusy && (try? draft.document()) != nil }
    public var body: some View {
        Form {
            Section { TextField("Name", text: $draft.label).accessibilityIdentifier("configuration.rule.editor.name") }
            Section("Policy Groups") {
                 
                let types = ConfigurationTypeWords.names(.proxyGroups, copy: fieldCopy, locale: locale)
                ForEach(draft.groups) { group in
                    Button { editingGroup = .init(groupID: group.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: group.name).foregroundStyle(.primary).lineLimit(2)
                            Text(verbatim: ConfigurationTypeWords.word(group.type, in: types)).font(.footnote).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("configuration.rule.editor.group.\(group.id)")
                }
                .onDelete { offsets in
                    do {
                        try draft.removeGroups(Set(offsets.compactMap { draft.groups.indices.contains($0) ? draft.groups[$0].id : nil }))
                        groupError = nil
                    } catch { groupError = ClashConfigurationRuleGroupCopy.message(error, locale: locale) }
                }
                .onMove { offsets, destination in
                    let ids = Set(offsets.compactMap { draft.groups.indices.contains($0) ? draft.groups[$0].id : nil })
                    draft.moveGroups(ids, before: draft.groups.indices.contains(destination) ? draft.groups[destination].id : nil)
                }
                Button("Add Group") { editingGroup = .init(groupID: nil) }.buttonStyle(.plain).foregroundStyle(.primary)
                    .accessibilityIdentifier("configuration.rule.editor.group.add")
                if let groupError { Text(verbatim: groupError).foregroundStyle(.red) }
            }
            Section {
                ForEach(draft.rows.filter { !$0.isFinal }) { row in ruleRow(row) }
                    .onDelete { offsets in
                        let movable = draft.rows.filter { !$0.isFinal }
                        draft.remove(Set(offsets.compactMap { movable.indices.contains($0) ? movable[$0].id : nil }))
                    }
                    .onMove { offsets, destination in
                        let movable = draft.rows.filter { !$0.isFinal }
                        let ids = Set(offsets.compactMap { movable.indices.contains($0) ? movable[$0].id : nil })
                        draft.move(ids, before: movable.indices.contains(destination) ? movable[destination].id : nil)
                    }
                ForEach(draft.rows.filter(\.isFinal)) { row in ruleRow(row) }
                    .deleteDisabled(true).moveDisabled(true)
                Button("Add Rule") { editing = .init(rowID: nil, raw: "") }.buttonStyle(.plain).foregroundStyle(.primary)
                    .accessibilityIdentifier("configuration.rule.editor.add")
            } header: { Text("Rules") }
            if let error { Section { Text(verbatim: error).foregroundStyle(.red) } }
        }
        .clashAlwaysEditing()
        .disabled(isBusy)
        .clashPageTitle("Edit Rule Scheme")
        .clashProductModalRoot(title: "Edit Rule Scheme")
        .accessibilityIdentifier("configuration.rule.editor")
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { if dirty { confirmsDiscard = true } else { close() } }
                    .disabled(isBusy).accessibilityIdentifier("configuration.rule.editor.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button { submit { _ in } } label: { ClashActionProgressLabel(.copy("Save"), isBusy: isBusy) }.disabled(!canSave)
                    .accessibilityIdentifier("configuration.rule.editor.save")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if insideProductModal {
                ClashModalActionBar(primaryTitle: "Save", primaryDisabled: !canSave, isBusy: isBusy) { submit { _ in } }
            }
        }
        .clashRegistersDeparture(isDirty: dirty, isBusy: isBusy, whySaveIsBlocked: {
            (try? draft.document()) == nil ? ClashDepartureSaveAnswer.incomplete : nil
        }, save: submit, discard: { draft = baseline })
        .interactiveDismissDisabled(dirty || isBusy)
        .clashUnsavedChangesAlert(isPresented: $confirmsDiscard,
            message: .copy("This profile has changes that have not been saved."),
            isBusy: isBusy, saveTitle: "Save", saveDisabled: !canSave,
            save: { submit { _ in } }, discard: { draft = baseline; close() })
        .clashProductModal(item: $editing, role: .page) { target in
            ruleEditor(target.raw, draft, { raw, enabled, note in draft.setRule(raw, enabled: enabled, note: note, rowID: target.rowID) },
                target.rowID.flatMap { id in
                    guard draft.rows.contains(where: { $0.id == id && !$0.isFinal }) else { return nil }
                    return { draft.remove([id]) }
                })
        }
        .clashProductModal(item: $editingGroup, role: .page) { target in
            groupEditor(draft, target.groupID) { group in
                do { try draft.setGroup(group, groupID: target.groupID); groupError = nil }
                catch { groupError = ClashConfigurationRuleGroupCopy.message(error, locale: locale) }
            }
        }
    }
     
     
     
    private func ruleRow(_ row: ConfigurationRuleDraft.Row) -> some View {
        let enabled = draft.isEnabled(row.raw)
        let note = draft.note(for: row.raw)
        return Button { editing = .init(rowID: row.id, raw: row.raw) } label: {
            VStack(alignment: .leading, spacing: 4) {
                ConfigurationRuleRow(row.raw).opacity(enabled ? 1 : 0.5)
                if !note.isEmpty {
                    Text(verbatim: note).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityValue(Text(enabled ? "" : "Off"))
            .accessibilityIdentifier("configuration.rule.editor.row.\(row.id)")
    }
    private func submit(_ completion: @escaping (Bool) -> Void) {
        guard canSave else { completion(false); return }
        save(draft) { success in
            if success { baseline = draft; close() }
            completion(success)
        }
    }
}

public struct ClashConfigurationNewRuleView: View {
    private let tabHeader: ((Bool) -> AnyView)?
    @State private var draft: ConfigurationNewRuleDraft
    @State private var baseline: ConfigurationNewRuleDraft
    @State private var confirmsDiscard = false
    private let templates: [ConfigurationRuleScheme]
    private let isBusy: Bool
    private let error: String?
    private let create: (ConfigurationNewRuleDraft, @escaping (Bool) -> Void) -> Void
    private let close: () -> Void
    @Environment(\.clashInsideProductModalPresentation) private var insideProductModal
    public init(defaultName: String, templates: [ConfigurationRuleScheme], isBusy: Bool, error: String?,
                tabHeader: ((Bool) -> AnyView)? = nil,
                create: @escaping (ConfigurationNewRuleDraft, @escaping (Bool) -> Void) -> Void,
                close: @escaping () -> Void) {
        self.tabHeader = tabHeader
        let draft = ConfigurationNewRuleDraft(label: defaultName)
        _draft = State(initialValue: draft); _baseline = State(initialValue: draft)
        self.templates = templates; self.isBusy = isBusy; self.error = error; self.create = create; self.close = close
    }
    private var dirty: Bool { draft != baseline }
    private var canCreate: Bool { !isBusy && !draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var body: some View {
        Form {
            Section("Name") { TextField("Name", text: $draft.label).accessibilityIdentifier("configuration.rule.new.name") }
            Section {
                Button { draft.templateID = nil } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Blank")
                            Text("One MATCH rule routes all traffic through the selected nodes.").font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if draft.templateID == nil { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("configuration.rule.new.blank")
                ForEach(templates) { template in
                    Button { draft.templateID = template.id } label: {
                        HStack {
                            Text("Copy")
                            if template.id == ConfigurationBuiltins.basicRuleID { Text("Default Configuration") }
                            else { Text(verbatim: template.displayLabel) }
                            Spacer()
                            if draft.templateID == template.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("configuration.rule.new.template.\(template.id)")
                }
            } header: { Text("Start From") }
            if let error { Section { Text(verbatim: error).foregroundStyle(.red) } }
        }
        .disabled(isBusy)
        .safeAreaInset(edge: .top, spacing: 0) { if let tabHeader { tabHeader(dirty).disabled(isBusy) } }
        .clashPageTitle(.copy(ClashConfigurationAddition.rules.title))
        .clashProductModalRoot(title: .copy(ClashConfigurationAddition.rules.title))
        .accessibilityIdentifier("configuration.rule.new")
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { if dirty { confirmsDiscard = true } else { close() } }
                    .disabled(isBusy).accessibilityIdentifier("configuration.rule.new.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") { submit { _ in } }.disabled(!canCreate)
                    .accessibilityIdentifier("configuration.rule.new.create")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if insideProductModal {
                ClashModalActionBar(primaryTitle: "Create", primaryDisabled: !canCreate, isBusy: isBusy) { submit { _ in } }
            }
        }
        .clashRegistersDeparture(isDirty: dirty, isBusy: isBusy, whySaveIsBlocked: {
            draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .copy("Enter a name.") : nil
        }, save: submit, discard: { draft = baseline })
        .interactiveDismissDisabled(dirty || isBusy)
        .clashUnsavedChangesAlert(isPresented: $confirmsDiscard,
            message: .copy("This profile has changes that have not been saved."),
            isBusy: isBusy, saveTitle: "Create", saveDisabled: !canCreate,
            save: { submit { _ in } }, discard: { draft = baseline; close() })
    }
    private func submit(_ completion: @escaping (Bool) -> Void) {
        guard canCreate else { completion(false); return }
        create(draft) { success in
            if success { baseline = draft }
            completion(success)
        }
    }
}

public struct ClashConfigurationRuleGroupsView: View {
    public let groups: [ConfigurationRuleGroupSnapshot]
    public let isLoading: Bool
    public let error: String?
    public let reload: () -> Void
    public let close: () -> Void
    @State private var search = ""
    @State private var expanded: Set<Int> = []
    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var fieldCopy
    public init(groups: [ConfigurationRuleGroupSnapshot], isLoading: Bool, error: String?,
                reload: @escaping () -> Void, close: @escaping () -> Void) {
        self.groups = groups; self.isLoading = isLoading; self.error = error; self.reload = reload; self.close = close
    }
     
     
    private var types: [String: String] { ConfigurationTypeWords.names(.proxyGroups, copy: fieldCopy, locale: locale) }
    private func visible(types: [String: String]) -> [ConfigurationRuleGroupSnapshot] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? groups : groups.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.type.localizedCaseInsensitiveContains(query)
                || ConfigurationTypeWords.word($0.type, in: types).localizedCaseInsensitiveContains(query)
                || $0.members.contains(where: { $0.localizedCaseInsensitiveContains(query) })
                || $0.providers.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }
    public var body: some View {
        let typeNames = types
        let shown = visible(types: typeNames)
        Form {
            Section {
                TextField("Search", text: $search).autocorrectionDisabled()
                    .accessibilityIdentifier("configuration.rule.groups.search")
            }
            if isLoading { ProgressView() }
            if let error {
                Section { Text(verbatim: error); Button("Retry", action: reload).accessibilityIdentifier("configuration.rule.groups.retry") }
            } else if !isLoading {
                if groups.isEmpty { Text("No Proxy Groups") }
                else if shown.isEmpty { Text("No results") }
                ForEach(shown) { group in
                    Section {
                        Button {
                            if expanded.contains(group.id) { expanded.remove(group.id) }
                            else { expanded.insert(group.id) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: group.name).foregroundStyle(.primary).lineLimit(2)
                                    Text(verbatim: ConfigurationTypeWords.word(group.type, in: typeNames)).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: expanded.contains(group.id) ? "chevron.down" : "chevron.right")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("configuration.rule.groups.item.\(group.id)")
                        if expanded.contains(group.id) {
                            if group.includesAll { Text("Include all proxies and providers") }
                            else {
                                if group.includesAllProxies { Text("Include all proxies") }
                                if group.includesAllProviders { Text("Include all providers") }
                            }
                            if !group.members.isEmpty {
                                Text("Members").font(.subheadline).foregroundStyle(.secondary)
                                ForEach(Array(group.members.enumerated()), id: \.offset) { _, member in
                                    Text(verbatim: member).textSelection(.enabled)
                                }
                            }
                            if !group.providers.isEmpty {
                                Text("Proxy Providers").font(.subheadline).foregroundStyle(.secondary)
                                ForEach(Array(group.providers.enumerated()), id: \.offset) { _, provider in
                                    Text(verbatim: provider).textSelection(.enabled)
                                }
                            }
                            let fields = advancedFields(group)
                            if !fields.isEmpty {
                                DisclosureGroup("Advanced") {
                                    ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(verbatim: field.key).font(.subheadline)
                                            Text(verbatim: field.value).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                                        }
                                    }
                                }.clashRowDisclosure().accessibilityIdentifier("configuration.rule.groups.advanced.\(group.id)")
                            }
                        }
                    }
                }
            }
        }
        .clashPageTitle("Policy Groups")
        .clashProductModalRoot(title: "Policy Groups")
        .accessibilityIdentifier("configuration.rule.groups")
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: close).accessibilityIdentifier("configuration.rule.groups.close")
            }
        }
    }
    private func advancedFields(_ group: ConfigurationRuleGroupSnapshot) -> [(key: String, value: String)] {
        guard case .object(let fields) = group.document else { return [] }
        let shown: Set<String> = ["name", "type", "proxies", "use", "include-all", "include-all-proxies", "include-all-providers"]
        return fields.filter { !shown.contains($0.key) }.map { field in
            if case .string(let value) = field.value { return (field.key, value) }
            return (field.key, field.value.serialized())
        }
    }
}

public enum ClashConfigurationRuleGroupCopy {
    public static func message(_ error: Error, locale: Locale) -> String {
        guard let error = error as? ConfigurationRuleGroupError else { return error.localizedDescription }
        let text: ClashDisplayText
        switch error {
        case .nameRequired: text = .copy("Group name is required.")
        case .duplicate(let name): text = .format("Group name is already in use: %@", [name])
        case .cycle(let name): text = .format("Groups cannot refer back to themselves: %@", [name])
        case .inUse(let name): text = .format("Change references to this group before deleting it: %@", [name])
        }
        return ClashCopy.string(for: text, locale: locale)
    }
}

 
 
public enum ClashConfigurationSubRuleCopy {
    public static func message(_ error: Error, locale: Locale) -> String {
        guard let error = error as? ConfigurationSubRuleError else { return ClashTowerRulesErrorText.describe(error) }
        let key: String
        switch error {
        case .nameRequired: key = "Give the sub-rule a name."
        case .nameHasComma: key = "A sub-rule name can't contain a comma."
        case .duplicate: key = "That sub-rule name is already in use."
        case .inUse: key = "Rules still lead into this sub-rule. Change them first."
        case .cycle: key = "Sub-rules can't lead back to themselves."
        case .ruleRequired: key = "Enter a rule."
        case .notEditable: key = "These sub-rules can only be changed in the source."
        }
        return ClashCopy.string(key, locale: locale)
    }
}

public enum ClashConfigurationUpdateCopy {
    public static func message(_ error: Error, locale: Locale) -> String {
        if error is ConfigurationRuleReplay.Conflict {
            return ClashCopy.string("The profile URL conflicts with your rule edits. Your current profile was kept.", locale: locale)
        }
        return ClashErrorCopy.message(error, locale: locale)
    }
}

public struct ClashConfigurationReadRow: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let subtitle: String?
    public let content: String?
    public let nodeIndex: Int?
    public let collection: ConfigurationCollection?
    public let rule: ClashRuleLineSnapshot?
    public let chainedThrough: String?
    public init(title: String, subtitle: String? = nil, content: String? = nil, nodeIndex: Int? = nil, collection: ConfigurationCollection? = nil,
                rule: ClashRuleLineSnapshot? = nil, chainedThrough: String? = nil) {
        self.rule = rule; self.chainedThrough = chainedThrough
        self.title = title; self.subtitle = subtitle; self.content = content; self.nodeIndex = nodeIndex; self.collection = collection
    }
}
public struct ClashConfigurationReadSection: Identifiable, Sendable {
    public let id = UUID()
     
     
    public let title: ClashDisplayText
    public let rows: [ClashConfigurationReadRow]
    public init(title: ClashDisplayText, rows: [ClashConfigurationReadRow]) { self.title = title; self.rows = rows }
}
public struct ClashConfigurationContentsView: View {
    @State private var search = ""
    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var fieldCopy
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
     
     
    private func subtitle(_ row: ClashConfigurationReadRow, words: ConfigurationTypeWords.Collections) -> String? {
        if let collection = row.collection { return words.line(collection) }
        guard let subtitle = row.subtitle else { return nil }
        return row.nodeIndex == nil ? subtitle : ConfigurationTypeWords.word(subtitle, in: words.nodes)
    }
    private func matches(_ row: ClashConfigurationReadRow, words: ConfigurationTypeWords.Collections) -> Bool {
        query.isEmpty || row.title.localizedCaseInsensitiveContains(query)
            || (row.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
            || (subtitle(row, words: words)?.localizedCaseInsensitiveContains(query) ?? false)
    }
     
     
    public let title: ClashDisplayText
    public let sections: [ClashConfigurationReadSection]
    public let loading: Bool
    public let error: String?
    public let reload: () -> Void
    public let edit: (() -> Void)?
    public let showsClose: Bool
    public let close: () -> Void
    public let openNode: ((Int) -> Void)?
    public let deleteNode: ((Int) -> Void)?
    public let addNode: (() -> Void)?
    public let isBusy: Bool
    public let manage: (() -> Void)?
    public let palette: ClashProductPalette?
    public let searchPrompt: String
    public let nodeDensity: ClashProxiesRowDensity
    public init(title: ClashDisplayText, sections: [ClashConfigurationReadSection], loading: Bool, error: String?,
                reload: @escaping () -> Void, edit: (() -> Void)? = nil, close: @escaping () -> Void,
                showsClose: Bool = true, openNode: ((Int) -> Void)? = nil, deleteNode: ((Int) -> Void)? = nil,
                addNode: (() -> Void)? = nil, isBusy: Bool = false, manage: (() -> Void)? = nil,
                nodeDensity: ClashProxiesRowDensity = .standard, searchPrompt: String = "Search Nodes", palette: ClashProductPalette? = nil) {
        self.palette = palette
        self.searchPrompt = searchPrompt
        self.showsClose = showsClose
        self.manage = manage; self.nodeDensity = nodeDensity
        self.title = title; self.sections = sections; self.loading = loading; self.error = error
        self.reload = reload; self.edit = edit; self.close = close
        self.openNode = openNode; self.deleteNode = deleteNode; self.addNode = addNode; self.isBusy = isBusy
    }
    private var contents: some View {
         
        let words = ConfigurationTypeWords.Collections(copy: fieldCopy, locale: locale)
        return List {
            if loading { ProgressView() }
            if let error {
                Text(verbatim: error).foregroundStyle(.red)
                Button("Retry", action: reload)
            }
            if !loading && error == nil && sections.allSatisfy({ !$0.rows.contains(where: { matches($0, words: words) }) }) { Text("No results") }
            ForEach(sections) { section in
                let rows = section.rows.filter { matches($0, words: words) }
                if !rows.isEmpty {
                Section {
                    ForEach(rows) { row in
                        if let index = row.nodeIndex, let openNode {
                            ClashProxyMemberListRow(
                                row: ClashProxyFrozenRow(name: row.title, type: subtitle(row, words: words) ?? "", chainedThrough: row.chainedThrough, groupName: nil),
                                initialLatency: .untested, failureCategory: "", isCurrent: false, canTest: false,
                                density: nodeDensity, latencyPulse: nil, latencyPulseSnapshot: nil,
                                select: { openNode(index) },
                                editNode: deleteNode == nil ? nil : { openNode(index) }, testNode: nil,
                                inspectNode: { openNode(index) }, showsLatency: false
                            )
                            .clashSwipeToDelete(deleteNode.map { delete in { delete(index) } })
                        } else if let rule = row.rule, let palette {
                            ClashRuleListRow(row: ClashRuleFrozenRow(rule), palette: palette)
                                .textSelection(.enabled)
                        } else if let collection = row.collection {
                            ClashRoutedViewLink { ClashConfigurationCollectionView(collection: collection) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: collection.name)
                                    Text(verbatim: words.line(collection))
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        } else if let content = row.content {
                            DisclosureGroup {
                                Text(verbatim: content).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(verbatim: row.title)
                                    if let subtitle = subtitle(row, words: words) { Text(verbatim: subtitle).foregroundStyle(.secondary).font(.footnote) }
                                }
                            }
                        } else { Text(verbatim: row.title).textSelection(.enabled) }
                    }
                } header: { Text(clash: section.title) }
                }
            }
            if let addNode { Section { Button("Add Custom Node", action: addNode).buttonStyle(.plain).foregroundStyle(.primary) } }
            if let edit { Section { Button("Edit", action: edit).buttonStyle(.plain).foregroundStyle(.primary) } }
        }
    }
    public var body: some View {
        ClashProxiesBrowserHost(modern: { contents }, legacy: { contents })
        .clashProductModalSearchable(text: $search, prompt: Text(ClashCopy.key(searchPrompt)))
        .disabled(isBusy || loading)
        .interactiveDismissDisabled(isBusy)
        .clashPageTitle(title, watchAs: "Node Sources")
        .clashProductModalRoot(title: title)
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) { if showsClose { ClashSheetCloseButton(dismiss: close) } }
            ToolbarItem(placement: .primaryAction) {
                if let manage {
                    Button(action: manage) {
                        Image(systemName: "gearshape").clashToolbarGlyph()
                    }
                    .accessibilityLabel("Manage")
                    .accessibilityIdentifier("configuration.contents.manage")
                }
            }
        }
    }
}

private struct ClashConfigurationSubscriptionFields: View {
    @Binding var draft: ConfigurationSourceSettingsDraft
    var body: some View {
        Group {
            Section("Profile URL") { TextField("URL", text: $draft.url).accessibilityIdentifier("configuration.source.subscription.url").clashConfigurationResolverInput() }
            Section {
                Picker("Update Interval", selection: $draft.intervalHours) {
                    Text("Manually").tag(0)
                    ForEach([1, 6, 12, 24, 48, 168], id: \.self) { hours in
                        Text(clash: .format("Every %@ hours", [String(hours)])).tag(hours)
                    }
                    if ![0,1,6,12,24,48,168].contains(draft.intervalHours) {
                        Text(clash: .format("Every %@ hours", [String(draft.intervalHours)])).tag(draft.intervalHours)
                    }
                }.accessibilityIdentifier("configuration.source.subscription.interval")
            } header: { Text("Update") }
        }
    }
}

public struct ClashConfigurationSourceSettingsView: View {
    @State private var draft: ConfigurationSourceSettingsDraft
    private let baseline: ConfigurationSourceSettingsDraft
    private let isBusy: Bool
    private let error: String?
    private let save: (ConfigurationSourceSettingsDraft, @escaping (Bool) -> Void) -> Void
    private let close: () -> Void
    @State private var confirmsDiscard = false
    @Environment(\.clashInsideProductModalPresentation) private var insideModal
    public init(source: ConfigurationSourceRecord, isBusy: Bool, error: String?,
                save: @escaping (ConfigurationSourceSettingsDraft, @escaping (Bool) -> Void) -> Void, close: @escaping () -> Void) {
        let value = ConfigurationSourceSettingsDraft(source: source)
        _draft = State(initialValue: value); baseline = value
        self.isBusy = isBusy; self.error = error; self.save = save; self.close = close
    }
    private var dirty: Bool { draft != baseline }
    private var valid: Bool {
        let url = URLComponents(string: draft.url.trimmingCharacters(in: .whitespacesAndNewlines))
        return url?.scheme != nil && !(url?.host?.isEmpty ?? true)
    }
    private func submit(_ done: @escaping (Bool) -> Void) {
        guard valid, !isBusy else { done(false); return }
        save(draft) { succeeded in done(succeeded); if succeeded { close() } }
    }
    public var body: some View {
        Form {
            ClashConfigurationSubscriptionFields(draft: $draft)
            if let error { Section { Text(verbatim: error).foregroundStyle(.red) } }
        }
        .disabled(isBusy)
        .clashPageTitle("Profile URL Settings")
        .clashProductModalRoot(title: "Profile URL Settings")
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { if dirty { confirmsDiscard = true } else { close() } }.disabled(isBusy)
            }
            ToolbarItem(placement: .confirmationAction) { Button { submit { _ in } } label: { ClashActionProgressLabel(.copy("Save"), isBusy: isBusy) }.disabled(isBusy || !valid || !dirty) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if insideModal {
                ClashModalActionBar(primaryTitle: "Save", primaryDisabled: !valid || !dirty, isBusy: isBusy) { submit { _ in } }
            }
        }
        .clashRegistersDeparture(isDirty: dirty, isBusy: isBusy, whySaveIsBlocked: {
            valid ? nil : .copy("Enter a valid link.")
        }, save: submit, discard: { draft = baseline })
        .interactiveDismissDisabled(dirty || isBusy)
        .clashUnsavedChangesAlert(isPresented: $confirmsDiscard,
            message: .copy("This profile has changes that have not been saved."),
            isBusy: isBusy, saveDisabled: !valid || !dirty,
            save: { submit { _ in } }, discard: { draft = baseline; close() })
    }
}

public struct ClashConfigurationSubscriptionRequest: Hashable, Sendable {
    public var url = ""
    public init() {}
}

 
public struct ClashConfigurationSubscriptionImportView: View {
    @State private var request = ClashConfigurationSubscriptionRequest()
    @State private var name = ""
    @State private var registerRules = true
    @State private var preview: ConfigurationSourcePayload?
    @State private var previewRequest: ClashConfigurationSubscriptionRequest?
    @State private var loading = false
    @State private var saving = false
    @State private var failure: String?
    @State private var retry = 0
    @State private var confirmsDiscard = false
    @Environment(\.clashInsideProductModalPresentation) private var insideModal
    private let load: (ClashConfigurationSubscriptionRequest) async throws -> ConfigurationSourcePayload
    private let save: (ConfigurationSourcePayload) async throws -> Void
    private let close: () -> Void
    public init(load: @escaping (ClashConfigurationSubscriptionRequest) async throws -> ConfigurationSourcePayload,
                save: @escaping (ConfigurationSourcePayload) async throws -> Void, close: @escaping () -> Void) {
        self.load = load; self.save = save; self.close = close
    }
    private struct PreviewKey: Hashable { let request: ClashConfigurationSubscriptionRequest; let retry: Int }
    private var dirty: Bool { request != .init() || !name.isEmpty || !registerRules }
    private var canSave: Bool { preview != nil && previewRequest == request && !loading && !saving }
    public var body: some View {
        Form {
            Section {
                TextField("Profile URL or Share Link", text: $request.url).accessibilityIdentifier("configuration.subscription.import.url").clashConfigurationResolverInput()
            } header: { Text("URL") } footer: {
                Text("HTTP is not encrypted. Credentials in the address travel in the clear.")
            }
            if loading { Section { ProgressView() } }
            if let preview, previewRequest == request {
                Section("Read from Source") {
                    HStack { Text("Nodes"); Spacer(); Text(verbatim: String(preview.record.nodeCount)) }
                    HStack { Text("Proxy Provider Count"); Spacer(); Text(verbatim: String(preview.record.providerCount)) }
                    HStack { Text("Policy Groups"); Spacer(); Text(verbatim: String(preview.record.groupCount)) }
                    HStack { Text("Rules"); Spacer(); Text(verbatim: String(preview.record.ruleCount)) }
                    if preview.record.hasRules { Toggle("Register Its Rules", isOn: $registerRules).accessibilityIdentifier("configuration.subscription.import.rules") }
                }
            }
            Section("Name (Optional)") { TextField("Name", text: $name).accessibilityIdentifier("configuration.subscription.import.name") }
            if let failure {
                Section {
                    Text(verbatim: failure).foregroundStyle(.red)
                    Button("Retry") { retry += 1 }.disabled(saving)
                }
            }
        }
        .disabled(saving)
        .clashPageTitle("Add Profile URL")
        .clashProductModalRoot(title: "Add Profile URL")
        .task(id: PreviewKey(request: request, retry: retry)) { await read() }
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { if dirty { confirmsDiscard = true } else { close() } }.disabled(saving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button { submit { _ in } } label: { ClashActionProgressLabel(.copy("Add"), isBusy: saving) }.disabled(!canSave)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if insideModal { ClashModalActionBar(primaryTitle: "Add", primaryDisabled: !canSave, isBusy: saving) { submit { _ in } } }
        }
        .clashRegistersDeparture(isDirty: dirty, isBusy: saving, whySaveIsBlocked: {
            preview != nil && previewRequest == request && !loading ? nil : ClashDepartureSaveAnswer.incomplete
        }, save: submit, discard: {
            request = .init(); name = ""; registerRules = true; preview = nil
        })
        .interactiveDismissDisabled(dirty || saving)
        .clashUnsavedChangesAlert(isPresented: $confirmsDiscard,
            message: .copy("This profile has changes that have not been saved."),
            isBusy: saving, saveTitle: "Add", saveDisabled: !canSave,
            save: { submit { _ in } }, discard: close)
    }
    private func read() async {
        let input = request
        preview = nil; previewRequest = nil; failure = nil
        guard !input.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { loading = false; return }
        loading = true
        do {
            try await Task.sleep(nanoseconds: 500_000_000)
            let result = try await load(input)
            try Task.checkCancellation()
            guard input == request else { return }
            preview = result; previewRequest = input; loading = false
        } catch {
            guard !Task.isCancelled, input == request else { return }
            failure = error.localizedDescription; loading = false
        }
    }
    private func submit(_ completion: @escaping (Bool) -> Void) {
        guard canSave, var payload = preview else { completion(false); return }
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { payload.record.label = label }
        payload.record.registersSuppliedRules = registerRules
        saving = true; failure = nil
        Task {
            do {
                try await save(payload)
                saving = false; request = .init(); name = ""; registerRules = true; preview = nil
                completion(true); close()
            } catch {
                saving = false; failure = error.localizedDescription; completion(false)
            }
        }
    }
}

 
struct ClashConfigurationLibraryRow: View {
    let title: String
    let count: ClashDisplayText
     
     
     
    var showsInfo = true
     
     
     
     
    var usage: ConfigurationSubscriptionUsage? = nil
     
     
    var failure: String? = nil
    @Environment(\.locale) private var locale

    var body: some View {
        let _ = ClashPerf.count("library.row")
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title)
                    .font(.body).foregroundStyle(Color.primary)
                    .lineLimit(1).truncationMode(.tail)
                caption
                    .font(.caption).foregroundStyle(Color.secondary)
                    .lineLimit(1)
                if let failure {
                    Text(verbatim: failure)
                        .font(.caption).foregroundStyle(Color.red)
                        .lineLimit(3)
                        .accessibilityIdentifier("configuration.library.source.refusal")
                }
                if let fraction = usage?.fraction {
                    ProgressView(value: fraction, total: 1)
                        .progressViewStyle(.linear).tint(.accentColor)
                        .accessibilityLabel(ClashCopy.key("Used"))
                }
            }
            Spacer(minLength: 8)
            if showsInfo {
                Image(systemName: ClashSymbol.infoCircle.rawValue)
                    .font(.title3).foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var caption: Text {
        guard let usage, usage.expire > 0 else { return Text(clash: count) }
        let date = Date(timeIntervalSince1970: Double(usage.expire))
        let expired = usage.expire < Int64(Date().timeIntervalSince1970)
        let expiry = Text(clash: .format("Expires %@", [date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))]))
         
         
        return Text(clash: count) + Text(verbatim: " · ") + (expired ? expiry.foregroundColor(.red) : expiry)
    }
}

 
 
 
 
public struct ClashConfigurationLibraryHeader: View {
    let title: ClashDisplayText
    var count: Int? = nil

    public init(title: ClashDisplayText, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(clash: title)
            Spacer(minLength: 8)
            if let count { Text("\(count)").monospacedDigit() }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(nil)
        .accessibilityAddTraits(.isHeader)
    }
}

 
 
struct ClashConfigurationLibraryCard<Content: View>: View {
    let nativeList: Bool
    var title: ClashDisplayText?
    var count: Int?
    let palette: ClashProductPalette
    let content: Content
     
     
     
    var systemRowInsets = false
    init(title: ClashDisplayText? = nil, count: Int? = nil, palette: ClashProductPalette,
         nativeList: Bool = false, systemRowInsets: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title; self.count = count; self.palette = palette; self.nativeList = nativeList
        self.systemRowInsets = systemRowInsets; self.content = content()
    }
    @ViewBuilder var body: some View {
        let _ = ClashPerf.count("library.card")
        if nativeList || ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            Section {
                content
                    .listRowInsets(ClashPlatformLayout.pageUsesSystemSettingsIdiom || systemRowInsets ? nil :
                        EdgeInsets(top: 0, leading: ClashTheme.Spacing.standard, bottom: 0, trailing: ClashTheme.Spacing.standard))
            } header: {
                if let title { ClashConfigurationLibraryHeader(title: title, count: count) }
            }
        } else {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.row) {
                if let title {
                    ClashConfigurationLibraryHeader(title: title, count: count)
                        .padding(.horizontal, ClashTheme.Spacing.standard)
                }
                ClashCardSurface(fill: palette.card, separator: palette.separator) {
                    VStack(alignment: .leading, spacing: 0) { content }
                        .padding(.horizontal, ClashTheme.Spacing.standard)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

 
public enum ClashConfigurationAddition {
    case configuration, nodes, rules, scripts, certificates
    public var title: String {
        switch self {
        case .configuration: "Create Profile"
        case .nodes: "Create Nodes"
        case .rules: "Create Rules"
        case .scripts: "Add Script"
        case .certificates: "Add Certificate"
        }
    }
    public var entryTitle: String { title }
    var creationHint: String {
        switch self {
        case .configuration: "Import from a Profile URL or YAML file, or use custom nodes"
        case .nodes: "Import from a Profile URL or YAML file, or create nodes manually"
        case .rules: "Import from a Profile URL or YAML file, or edit rules manually"
        case .scripts: "Import from a URL or file, or write one by hand"
        case .certificates: "Import from a URL or file, or paste the PEM"
        }
    }
}

 
 
 
public struct ClashConfigurationLibraryAddCard: View {
    let kind: ClashConfigurationAddition
    let palette: ClashProductPalette
    var nativeList = false
    var showsHeader = true
    var disabled = false
    let action: () -> Void
    public init(kind: ClashConfigurationAddition, palette: ClashProductPalette, nativeList: Bool = false,
                showsHeader: Bool = true, disabled: Bool = false, action: @escaping () -> Void) {
        self.kind = kind; self.palette = palette; self.nativeList = nativeList
        self.showsHeader = showsHeader; self.disabled = disabled; self.action = action
    }
    public var body: some View {
        ClashConfigurationLibraryCard(title: showsHeader ? .copy(kind.title) : nil, palette: palette, nativeList: nativeList) {
            Button(action: action) {
                ClashProfileActionRow(title: .copy(kind.entryTitle), subtitle: .copy(kind.creationHint),
                    symbol: .plusCircle, tint: .primary, showsDisclosure: false,
                    icon: { Image(systemName: $0.rawValue) })
            }
            .buttonStyle(.plain)
            .disabled(disabled)
        }
    }
}

public extension ConfigurationSourceRecord {
     
     
     
     
    func displayLabel(locale: Locale) -> String {
        Self.displayLabel(label, origin: origin, locale: locale)
    }

     
     
    static func displayLabel(_ label: String, origin: Origin, locale: Locale) -> String {
        ClashCopy.string(for: ClashConfigurationSourceCopy.name(label, origin: origin), locale: locale)
    }
}

public enum ClashConfigurationSourceCopy {
     
     
     
    public static func nameToStore(_ typed: String, origin: ConfigurationSourceRecord.Origin, locale: Locale) -> String {
        let builtin = ConfigurationBuiltins.customNodesName
        if ConfigurationSourceRecord.isBuiltinName(builtin, origin: origin),
           typed == ConfigurationSourceRecord.displayLabel(builtin, origin: origin, locale: locale) {
            return builtin
        }
        return typed
    }

     
     
     
     
     
     
    public static func name(_ source: ConfigurationSourceRecord) -> ClashDisplayText {
        name(source.label, origin: source.origin)
    }
    public static func name(_ label: String, origin: ConfigurationSourceRecord.Origin) -> ClashDisplayText {
        ConfigurationSourceRecord.isBuiltinName(label, origin: origin) ? .copy(label) : .verbatim(label)
    }
     
     
     
     
    public static func sentence(_ key: String, naming source: ConfigurationSourceRecord, then more: [String] = []) -> ClashDisplayText {
        source.hasBuiltinName ? .formatCopy(key, [source.label] + more) : .format(key, [source.label] + more)
    }
     
     
    static func counted(_ count: Int, one: String, other: String) -> ClashDisplayText {
        .format(count == 1 ? one : other, [String(count)])
    }
    public static func ruleSummary(_ source: ConfigurationSourceRecord?, locale: Locale) -> ClashDisplayText {
        let count = source?.ruleCount ?? 0, collections = source?.ruleProviderCount ?? 0
        let rules = counted(count, one: "%@ rule", other: "%@ rules")
        let sets = counted(collections, one: "%@ collection", other: "%@ collections")
        if collections == 0 { return rules }
        if count == 0 { return sets }
         
        return .verbatim(rules.resolved(locale: locale) + " · " + sets.resolved(locale: locale))
    }
    public static func summary(_ source: ConfigurationSourceRecord, locale: Locale) -> String {
        let nodes = counted(source.nodeCount, one: "%@ node", other: "%@ nodes")
        let sets = counted(source.providerCount, one: "%@ collection", other: "%@ collections")
        if source.providerCount == 0 { return nodes.resolved(locale: locale) }
        if source.nodeCount == 0 { return sets.resolved(locale: locale) }
        return nodes.resolved(locale: locale) + " · " + sets.resolved(locale: locale)
    }
}

public struct ClashConfigurationCollectionView: View {
    public let collection: ConfigurationCollection
    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var fieldCopy
    public init(collection: ConfigurationCollection) { self.collection = collection }
     
     
    private func title(_ key: String) -> String {
        let path = (collection.id.kind == .rules ? "rule-providers.*." : "proxy-providers.*.") + key
        return fieldCopy.entry(forPath: path, language: .init(locale: locale))?.title ?? key
    }
    public var body: some View {
         
         
        let words = ConfigurationTypeWords.Collections(copy: fieldCopy, locale: locale)
        Form {
            Section {
                HStack { Text(verbatim: title("type")); Spacer(); Text(verbatim: words.type(of: collection)) }
                if collection.id.kind == .rules {
                    HStack { Text(verbatim: title("format")); Spacer(); Text(verbatim: words.format(of: collection)) }
                    if let behavior = words.behavior(of: collection) {
                        HStack { Text(verbatim: title("behavior")); Spacer(); Text(verbatim: behavior) }
                    }
                }
                if let location = collection.location { Text(verbatim: location).font(.footnote).textSelection(.enabled) }
            }
            if let count = collection.inlineCount {
                Section {
                    HStack { Text("Entries"); Spacer(); Text(verbatim: String(count)) }
                } header: { Text("Content") }
            }
        }.clashPageTitle(.verbatim(collection.name), watchAs: "Rule Collection")
    }
}

public struct ClashConfigurationSelectableNode: Identifiable, Sendable {
    public let name: String
    public let type: String
    public var id: String { name }
    public init(name: String, type: String) { self.name = name; self.type = type }
}

public struct ClashConfigurationNodeScopeView: View {
    private let source: ConfigurationSourceRecord
    private let initial: ConfigurationNodeScope?
    private let save: (ConfigurationNodeScope?) -> Void
    private let close: () -> Void
    private let collections: [ConfigurationCollection]
    private let nodes: [ClashConfigurationSelectableNode]
    private let initialNodes: Set<String>
    private let initialProviders: Set<String>
    private enum Choice: Hashable { case node(String), provider(String) }
    private let initialChoices: Set<Choice>
    @State private var selectedChoices: Set<Choice>
    private var selectedNodes: Set<String> {
        Set(selectedChoices.compactMap { if case .node(let name) = $0 { name } else { nil } })
    }
    private var selectedProviders: Set<String> {
        Set(selectedChoices.compactMap { if case .provider(let name) = $0 { name } else { nil } })
    }
    @State private var search = ""
    @State private var confirmsDiscard = false
    public init(source: ConfigurationSourceRecord, collections: [ConfigurationCollection],
                nodes: [ClashConfigurationSelectableNode], initial: ConfigurationNodeScope?,
                save: @escaping (ConfigurationNodeScope?) -> Void, close: @escaping () -> Void) {
        self.source = source; self.initial = initial; self.save = save; self.close = close
        self.collections = collections; self.nodes = nodes
        let selected = initial?.includesInlineNodes == false ? Set<String>()
            : Set(initial?.inlineNodeNames ?? nodes.map(\.name))
        let providers = Set(initial?.providerKeys ?? collections.map(\.name))
        initialNodes = selected; initialProviders = providers
        let choices = Set(selected.map(Choice.node) + providers.map(Choice.provider))
        initialChoices = choices
        _selectedChoices = State(initialValue: choices)
    }
    @Environment(\.clashInsideProductModalPresentation) private var insideProductModal
    private var dirty: Bool { selectedChoices != initialChoices }
    private var selection: ConfigurationNodeScope? {
        guard dirty else { return initial }
        let allNodes = selectedNodes == Set(nodes.map(\.name))
        if allNodes && selectedProviders == Set(collections.map(\.name)) { return nil }
        return .init(includesInlineNodes: !selectedNodes.isEmpty, providerKeys: selectedProviders.sorted(),
                     inlineNodeNames: allNodes ? nil : selectedNodes.sorted())
    }
    public var body: some View {
        List {
            if !collections.isEmpty {
                Section("Node Collections") {
                    ForEach(collections.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { collection in
                        choiceRow(.provider(collection.name), label: collection.name, detail: nil)
                            .accessibilityIdentifier("configuration.scope.collection.\(collection.name)")
                    }
                }
            }
            Section("Nodes") {
                ForEach(nodes.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.type.localizedCaseInsensitiveContains(search) }) { node in
                    choiceRow(.node(node.name), label: node.name, detail: node.type)
                        .accessibilityIdentifier("configuration.scope.node.\(node.name)")
                }
            }
        }
        .clashConfigurationFormSpacing()
        .clashProductModalSearchable(text: $search, prompt: Text("Search Nodes"))
        .clashPageTitle(ClashConfigurationSourceCopy.name(source), watchAs: "Source Nodes")
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { if dirty { confirmsDiscard = true } else { close() } }
            }
            ToolbarItem(placement: .confirmationAction) { Button("Done") { save(selection) } }
        }
        .interactiveDismissDisabled(dirty)
         
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if insideProductModal {
                ClashModalActionBar(primaryTitle: "Done", primaryDisabled: !dirty,
                    primaryHint: dirty ? nil : "Change something to save it.", onPrimary: { save(selection) })
            }
        }
        .clashUnsavedChangesAlert(isPresented: $confirmsDiscard, message: .copy("This selection has not been saved."),
            isBusy: false, save: { save(selection) }, discard: close)
    }
     
     
     
    private func choiceRow(_ choice: Choice, label: String, detail: String?) -> some View {
        let chosen = selectedChoices.contains(choice)
        return Button {
            if chosen { selectedChoices.remove(choice) } else { selectedChoices.insert(choice) }
        } label: {
            HStack(spacing: ClashTheme.Spacing.row) {
                ClashSelectionCircle(isSelected: chosen)
                choiceLabel(label, detail: detail)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .clashSelectionRowFill(chosen)
    }

    private func choiceLabel(_ name: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
            Text(verbatim: name).foregroundStyle(.primary)
            if let detail, !detail.isEmpty { Text(verbatim: detail).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

 
 
enum ClashConfigurationCollectionCopy {
    static func summary(_ entry: ConfigurationCollectionEntry) -> ClashDisplayText {
        if let count = entry.memberCount {
            return .format(entry.id.kind == .nodes ? "%@ nodes" : "%@ rules", [String(count)])
        }
        if entry.collection.type == "http" {
             
             
             
             
            return .copy(entry.id.kind == .nodes ? "Remote Node Collection" : "Remote Rule Set")
        }
        return .copy(entry.id.kind == .nodes ? "Node Collection File" : "Rule Set File")
    }
}

 
public struct ClashConfigurationCollectionCards: View {
    public let entries: [ConfigurationCollectionEntry]
    public let palette: ClashProductPalette
    public let open: (ConfigurationCollectionEntry) -> Void
    public init(entries: [ConfigurationCollectionEntry], palette: ClashProductPalette,
                open: @escaping (ConfigurationCollectionEntry) -> Void) {
        self.entries = entries; self.palette = palette; self.open = open
    }
    public var body: some View {
        ForEach(Array(Set(entries.map { $0.source.id })).sorted(), id: \.self) { sourceID in
            let children = entries.filter { $0.source.id == sourceID }
            ClashConfigurationLibraryCard(title: children.first.map { ClashConfigurationSourceCopy.name($0.source) } ?? .verbatim(""), count: children.count, palette: palette, nativeList: true) {
                ForEach(children) { entry in
                    Button { open(entry) } label: {
                        ClashConfigurationLibraryRow(title: entry.collection.name,
                            count: ClashConfigurationCollectionCopy.summary(entry))
                    }.buttonStyle(.plain)
                        .padding(.vertical, ClashMacSettingsMetrics.rowVerticalInset(touch: ClashTheme.Spacing.row))
                        .accessibilityIdentifier("configuration.collection.\(entry.source.id).\(entry.id.kind.rawValue).\(entry.collection.name)")
                }
            }
        }
    }
}

public struct ClashConfigurationCollectionContentsView: View {
    public let title: String
    public let rows: [ClashConfigurationReadRow]
    @Binding public var query: String
    public let status: String
    public let error: String?
    public let loading: Bool
    public let refresh: (() -> Void)?
    public let next: (() -> Void)?
    public let openNode: (Int) -> Void
    public let manage: () -> Void
    public let close: () -> Void
    public let details: (() -> AnyView)?
    public let actions: (() -> AnyView)?
    public let subscriptionUsage: ConfigurationSubscriptionUsage?
     
     
     
     
    public let isUpdating: Bool?
     
    public let updateProgress: String?
    public init(title: String, rows: [ClashConfigurationReadRow], query: Binding<String>, status: String,
                error: String?, loading: Bool, refresh: (() -> Void)?, next: (() -> Void)?,
                openNode: @escaping (Int) -> Void, manage: @escaping () -> Void, close: @escaping () -> Void,
                details: (() -> AnyView)? = nil, actions: (() -> AnyView)? = nil, subscriptionUsage: ConfigurationSubscriptionUsage? = nil,
                isUpdating: Bool? = nil, updateProgress: String? = nil) {
        self.isUpdating = isUpdating; self.updateProgress = updateProgress
        self.details = details; self.actions = actions; self.subscriptionUsage = subscriptionUsage
        self.title = title; self.rows = rows; _query = query; self.status = status; self.error = error
        self.loading = loading; self.refresh = refresh; self.next = next; self.openNode = openNode; self.manage = manage; self.close = close
    }
    public var body: some View {
        List {
            if let subscriptionUsage { Section { ClashConfigurationSubscriptionUsageView(usage: subscriptionUsage, detailed: true) } }
            if let details { details() }
            Section {
                if let refresh {
                    ClashConfigurationUpdateButton(title: "Update Source", isUpdating: isUpdating ?? loading, disabled: false, action: refresh)
                } else if loading { ProgressView() }
            } footer: {
                ClashConfigurationUpdateStatus(progress: updateProgress, status: status, error: error)
                    .accessibilityIdentifier("configuration.collection.status")
            }
            if let actions { actions() }
            Section {
                ForEach(rows) { row in
                    if let index = row.nodeIndex {
                        ClashProxyMemberListRow(
                            row: ClashProxyFrozenRow(name: row.title, type: row.subtitle ?? "", chainedThrough: nil, groupName: nil),
                            initialLatency: .untested, failureCategory: "", isCurrent: false, canTest: false,
                            density: .standard, latencyPulse: nil, latencyPulseSnapshot: nil,
                            select: { openNode(index) }, editNode: nil, testNode: nil, inspectNode: { openNode(index) }, showsLatency: false)
                    } else { Text(verbatim: row.title).textSelection(.enabled) }
                }
                if rows.isEmpty && !loading && !query.isEmpty { Text("No results") }
                if let next { Button("Load More", action: next).disabled(loading) }
            }
        }.clashConfigurationFormSpacing()
            .clashProductModalSearchable(text: $query)
            .clashPageTitle(.verbatim(title), watchAs: "Collection Entries")
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) { ClashSheetCloseButton(dismiss: close) }
                ToolbarItem(placement: .primaryAction) {
                    if details == nil { Button(action: manage) { Image(systemName: "gearshape").clashToolbarGlyph() }.accessibilityLabel("Manage Collections") }
                }
            }
    }
}

 
 
 
 
 
 
 
 
enum ClashConfigurationRuleChoices {
    static func schemes(draft: ConfigurationCreationDraft, library: ConfigurationLibrarySnapshot,
                        profileID: String? = nil) -> [ConfigurationRuleScheme] {
        var catalog = library
        catalog.rules = draft.rules(in: library)
        var choices = catalog.placingOwnViews(in: catalog.visibleRuleSchemes, for: profileID, running: draft.selectedRuleID)
         
         
        if let selected = catalog.rules.first(where: { $0.id == draft.selectedRuleID }),
           !choices.contains(where: { $0.id == selected.id && selected.ownViewBaseID != nil }) {
            let family = selected.baseSchemeID ?? selected.id
            if let index = choices.firstIndex(where: { ConfigurationBuiltins.isNative(family) ? $0.id == selected.id : ($0.baseSchemeID ?? $0.id) == family }) {
                choices[index] = selected
            } else {
                choices.append(selected)
            }
        }
        return choices
    }
}

struct ClashConfigurationSubscriptionUsageView: View {
    @Environment(\.locale) private var locale
    let usage: ConfigurationSubscriptionUsage
    var detailed = false
    var body: some View {
        let _ = ClashPerf.count("library.usage")
        VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
            if usage.total > 0 {
                Text(clash: .format("%@ of %@ used", [bytes(usage.used), bytes(usage.total)]))
            } else if usage.used > 0 {
                Text(clash: .format("Used %@", [bytes(usage.used)]))
            }
            if let fraction = usage.fraction {
                ProgressView(value: fraction, total: 1)
                    .progressViewStyle(.linear).tint(.accentColor)
                    .accessibilityLabel(ClashCopy.key("Used"))
            }
            if usage.expire > 0 {
                Text(clash: .format("Expires %@", [Date(timeIntervalSince1970: Double(usage.expire)).formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))]))
                    .foregroundStyle(usage.expire < Int64(Date().timeIntervalSince1970) ? Color.red : Color.secondary)
            }
            if detailed {
                Text(clash: .format("Uploaded %@", [bytes(max(0, usage.upload))]))
                Text(clash: .format("Downloaded %@", [bytes(max(0, usage.download))]))
            }
        }
        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("configuration.source.subscription-usage")
    }
    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
    }
}

 
 
 
 
 
 
 
struct ClashLibraryPullToUpdate: ViewModifier {
    let action: (() async -> Void)?

    init(action: (() async -> Void)?) { self.action = action }

    func body(content: Content) -> some View {
        if let action {
            content.refreshable { await action() }
        } else {
            content
        }
    }
}
