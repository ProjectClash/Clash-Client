import ClashClientUI
import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

 
 
 
struct ProfileOverrideView: View {
    @Environment(\.locale) private var locale
    let profile: Profile

     
     
     
     
     
    let save: (Profile) throws -> Void
    private let settingsFacade: ProfileSettingsFacade

     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
    @State private var patchText: String
    @State private var patchDiagnostic: CodeEditorDiagnostic?
    @State private var rules: [String]
    @State private var prependRules: Bool
    @State private var disabledGlobalRules: Set<String>
    @State private var selectedScriptID: String?
    @State private var mode: Profile.OverwriteMode
    @State private var customGroups: [CustomProxyGroup]
    @State private var customRules: [String]
    @State private var proxyChain: ProxyChainSpec
    @State private var legacyRelayMigrations: [LegacyRelayMigration]
    @State private var error = ""
     
    @State private var refusal: CustomOverwriteError?
     
    @State private var saving = false
    @State private var isConfirmingQuickFill = false
    @State private var editingRule: RuleEditTarget?
    @State private var editingScript: ConfigScript?
    @State private var addingScriptSheet = false
    @State private var scriptAddress = ""
    @State private var importingScript = false
    @State private var showsScriptFileImporter = false
    @State private var scriptFailure = ""
    @State private var showsScriptFailure = false
    @State private var deletingScript: ConfigScript?
     
    @State private var renamingScript: ConfigScript?
     
    @State private var scriptRefusal: ScriptSaveRefusal?
    @State private var scriptName = ""

    private let globalRules: [String]
    @State private var scripts: [ConfigScript]
    private let scriptLibrary: UserDefaults
    @State private var updatingScripts = false
    @Environment(\.clashFeedback) private var feedback
     
     
     
     
    @State private var rawYAML: String?
    private let loadRawYAML: (() async -> String?)?
    @State private var projectionPending: Bool
    private let opensProxyChainsDirectly: Bool
    private let configurationCenter: Bool
     
     
    private let ownsNavigationContainer: Bool

    private struct RuleEditTarget: Identifiable {
        let id = UUID()
         
         
         
        let rowID: UUID?
        let raw: String
    }

     
    @State private var ruleRows = ClashIdentifiedRows()
     
     
    @State private var draftSlot: ClashDraftSlot<ProfileOverrideDraft>
     
    @State private var showsRestoredDraft: Bool
     
     
     
     
    @State private var publishedRuleSets: (options: ClashRulePolicyOptions, savedAs: RuleSetInputs)?

     
     
     
    private struct RuleSetInputs: Equatable {
        let scriptID: String?
        let scriptBody: String?
        let mode: Profile.OverwriteMode
        let patchText: String
    }

    private func ruleSetInputs(scriptID: String?, mode: Profile.OverwriteMode, patchText: String) -> RuleSetInputs {
        RuleSetInputs(scriptID: scriptID, scriptBody: scripts.first { $0.id == scriptID }?.body, mode: mode, patchText: patchText)
    }

    init(
        profile: Profile,
        rawYAML: String?,
        openProxyChains: Bool = false,
        configurationCenter: Bool = false,
        ownsNavigationContainer: Bool = true,
        scriptLibrary: UserDefaults = ScriptLibrary.appGroupDefaults,
        loadRawYAML: (() async -> String?)? = nil,
        save: @escaping (Profile) throws -> Void
    ) {
        let settingsFacade = ProfileSettingsFacade()
        let settings = settingsFacade.snapshot(for: profile)
        self.configurationCenter = configurationCenter
        self.ownsNavigationContainer = ownsNavigationContainer
        self.profile = profile
        self.save = save
        _rawYAML = State(initialValue: rawYAML)
        self.loadRawYAML = loadRawYAML
        _projectionPending = State(initialValue: rawYAML == nil && loadRawYAML != nil)
        self.settingsFacade = settingsFacade
        opensProxyChainsDirectly = openProxyChains
        globalRules = settings.migratedGlobalOverride?.appendRules ?? []
        self.scriptLibrary = scriptLibrary
        let library = ScriptLibrary.load(from: scriptLibrary)
        _scripts = State(initialValue: library)
        let slot = Self.draftSlot(for: profile, scripts: library, store: SourceEditDrafts.shared)
        _draftSlot = State(initialValue: slot)
        let opening = slot.opening()
         
        let draft = opening.needsNotice ? opening.value.choosingOnly(from: library) : opening.value
        _showsRestoredDraft = State(initialValue: opening.needsNotice)
        _patchText = State(initialValue: draft.patchText)
        _rules = State(initialValue: draft.rules)
        _prependRules = State(initialValue: draft.prependRules)
        _disabledGlobalRules = State(initialValue: Set(draft.disabledGlobalRules))
        _selectedScriptID = State(initialValue: draft.selectedScriptID)
        _mode = State(initialValue: draft.mode)
        _customGroups = State(initialValue: draft.customGroups)
        _customRules = State(initialValue: draft.customRules)
        _proxyChain = State(initialValue: draft.proxyChain)
        _legacyRelayMigrations = State(initialValue: draft.legacyRelayMigrations)
    }

     
    static func savedDraft(for profile: Profile) -> ProfileOverrideDraft {
        let settings = ProfileSettingsFacade().snapshot(for: profile)
        return ProfileOverrideDraft(
            patchText: prettyJSON(settings.override.patchJSON),
            rules: settings.override.appendRules,
            prependRules: settings.override.prependRules,
            disabledGlobalRules: settings.override.disabledGlobalRules ?? [],
            selectedScriptID: settings.selectedScriptID,
            mode: settings.overwriteMode ?? .standard,
            customGroups: settings.customOverwrite?.proxyGroups ?? [],
            customRules: settings.customOverwrite?.rules ?? [],
            proxyChain: settings.proxyChain ?? ProxyChainSpec(),
            legacyRelayMigrations: settings.legacyRelayMigrations ?? []
        )
    }

     
     
     
     
     
     
    static func draftSlot(for profile: Profile, scripts: [ConfigScript],
                          store: (any ClashUnsavedDraftStore)?) -> ClashDraftSlot<ProfileOverrideDraft> {
        ClashDraftSlot(key: "Profile Override|\(profile.id)", original: savedDraft(for: profile), store: store,
                       sameBasis: { recorded, current in
            guard recorded != current else { return true }
            guard current.selectedScriptID == nil, let gone = recorded.selectedScriptID,
                  !scripts.contains(where: { $0.id == gone }) else { return false }
            var unlinked = recorded
            unlinked.selectedScriptID = nil
            return unlinked == current
        })
    }

     
     
     
    static func committing(_ updated: Profile, with save: (Profile) throws -> Void,
                           slot draftSlot: ClashDraftSlot<ProfileOverrideDraft>) throws {
        try save(updated)
        draftSlot.commit()
    }

    private var currentDraft: ProfileOverrideDraft {
        ProfileOverrideDraft(patchText: patchText, rules: rules, prependRules: prependRules,
                             disabledGlobalRules: Array(disabledGlobalRules), selectedScriptID: selectedScriptID,
                             mode: mode, customGroups: customGroups, customRules: customRules,
                             proxyChain: proxyChain, legacyRelayMigrations: legacyRelayMigrations)
    }

    private var restoredNotice: some View {
        HStack(spacing: ClashTheme.Spacing.compact) {
            ClashStatusMessage(text: .copy("Unsaved edits from last time were restored."), kind: .information)
                .accessibilityIdentifier("profile.override.restored")
            Spacer(minLength: 0)
            Button("Discard", role: .destructive) { discardDraft() }
                .font(.subheadline)
                .accessibilityIdentifier("profile.override.restored.discard")
        }
        .padding(.horizontal, ClashTheme.Spacing.standard)
        .padding(.vertical, ClashTheme.Spacing.compact)
    }

     
    private func discardDraft() {
        let saved = draftSlot.original
        patchText = saved.patchText
        rules = saved.rules
        prependRules = saved.prependRules
        disabledGlobalRules = Set(saved.disabledGlobalRules)
        selectedScriptID = saved.selectedScriptID
        mode = saved.mode
        customGroups = saved.customGroups
        customRules = saved.customRules
        proxyChain = saved.proxyChain
        legacyRelayMigrations = saved.legacyRelayMigrations
        draftSlot.clear()
        showsRestoredDraft = false
    }

    var body: some View {
        ClashFeatureNavigationContainer(ownsNavigationContainer: ownsNavigationContainer) {
            Group {
            if opensProxyChainsDirectly {
                ProfileProxyChainEditorHost(
                    rawYAML: rawYAML,
                    draft: chainDraft(),
                    spec: $proxyChain,
                    legacyRelayMigrations: $legacyRelayMigrations
                )
                .clashSheetPresentation()
                .clashToolbarUnlessInPanel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { draftSlot.clear(); dismissPresentation() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        ClashSaveButton { persist() }
                            .disabled(saving)
                    }
                }
            } else {
            Form {

                 
                 
                 
                 
                 
                 
                 
                 
                if mode != .custom, !configurationCenter {
                    Section {
                        CodeEditorPanel(
                            text: $patchText,
                            language: .json,
                            minHeight: 260,
                            diagnostic: patchDiagnostic
                        )
                    } header: {
                        Text("Patch JSON")
                    }

                    addedRulesSection
                }
                     
                     
                     
                     
                     
                     
                scriptSections
                if mode == .custom {
                    Section {
                        ClashRoutedViewLink {
                            ClashLazyView {
                                CustomProxyGroupsEditorHost(
                                    groups: $customGroups,
                                    profileProxyNames: memberCandidateNames,
                                    rawYAML: rawYAML,
                                    profile: profile,
                                    onRename: { old, new in
                                         
                                         
                                         
                                        var spec = CustomOverwriteSpec(
                                            proxyGroups: customGroups,
                                            rules: customRules
                                        )
                                        spec.renameProxyGroup(from: old, to: new)
                                        customGroups = spec.proxyGroups
                                        customRules = spec.rules
                                    }
                                )
                            }
                        } label: {
                            ClashDestinationRow(
                                title: "Proxy Groups",
                                subtitle: .format(
                                    "%@ groups",
                                    [String(customGroups.count)]
                                ),
                                symbol: .point3ConnectedTrianglepathDotted,
                                tint: .blue
                            )
                        }
                        .accessibilityIdentifier("profile.override.proxy-groups")
                        ClashRoutedViewLink {
                            CustomRulesEditor(
                                rules: $customRules,
                                options: policyOptions,
                                draftScope: "Profile Override|\(profile.id)|custom"
                            )
                        } label: {
                            ClashDestinationRow(
                                title: "Rules",
                                subtitle: .format(
                                    "%@ rules",
                                    [String(customRules.count)]
                                ),
                                symbol: .listBulletRectangle,
                                tint: .orange
                            )
                        }
                        Button("Quick Fill from Source") {
                             
                             
                            if customGroups.isEmpty, customRules.isEmpty {
                                quickFill()
                            } else {
                                isConfirmingQuickFill = true
                            }
                        }
                        .accessibilityIdentifier("profile-override.quick-fill")
                        .clashMacFormActionChrome()
                        Button("Remove Custom Overrides", role: .destructive) {
                            customGroups = []
                            customRules = []
                            mode = .standard
                        }
                        .accessibilityIdentifier("profile.override.custom.remove")
                        .clashMacFormActionChrome()
                    } header: {
                        Text("Custom Overrides")
                    }
                }

                if !configurationCenter || !proxyChain.isEmpty || !legacyRelayMigrations.isEmpty {
                Section {
                    ClashRoutedViewLink {
                        ProfileProxyChainEditorHost(
                            rawYAML: rawYAML,
                            draft: chainDraft(),
                            spec: $proxyChain,
                            legacyRelayMigrations: $legacyRelayMigrations
                        )
                    } label: {
                        ClashDestinationRow(
                            title: "Proxy Chains",
                            subtitle: proxyChainSubtitle,
                            symbol: .arrowTriangleBranch,
                            tint: .indigo
                        )
                    }
                    .accessibilityIdentifier("profile.override.proxy-chains")
                } header: {
                    Text("Proxy Identity")
                } footer: {
                    Text("Add chains in Node Library.")
                }

                }

                if !globalRules.isEmpty {
                    Section {
                        ForEach(globalRules, id: \.self) { rule in
                            Toggle(
                                isOn: Binding(
                                    get: { !disabledGlobalRules.contains(rule) },
                                    set: { enabled in
                                        if enabled { disabledGlobalRules.remove(rule) }
                                        else { disabledGlobalRules.insert(rule) }
                                    }
                                )
                            ) { ConfigurationRuleRow(rule, showsChevron: false) }
                             
                             
                             
                            .accessibilityIdentifier("profile.override.migrated-rule.\(rule)")
                        }
                    } header: {
                        Text("Migrated Rules")
                    }
                }

                if !error.isEmpty {
                    ClashStatusMessage(text: CustomOverwriteError.displayText(for: error, from: refusal), kind: .error)
                }
                 
                 
                 
                 
            }
            .clashPageTitle(.copy(configurationCenter ? "Overrides and Scripts" : "Profile Override"))
             
             
             
             
             
             
             
             
            .task(id: profile.id) {
                if projectionPending, let loadRawYAML {
                    let loaded = await loadRawYAML()
                    if rawYAML == nil { rawYAML = loaded }
                    projectionPending = false
                }
                let saved = draftSlot.original
                let savedAs = ruleSetInputs(scriptID: saved.selectedScriptID, mode: saved.mode, patchText: saved.patchText)
                publishedRuleSets = (await ProfileRulesAdapter.loadPublishedRuleSets(of: profile), savedAs)
            }
            .onReceive(NotificationCenter.default.publisher(for: ScriptLibrary.didChange)) { _ in
                scripts = ScriptLibrary.load(from: scriptLibrary)
                if let selected = selectedScriptID, !scripts.contains(where: { $0.id == selected }) {
                    selectedScriptID = nil
                }
            }
             
             
             
             
            .alert(
                "Replace your custom groups and rules?",
                isPresented: $isConfirmingQuickFill
            ) {
                Button("Replace", role: .destructive) { quickFill() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Quick Fill reads this profile's source and replaces everything you have built here. This cannot be undone.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !insideProductModal {
                        Button("Cancel") { draftSlot.clear(); dismissPresentation() }
                    }
                }
                 
                 
                 
                 
                ToolbarItem(placement: .clashNavigationTrailing) {
                     
                     
                     
                    if !insideProductModal {
                        Button { Task { await updateScripts() } } label: {
                            Label("Update Scripts", systemImage: ClashSymbol.arrowClockwise.name)
                        }
                        .disabled(updatingScripts)
                        .accessibilityIdentifier("profile.override.scripts.update")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !insideProductModal {
                        ClashSaveButton { persist() }
                            .disabled(projectionPending || saving)
                    }
                }
#if !os(macOS)
                ToolbarItem(placement: .bottomBar) {
                     
                     
                     
                    if !configurationCenter, mode != .custom, !rules.isEmpty {
                        ClashEditButton()
                    }
                }
#endif
            }
            .clashProductModalRoot(
                title: configurationCenter ? "Overrides and Scripts" : "Profile Override",
                 
                 
                 
                 
                actionTitle: "Update Scripts",
                actionDisabled: updatingScripts,
                action: { Task { await updateScripts() } }
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if insideProductModal {
                    ClashModalActionBar(
                        primaryTitle: "Save",
                    primaryDisabled: !hasChanges || projectionPending || saving,
                        onPrimary: persist
                    )
                }
            }
            .clashProductModal(item: $editingRule, role: .page) { target in
                RuleBuilderAdapter(
                    raw: target.raw,
                    options: policyOptions,
                    draftKey: ClashRuleBuilderDraft.key(scope: "Profile Override|\(profile.id)", raw: target.raw,
                                                        index: target.rowID.flatMap(ruleRows.index(of:)), in: rules)
                ) { rule in
                    if let id = target.rowID {
                        ruleRows.update(id, in: &rules, to: rule)
                    } else if !rules.contains(rule) {
                        ruleRows.append(rule, to: &rules)
                    }
                }
                .clashModalPresentation(.page)
            }
             
            .clashProductModal(item: $editingScript, role: .page, immersive: { _ in true }) { script in
                ScriptEditorView(script: script, check: scriptCheck(for: script), rename: { [scriptLibrary] name in
                    try ScriptLibrary.rename(id: script.id, to: name, in: scriptLibrary)
                     
                     
                    if let renamed = ScriptLibrary.load(from: scriptLibrary).first(where: { $0.id == script.id }) {
                        editingScript?.label = renamed.label
                    }
                }) { saved in
                    ScriptLibrary.upsert(saved, in: scriptLibrary)
                    editingScript = nil
                }
                .clashModalPresentation(.page)
            }
            .clashProductModal(isPresented: $addingScriptSheet, role: .page) {
                ScriptManualPage(library: scriptLibrary, close: { addingScriptSheet = false }) { added in
                     
                     
                    acceptAddedScript(added)
                }
                .clashModalPresentation(.page)
            }
            .fileImporter(isPresented: $showsScriptFileImporter,
                          allowedContentTypes: [.javaScript, .plainText, .text],
                          allowsMultipleSelection: false) { outcome in
                do { acceptAddedScript(try ScriptAddOutcome.fromFile(outcome, in: scriptLibrary)) }
                catch { failScriptAdd(ClashErrorCopy.message(error, locale: locale)) }
            }
            .alert("Import Failed", isPresented: $showsScriptFailure) {
                Button("OK") {}
            } message: {
                Text(verbatim: scriptFailure)
            }
            .scriptSaveRefusalAlert($scriptRefusal)
             
             
             
             
             
             
            .clashTextFieldAlert("Rename…", isPresented: Binding(get: { renamingScript != nil }, set: { if !$0 { renamingScript = nil } }),
                                 presenting: renamingScript, text: $scriptName,
                                 field: ClashTextFieldAlertField(placeholder: "Script name",
                                                                 identifier: "profile.override.script.rename.name"),
                                 isConfirmEnabled: { script, name in renameIsValid(script, name: name) }) { script, name in
                commitRename(script, name: name)
            }
            }
            }
             
             
             
             
             
             
            .clashPinnedTopBar {
                if showsRestoredDraft { restoredNotice }
            }
        }
        .clashStackNavigationViewStyle()
        .onChange(of: currentDraft) { draftSlot.record($0) }
        .clashCapturesDismiss(dismiss)
    }

     
     
     
     
     
     
     
     
     
     
    private var hasChanges: Bool {
        guard let updated = try? draftProfile() else { return true }
        return updated != profile
    }

    private func persist() {
        guard !saving else { return }
        let updated: Profile
        do {
            updated = try draftProfile()
            if rawYAML == nil, !proxyChain.isEmpty || !legacyRelayMigrations.isEmpty {
                throw PipelineError.sourceUnavailable(
                    "Sync or activate this profile before configuring proxy chains."
                )
            }
        } catch {
            report(error)
            return
        }
        guard let rawYAML else {
            do { try Self.committing(updated, with: save, slot: draftSlot) } catch { return reportSaveFailure(error) }
            dismissPresentation()
            return
        }
         
         
         
        saving = true
         
         
         
         
        let library = ScriptSaveCheck.runsAScript(updated) ? ScriptLibrary.load(from: scriptLibrary) : nil
        Task { @MainActor in
            defer { saving = false }
            let verdict: ScriptSaveCheck.Verdict
            do {
                verdict = try await Task.detached(priority: .userInitiated) {
                     
                    _ = try ProfileRuntimeConfigBuilder.runtimePreview(raw: rawYAML, profile: updated, scripts: .surfaced)
                    guard let library else { return ScriptSaveCheck.Verdict.accepted }
                    return ScriptSaveCheck.verdict(raw: rawYAML, profile: updated, scripts: library)
                }.value
            } catch let failure as ScriptEngine.ScriptError {
                 
                 
                scriptRefusal = ScriptSaveRefusal(reason: .reading(scriptFailure: failure),
                                                  saveAnyway: nil, keepEditing: {})
                return
            } catch {
                return report(error)
            }
            switch verdict {
            case .accepted:
                commitAndClose(updated)
            case .refused(let reason):
                scriptRefusal = ScriptSaveRefusal(reason: reason, saveAnyway: { commitAndClose(updated) },
                                                  keepEditing: {})
            case .scriptFailed(let reason):
                scriptRefusal = ScriptSaveRefusal(reason: reason, saveAnyway: nil, keepEditing: {})
            }
        }
    }

    private func commitAndClose(_ updated: Profile) {
        do { try Self.committing(updated, with: save, slot: draftSlot) } catch { return reportSaveFailure(error) }
        dismissPresentation()
    }

     
     
     
     
    private func scriptCheck(for script: ConfigScript) -> ((ConfigScript) async -> ScriptSaveCheck.Verdict)? {
        guard let rawYAML, ScriptSaveCheck.runs(script.id, in: profile) else { return nil }
        let profile = profile
        let library = scriptLibrary
        return { edited in
            var scripts = ScriptLibrary.load(from: library)
            if let index = scripts.firstIndex(where: { $0.id == edited.id }) {
                scripts[index] = edited
            } else {
                scripts.append(edited)
            }
            return await Task.detached(priority: .userInitiated) {
                ScriptSaveCheck.verdict(raw: rawYAML, profile: profile, scripts: scripts)
            }.value
        }
    }

     
    private func reportSaveFailure(_ error: Error) {
        patchDiagnostic = nil
        refusal = nil
        self.error = error.localizedDescription
    }

    private func report(_ error: Error) {
        if let refusal = error as? PatchKeysSetElsewhere {
            patchDiagnostic = nil
            self.refusal = nil
            self.error = refusal.sentence(locale: locale)
            return
        }
        patchDiagnostic = CodeEditorDiagnostic.parsed(from: error.localizedDescription, in: patchText)
        refusal = error as? CustomOverwriteError
        if error is CustomOverwriteError
            || error is ProxyChainError
            || error is LegacyRelayMigrationError
            || error is PipelineError {
            self.error = error.localizedDescription
        } else {
            self.error = ClashCopy.format("Patch JSON must be an object: %@", locale: locale, error.localizedDescription)
        }
    }

    private func dismissPresentation() {
        dismiss.closeModalOrDismiss()
    }

     
     
     
     
    @ViewBuilder
    private func scriptRow(_ script: ConfigScript) -> some View {
        let selected = selectedScriptID == script.id
        HStack(spacing: 0) {
            Button {
                 
                 
                selectedScriptID = selected ? nil : script.id
            } label: {
                HStack(alignment: .center, spacing: ClashTheme.Spacing.row) {
                    Group {
                        if selected {
                            Image(systemName: ClashSymbol.checkmark.rawValue)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.tint)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                    Text(verbatim: script.label)
                        .font(.body.weight(selected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: ClashTheme.Spacing.compact)
                }
                .padding(.leading, ClashTheme.Spacing.standard)
                .padding(.vertical, ClashMacSettingsMetrics.rowVerticalInset(touch: ClashTheme.Spacing.row))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("profile.override.script.\(script.id)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityAction(named: Text("Rename…")) { beginRename(script) }
            Button {
                editingScript = script
            } label: {
                Image(systemName: ClashSymbol.infoCircle.rawValue)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: ClashClientUI.ClashTheme.Control.minimumHitTarget,
                           height: ClashClientUI.ClashTheme.Control.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit")
            .accessibilityIdentifier("profile.override.script.edit.\(script.id)")
            .padding(.trailing, ClashTheme.Spacing.standard)
        }
         
         
        .accessibilityElement(children: .contain)
         
         
         
        .listRowInsets(EdgeInsets())
        .contextMenu {
            Button { beginRename(script) } label: { Label("Rename…", systemImage: ClashSymbol.pencil.name) }
                .accessibilityIdentifier("profile.override.script.rename")
        }
         
        .clashSwipeToDelete { removeScriptWithUndo(script) }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { beginRename(script) } label: { Label("Rename…", systemImage: ClashSymbol.pencil.name) }
                .tint(.gray)
                .accessibilityIdentifier("profile.override.script.rename")
            if !(script.sourceURL ?? "").isEmpty {
                 
                 
                 
                 
                 
                Button {
                    Task { @MainActor in await updateScripts(only: script) }
                } label: {
                    Label("Update", systemImage: ClashSymbol.arrowClockwise.name)
                }
                .tint(.blue)
                .accessibilityIdentifier("profile.override.script.update")
            }
        }
    }

     
     
    private var policyOptions: RulePolicyOptions {
         
         
         
        let published = publishedRuleSets.flatMap { loaded in
            loaded.savedAs == ruleSetInputs(scriptID: selectedScriptID, mode: mode, patchText: patchText) ? loaded.options : nil
        }
        return RulePolicyOptions
            .make(sourceYAML: rawYAML)
            .including(customGroups: customGroups)
            .adopting(published: published)
    }

    private func quickFill() {
        do {
            guard let rawYAML else {
                error = "Sync or activate this profile before using Quick Fill."
                return
            }
            let parsed = try CustomOverwriteSpec.parse(sourceYAML: rawYAML)
            customGroups = parsed.proxyGroups
            customRules = parsed.rules
            error = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

     
     
     
    private func chainDraft() -> Result<Profile, Error> {
        Result {
            var draft = try draftProfile()
            draft.proxyChain = nil
            return draft
        }
    }

    nonisolated static func chainBase(rawYAML: String?, draft: Result<Profile, Error>) -> Result<String, Error> {
        Result {
            guard let rawYAML else {
                throw PipelineError.sourceUnavailable(
                    "Sync or activate this profile before configuring proxy chains."
                )
            }
             
             
            return try ProfileRuntimeConfigBuilder.buildProduction(
                raw: rawYAML,
                profile: try draft.get(),
                applyProxyChain: false,
                applyLegacyRelayMigration: false, scripts: .surfaced
            )
        }
    }

     
     

    private func importScriptLink() {
        let address = scriptAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, !importingScript else { return }
        importingScript = true
        Task { @MainActor in
            defer { importingScript = false }
            do { acceptAddedScript(try await ScriptAddOutcome.fromLink(address, in: scriptLibrary)) }
            catch { failScriptAdd(ClashErrorCopy.message(error, locale: locale)) }
        }
    }

    private func acceptAddedScript(_ script: ConfigScript) {
        scripts = ScriptLibrary.load(from: scriptLibrary)
        selectedScriptID = script.id
        scriptAddress = ""
        addingScriptSheet = false
    }

    private func failScriptAdd(_ message: String) {
        scriptFailure = message
        showsScriptFailure = true
    }

    private func beginRename(_ script: ConfigScript) {
        scriptName = script.label
        renamingScript = script
    }

     
     
    private func renameIsValid(_ script: ConfigScript, name: String) -> Bool {
        ScriptLibrary.editedScript(id: script.id, label: name, body: script.body,
                                          existing: scripts) != nil
    }

     
     
    private func commitRename(_ script: ConfigScript, name: String) {
        do { try ScriptLibrary.rename(id: script.id, to: name, in: scriptLibrary) }
        catch { failScriptAdd(error.localizedDescription) }
    }

    @ViewBuilder
    private var scriptSections: some View {
         
         
         
        let chosen = scripts.first { $0.id == selectedScriptID }
        let others = scripts.filter { $0.id != selectedScriptID }
        if let chosen {
            Section {
                scriptRow(chosen)
            } header: {
                Text("Script").accessibilityIdentifier("profile.override.scripts.selected")
            }
        }
        if !others.isEmpty {
            Section {
                ForEach(others) { script in
                    scriptRow(script)
                }
            } header: {
                if chosen == nil {
                     
                     
                     
                    Text("Scripts")
                } else {
                    Text("Other Scripts").accessibilityIdentifier("profile.override.scripts.other")
                }
            }
        }
         
         
         
        Section {
             
             
            HStack(spacing: ClashTheme.Spacing.standard) {
                TextField("", text: $scriptAddress, prompt: Text(verbatim: "https://example.com/script.js"))
#if !os(macOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { importScriptLink() }
                    .disabled(importingScript)
                    .accessibilityIdentifier("scripts.add.link.address")
                ClashPasteControl(style: .square) { pasted in
                    scriptAddress = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                    importScriptLink()
                }
                .disabled(importingScript)
            }
            if importingScript {
                HStack(spacing: ClashTheme.Spacing.compact) {
                    ProgressView().controlSize(.small)
                    Text(clash: .copy("Importing…")).font(.subheadline).foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("scripts.add.status")
            }
             
             
            Button {
                showsScriptFileImporter = true
            } label: {
                Label(ClashCopy.key("Import File"), systemImage: ClashSymbol.arrowUpDocument.name)
            }
            .disabled(importingScript)
            .accessibilityIdentifier("profile.override.script.add.file")
            Button {
                addingScriptSheet = true
            } label: {
                Label(ClashCopy.key("New Script"), systemImage: ClashSymbol.docBadgePlus.name)
            }
            .disabled(importingScript)
            .accessibilityIdentifier("profile.override.script.add")
        } header: {
            ClashConfigurationLibraryHeader(title: .copy("Add Script"))
        }
         
         
         
    }

     
     
    private var addedRulesSection: some View {
                    Section {
                        ForEach(ruleRows.current(for: rules)) { row in
                            let rule = ruleRows.index(of: row.id)
                                .map { rules[$0] } ?? ""
                            ClashMacDeletableRow(onDelete: {
                                ruleRows.remove(row.id, from: &rules)
                            }) {
                                Button {
                                    editingRule = RuleEditTarget(rowID: row.id, raw: rule)
                                } label: {
                                    Text(rule)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                        .onDelete { ruleRows.removeOffsets($0, from: &rules) }
                        .onMove { ruleRows.move(fromOffsets: $0, toOffset: $1, in: &rules) }
                        .onAppear { ruleRows.resync(count: rules.count) }
                        .onChange(of: rules.count) { ruleRows.resync(count: $0) }

                        ClashAddRow(Text("Add Rule")) {
                            editingRule = RuleEditTarget(rowID: nil, raw: "")
                        } touchLabel: {
                            Label("Add Rule", systemImage: ClashSymbol.plus.name)
                        }
                        Toggle("Insert before profile URL rules", isOn: $prependRules)
                            .accessibilityIdentifier("profile.override.prepend-rules")
                    } header: {
                        Text("Added Rules")
                    }
    }

    private func draftProfile() throws -> Profile {
        let trimmed = patchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let patchJSON: String
        if mode == .custom || trimmed.isEmpty || trimmed == "{}" {
            patchJSON = ""
        } else {
            let value = try JSONSerialization.jsonObject(with: Data(trimmed.utf8))
            guard value is [String: Any] else {
                throw CocoaError(.propertyListReadCorrupt)
            }
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            patchJSON = String(decoding: data, as: UTF8.self)
             
             
             
            if !configurationCenter, let refusal = PatchKeysSetElsewhere(patchJSON: patchJSON) { throw refusal }
        }

        let customOverwrite = CustomOverwriteSpec(
            proxyGroups: customGroups,
            rules: customRules
        )
        if mode == .custom { try customOverwrite.validate() }

        var settings = settingsFacade.snapshot(for: profile)
         
        settings.override.patchJSON = patchJSON
        settings.override.appendRules = rules
        settings.override.prependRules = prependRules
        settings.override.disabledGlobalRules = globalRules.filter(disabledGlobalRules.contains)
         
         
        let chosenScriptID = selectedScriptID.flatMap { id in
            id == settings.selectedScriptID || scripts.contains(where: { $0.id == id }) ? id : nil
        }
        settings.selectedScriptID = chosenScriptID
        settings.overwriteMode = ProfileOverrideModePolicy.mode(stored: mode, selectedScriptID: chosenScriptID)
        settings.customOverwrite = customOverwrite
        settings.proxyChain = proxyChain.isEmpty ? nil : proxyChain
        settings.legacyRelayMigrations = legacyRelayMigrations.isEmpty
            ? nil
            : legacyRelayMigrations
        return settingsFacade.applying(settings, to: profile)
    }

     
     
     
     
    private func removeScriptWithUndo(_ script: ConfigScript) {
        guard let removal = ScriptLibrary.removeRestorably(id: script.id, in: scriptLibrary) else { return }
        let wasSelected = selectedScriptID == script.id
        if wasSelected { selectedScriptID = nil }
        let feedback = feedback, library = scriptLibrary
        feedback?.show(.success(title: ClashFeedbackCopy.deleted(script.label), action: .undo,
                                accessibilityIdentifier: "feedback.scripts.delete"),
                       operation: "scripts.delete",
                       perform: {
            do {
                try ScriptLibrary.restore(removal, in: library)
                if wasSelected, selectedScriptID == nil { selectedScriptID = script.id }
                feedback?.show(.success(title: ClashFeedbackCopy.restored(script.label),
                                        accessibilityIdentifier: "feedback.scripts.delete"), operation: "scripts.delete")
            } catch {
                feedback?.show(.error(title: ClashFeedbackCopy.couldNotUndo, message: .copy(error.localizedDescription),
                                      accessibilityIdentifier: "feedback.scripts.delete"), operation: "scripts.delete")
            }
        })
    }

    @MainActor
    private func updateScripts(only: ConfigScript? = nil) async {
        guard !updatingScripts else { return }
        updatingScripts = true
        defer { updatingScripts = false }
        let targets = only.map { [$0] } ?? scripts.filter { !($0.sourceURL ?? "").isEmpty }
        let operation = only.map { "script.update.\($0.id)" } ?? "override.scripts.update"
        if targets.isEmpty {
            feedback?.show(ScriptUpdateSummary.nothingToFetch, operation: operation)
            return
        }
        let running = feedback?.show(.loading(title: ClashFeedbackCopy.updating, accessibilityIdentifier: "feedback.scripts.update"),
                                     operation: operation)
        var outcome = ScriptUpdateSummary()
        var failedIDs: Set<String> = []
        for script in targets {
            do {
                let refreshed = try await ScriptImport.refreshed(script)
                if refreshed.body != script.body {
                    ScriptLibrary.upsert(refreshed, in: scriptLibrary)
                    outcome.changed.append(script.label)
                } else {
                    outcome.unchanged.append(script.label)
                }
            } catch {
                outcome.failed.append((script.label, error.localizedDescription))
                failedIDs.insert(script.id)
            }
        }
        let retry: @MainActor () -> Void = {
            Task {
                 
                for script in ScriptLibrary.load(from: scriptLibrary) where failedIDs.contains(script.id)
                    && !(script.sourceURL ?? "").isEmpty { await updateScripts(only: script) }
            }
        }
        feedback?.answer(running, with: outcome.presentation(), operation: operation, perform: retry)
    }

    private var proxyChainSubtitle: ClashDisplayText {
        let chainCount = proxyChain.assignments.count
        let relayCount = legacyRelayMigrations.count
        if chainCount == 0 && relayCount == 0 {
            return "Use generated proxy identities"
        }
        if chainCount > 0, relayCount > 0 {
            return .format(
                "%@ chain overrides · %@ relay migrations",
                [String(chainCount), String(relayCount)]
            )
        }
        return chainCount > 0
            ? .format("%@ chain overrides", [String(chainCount)])
            : .format("%@ relay migrations", [String(relayCount)])
    }

     
     
    private var memberCandidateNames: [String] {
        guard let rawYAML,
              let inventory = try? ProxyChainSpec.inventory(from: rawYAML)
        else { return [] }
        return inventory.map(\.name)
    }

    private static func prettyJSON(_ raw: String) -> String {
        guard !raw.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

 
 
 
 
 
struct ProfileOverrideDraft: Codable, Equatable {
    var patchText: String
    var rules: [String]
    var prependRules: Bool
     
    var disabledGlobalRules: [String]
    var selectedScriptID: String?
    var mode: Profile.OverwriteMode
    var customGroups: [CustomProxyGroup]
    var customRules: [String]
    var proxyChain: ProxyChainSpec
    var legacyRelayMigrations: [LegacyRelayMigration]

    init(patchText: String, rules: [String], prependRules: Bool, disabledGlobalRules: [String],
         selectedScriptID: String?, mode: Profile.OverwriteMode, customGroups: [CustomProxyGroup],
         customRules: [String], proxyChain: ProxyChainSpec, legacyRelayMigrations: [LegacyRelayMigration]) {
        self.patchText = patchText
        self.rules = rules
        self.prependRules = prependRules
        self.disabledGlobalRules = disabledGlobalRules.sorted()
        self.selectedScriptID = selectedScriptID
        self.mode = mode
        self.customGroups = customGroups
        self.customRules = customRules
        self.proxyChain = proxyChain
        self.legacyRelayMigrations = legacyRelayMigrations
    }

     
    func choosingOnly(from scripts: [ConfigScript]) -> ProfileOverrideDraft {
        var draft = self
        if let id = selectedScriptID, !scripts.contains(where: { $0.id == id }) { draft.selectedScriptID = nil }
        return draft
    }
}

struct ProfileProxyChainDerivedState: Equatable {
    let relayAssessments: [LegacyRelayAssessment]
    let validationMessage: String

    static func evaluate(
        baseYAML: String?,
        baseError: String,
        inventory: [ProxyIdentity],
        spec: ProxyChainSpec,
        payloadEdits: [ProxyPayloadDialerEdit],
        legacyRelayMigrations: [LegacyRelayMigration]
    ) -> Self {
        guard baseError.isEmpty else {
            return Self(relayAssessments: [], validationMessage: "")
        }
        do {
            let overlaid = overlay(
                inventory: inventory,
                payloadEdits: payloadEdits
            )
            try spec.validate(in: overlaid)
            guard let baseYAML else {
                throw PipelineError.sourceUnavailable(
                    "Sync or activate this profile before configuring proxy chains."
                )
            }
            let generated = try spec.apply(to: baseYAML)
            let assessments =
                (try? LegacyRelayMigrationEngine.assess(generated)) ?? []
            do {
                _ = try LegacyRelayMigrationEngine.apply(
                    legacyRelayMigrations,
                    to: generated
                )
                return Self(
                    relayAssessments: assessments,
                    validationMessage: ""
                )
            } catch is LegacyRelayMigrationError where !assessments.isEmpty {
                 
                 
                return Self(
                    relayAssessments: assessments,
                    validationMessage: ""
                )
            } catch {
                return Self(
                    relayAssessments: assessments,
                    validationMessage: error.localizedDescription
                )
            }
        } catch {
            return Self(
                relayAssessments: [],
                validationMessage: error.localizedDescription
            )
        }
    }

    static func overlay(
        inventory: [ProxyIdentity],
        payloadEdits: [ProxyPayloadDialerEdit]
    ) -> [ProxyIdentity] {
        guard !payloadEdits.isEmpty else { return inventory }
        let edits = payloadEdits.reduce(into: [String: String]()) {
             
             
             
            $0["\($1.provider)\u{001F}\($1.node)"] = $1.dialerProxy
        }
        return inventory.map { identity in
            guard identity.kind == .payloadProxy,
                  let provider = identity.provider,
                  let edit = edits["\(provider)\u{001F}\(identity.name)"]
            else { return identity }
            return ProxyIdentity(
                name: identity.name,
                type: identity.type,
                dialerProxy: edit,
                kind: identity.kind,
                members: identity.members,
                provider: identity.provider
            )
        }
    }
}

struct ProfileProxyChainPreparation {
    let baseYAML: String?
    let inventory: [ProxyIdentity]
    let error: String
    let derived: ProfileProxyChainDerivedState
    let hasDerivedState: Bool
     
     
     
     
    let scriptTimedOut: Bool

    init(
        baseResult: Result<String, Error>,
        spec: ProxyChainSpec = ProxyChainSpec(),
        legacyRelayMigrations: [LegacyRelayMigration] = [],
        payloadEdits: [ProxyPayloadDialerEdit] = [],
        precomputesDerived: Bool = true
    ) {
        let resolvedYAML: String?
        let identities: [ProxyIdentity]
        let message: String
        if case .failure(let failure) = baseResult {
            scriptTimedOut = failure as? ScriptEngine.ScriptError == .timedOut
        } else {
            scriptTimedOut = false
        }
        switch baseResult {
        case .success(let sourceYAML):
            do {
                let parsedInventory = try ProxyChainSpec.inventory(
                    from: sourceYAML
                )
                self.baseYAML = sourceYAML
                inventory = parsedInventory
                error = ""
                hasDerivedState = precomputesDerived
                derived = precomputesDerived
                    ? ProfileProxyChainDerivedState.evaluate(
                        baseYAML: sourceYAML,
                        baseError: "",
                        inventory: parsedInventory,
                        spec: spec,
                        payloadEdits: payloadEdits,
                        legacyRelayMigrations: legacyRelayMigrations
                    )
                    : ProfileProxyChainDerivedState(
                        relayAssessments: [],
                        validationMessage: ""
                    )
                return
            } catch {
                resolvedYAML = nil
                identities = []
                message = error.localizedDescription
            }
        case .failure(let error):
            resolvedYAML = nil
            identities = []
            message = error.localizedDescription
        }
        baseYAML = resolvedYAML
        inventory = identities
        error = message
        hasDerivedState = true
        derived = ProfileProxyChainDerivedState.evaluate(
            baseYAML: resolvedYAML,
            baseError: message,
            inventory: identities,
            spec: spec,
            payloadEdits: payloadEdits,
            legacyRelayMigrations: legacyRelayMigrations
        )
    }

     
     
     
    static func make(profile: Profile, rawYAML: String?, scripts caller: ScriptEngine.Caller) -> Self {
        let baseResult: Result<String, Error> = Result {
            guard let rawYAML else {
                throw PipelineError.sourceUnavailable(
                    "Sync or prepare this profile before configuring proxy chains."
                )
            }
            var base = profile
            base.proxyChain = nil
            base.legacyRelayMigrations = nil
            return try ProfileRuntimeConfigBuilder.buildProduction(
                raw: rawYAML,
                profile: base,
                applyProxyChain: false,
                applyLegacyRelayMigration: false, scripts: caller
            )
        }
        return ProfileProxyChainPreparation(
            baseResult: baseResult,
            spec: profile.proxyChain ?? ProxyChainSpec(),
            legacyRelayMigrations: profile.legacyRelayMigrations ?? []
        )
    }
}

 
private struct ProfileProxyChainEditorHost: View {
    let rawYAML: String?
    let draft: Result<Profile, Error>
    @Binding var spec: ProxyChainSpec
    @Binding var legacyRelayMigrations: [LegacyRelayMigration]
    @State private var base: Result<String, Error>?

    var body: some View {
        Group {
            if let base {
                ProfileProxyChainEditor(
                    baseResult: base,
                    spec: $spec,
                    legacyRelayMigrations: $legacyRelayMigrations
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
         
         
        .task(id: rawYAML) {
            let rawYAML = rawYAML
            let draft = draft
            base = await Task.detached(priority: .userInitiated) {
                ProfileOverrideView.chainBase(rawYAML: rawYAML, draft: draft)
            }.value
        }
    }
}

 
 
 
private struct CustomProxyGroupsEditorHost: View {
    @Binding var groups: [CustomProxyGroup]
    let profileProxyNames: [String]
    let rawYAML: String?
    let profile: Profile
    let onRename: (String, String) -> Void
    @State private var context: CustomGroupValidationContext?

    private struct Key: Equatable {
        let rawYAML: String?
        let groups: [CustomProxyGroup]
    }

    var body: some View {
        Group {
            if let context {
                CustomProxyGroupsEditor(
                    groups: $groups,
                    profileProxyNames: profileProxyNames,
                    validationContext: context,
                    onRename: onRename,
                    draftScope: profile.id
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: Key(rawYAML: rawYAML, groups: groups)) {
            let rawYAML = rawYAML
            let profile = profile
            let groups = groups
            let built = await Task.detached(priority: .userInitiated) {
                GroupMemberCandidates.validationContext(
                    sourceYAML: rawYAML,
                    profile: profile,
                    draftGroups: groups
                )
            }.value
             
             
            guard !Task.isCancelled else { return }
            context = built
        }
    }
}

 
 
struct ProfileProxyChainEditor: View {
     
     
    @ViewBuilder
    private func legacyRelayRow(
        _ relay: LegacyRelayAssessment
    ) -> some View {
        VStack(alignment: .leading, spacing: ClashTheme.Spacing.compact) {
            HStack(alignment: .firstTextBaseline) {
                Text(relay.groupName)
                    .font(.body.weight(.semibold))
                Spacer()
                if isConfirmed(relay) {
                    ClashStatusBadge(title: "TCP only", tint: .orange)
                }
            }
            Text(clash: .copy(relay.pathDescription))
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let blocker = relay.blocker {
                Text(clash: .copy(blocker.explanation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Edit the profile or rebuild the affected proxies and group before using this profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isConfirmed(relay) {
                Button("Remove Migration", role: .destructive) {
                    confirmingRelayRemoval = relay
                }
                .accessibilityIdentifier(
                    "proxy-chain.legacy-relay.remove.\(relay.groupName)"
                )
            } else {
                Button("Review TCP-only Migration") {
                    confirmingRelay = relay
                }
                .accessibilityIdentifier(
                    "proxy-chain.legacy-relay.review.\(relay.groupName)"
                )
            }
        }
        .padding(.vertical, ClashTheme.Spacing.compact / 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "proxy-chain.legacy-relay.\(relay.groupName)"
        )
        .accessibilityLabel(
            "\(relay.groupName), \(relay.pathDescription)"
        )
    }

    private var legacyRelayFooter: some View {
        EmptyView()
    }

    @Binding var spec: ProxyChainSpec
    @Binding var legacyRelayMigrations: [LegacyRelayMigration]
     
     
     
    @Binding var payloadEdits: [ProxyPayloadDialerEdit]
     
    let measure: ((String) async -> Int?)?
    let openCustomNodes: (() -> Void)?
    let profileName: String?

    private let baseYAML: String?
    private let inventory: [ProxyIdentity]
    private let baseError: String
    private let saveError: String

    @State private var editing: ProxyIdentity?
    @State private var addingChain = false
     
    @State private var delays: [String: Int] = [:]
    @State private var measuring: Set<String> = []
    @State private var migrating: OrphanTarget?
    @State private var confirmingRelay: LegacyRelayAssessment?
    @State private var confirmingRelayRemoval: LegacyRelayAssessment?
    @State private var validationMessage = ""
    @State private var relayAssessments: [LegacyRelayAssessment] = []
    @State private var validatedKey: ValidationKey?

    private struct ValidationKey: Equatable {
        let spec: ProxyChainSpec
        let payloadEdits: [ProxyPayloadDialerEdit]
        let legacyRelayMigrations: [LegacyRelayMigration]
    }

    private struct OrphanTarget: Identifiable {
        let id: String
    }

    init(
        baseResult: Result<String, Error>,
        spec: Binding<ProxyChainSpec>,
        legacyRelayMigrations: Binding<[LegacyRelayMigration]>,
        saveError: String = "",
        payloadEdits: Binding<[ProxyPayloadDialerEdit]> = .constant([]),
        measure: ((String) async -> Int?)? = nil,
        openCustomNodes: (() -> Void)? = nil,
        profileName: String? = nil
    ) {
        self.init(
            preparation: ProfileProxyChainPreparation(
                baseResult: baseResult,
                spec: spec.wrappedValue,
                legacyRelayMigrations: legacyRelayMigrations.wrappedValue,
                payloadEdits: payloadEdits.wrappedValue,
                precomputesDerived: false
            ),
            spec: spec,
            legacyRelayMigrations: legacyRelayMigrations,
            saveError: saveError,
            payloadEdits: payloadEdits,
            measure: measure,
            openCustomNodes: openCustomNodes,
            profileName: profileName
        )
    }

    init(
        preparation: ProfileProxyChainPreparation,
        spec: Binding<ProxyChainSpec>,
        legacyRelayMigrations: Binding<[LegacyRelayMigration]>,
        saveError: String = "",
        payloadEdits: Binding<[ProxyPayloadDialerEdit]> = .constant([]),
        measure: ((String) async -> Int?)? = nil,
        openCustomNodes: (() -> Void)? = nil,
        profileName: String? = nil
    ) {
        _spec = spec
        _legacyRelayMigrations = legacyRelayMigrations
        _payloadEdits = payloadEdits
        self.measure = measure
        self.openCustomNodes = openCustomNodes
        self.profileName = profileName
        self.saveError = saveError
        baseYAML = preparation.baseYAML
        inventory = preparation.inventory
        baseError = preparation.error
        _validationMessage = State(
            initialValue: preparation.derived.validationMessage
        )
        _relayAssessments = State(
            initialValue: preparation.derived.relayAssessments
        )
        _validatedKey = State(initialValue:
            preparation.hasDerivedState
                ? ValidationKey(
                    spec: spec.wrappedValue,
                    payloadEdits: payloadEdits.wrappedValue,
                    legacyRelayMigrations: legacyRelayMigrations.wrappedValue
                )
                : nil
        )
    }

    var body: some View {
        Form {
#if os(macOS)
             
             
             
            if let profileName {
                Section {
                    ClashProfileContextHeader(
                        profileName: profileName,
                        message: "Proxy chains belong to this profile. Its imported source stays unchanged."
                    ) {
                        ClashSymbolImage(symbol: .profileClipboard)
                    }
                }
            }
#endif
            if !baseError.isEmpty {
                Section {
                    ClashStatusMessage(text: .copy(baseError), kind: .error)
                }
            } else if editableInventory.isEmpty && relayAssessments.isEmpty {
                 
                 
                 
                 
                Section {
                    ClashEmptyState(
                        title: "No Proxies",
                        message: "This profile has no proxies that can be linked.",
                        symbol: .arrowTriangleBranch
                    )
                    .listRowSeparator(.hidden)
                }
                if let openCustomNodes {
                    Section {
                        ClashAddRow(Text(ClashCopy.key("Add Custom Node"))) {
                            openCustomNodes()
                        } touchLabel: {
                            Label(
                                ClashCopy.key("Add Custom Node"),
                                systemImage: ClashSymbol.plus.name
                            )
                        }
                        .accessibilityIdentifier("proxy-chains.row.add-node")
                    }
                }
            } else if !editableInventory.isEmpty {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                if chainedProxies.isEmpty {
                    Section {
                        chainRows
                    } header: {
#if !os(macOS)
                         
                         
                         
                         
                        chainsHeader
#endif
                    }
                    Section {
                        addChainRow
                    }
                } else {
                    Section {
                        chainRows
                        addChainRow
                    } header: {
                        chainsHeader
                    }
                }
            }

            if !relayAssessments.isEmpty {
                Section {
                    ForEach(relayAssessments) { relay in
                        legacyRelayRow(relay)
                    }
                } header: {
                    Text("Legacy Relay Groups")
                } footer: {
                    legacyRelayFooter
                }
            }

            if !orphanAssignments.isEmpty {
                Section {
                    ForEach(orphanAssignments, id: \.proxy) { assignment in
                        Button {
                            migrating = OrphanTarget(id: assignment.proxy)
                        } label: {
                            ClashDestinationRow(
                                title: .verbatim(assignment.proxy),
                                subtitle: "Proxy identity is missing · tap to migrate or remove",
                                symbol: .exclamationmarkTriangle,
                                tint: .orange
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "proxy-chain.orphan.\(assignment.proxy)"
                        )
                    }
                } header: {
                    Text("Needs Attention")
                } footer: {
                    Text("A profile URL update or source edit renamed/deleted these proxies. Migrate the identity or remove its override before saving.")
                }
            }

            if !validationMessage.isEmpty {
                Section {
                    ClashStatusMessage(text: .copy(validationMessage), kind: .error)
                }
            }

            if !saveError.isEmpty {
                Section {
                    ClashStatusMessage(text: .copy(saveError), kind: .error)
                }
            }

        }
        .clashInsetGroupedListStyle()
        .clashPageTitle("Proxy Chains")
        .clashDetailPageInsets()
        .clashProductModalChild(title: "Proxy Chains")
        .task(id: ValidationKey(
            spec: spec,
            payloadEdits: payloadEdits,
            legacyRelayMigrations: legacyRelayMigrations
        )) {
            await refreshDerivedState()
        }
        .clashProductModal(
            isPresented: $addingChain,
            role: .form,
            macOSPanelRole: .page
        ) {
            ChainBuilder(proxies: editableInventory) { entry, exitNode in
                addChain(entry: entry, exit: exitNode)
            }
            .clashModalPresentation(.form)
        }
        .clashProductModal(item: $editing, role: .page) { proxy in
            ProxyDialerEditor(proxy: proxy, inventory: overlaidInventory, spec: spec) { dialerProxy in
                if proxy.kind == .payloadProxy {
                    guard let provider = proxy.provider else {
                        throw ProfileProviderDefinitionError.missingDefinition
                    }
                    var edits = payloadEdits.filter { $0.node != proxy.name }
                    let sourceRow = inventory.first { $0.name == proxy.name }
                    if dialerProxy != sourceRow?.dialerProxy {
                        edits.append(ProxyPayloadDialerEdit(
                            provider: provider,
                            node: proxy.name,
                            dialerProxy: dialerProxy
                        ))
                    }
                    var probe = overlaidInventory
                    if let index = probe.firstIndex(where: { $0.name == proxy.name }) {
                        probe[index] = ProxyIdentity(
                            name: proxy.name,
                            type: proxy.type,
                            dialerProxy: dialerProxy,
                            kind: .payloadProxy,
                            members: proxy.members,
                            provider: provider
                        )
                    }
                    try spec.validate(in: probe)
                    payloadEdits = edits
                } else {
                    var draft = spec
                    if dialerProxy == proxy.dialerProxy {
                        draft.removeAssignment(for: proxy.name)
                    } else {
                        draft.setDialerProxy(dialerProxy, for: proxy.name)
                    }
                    try draft.validate(in: overlaidInventory)
                    spec = draft
                }
            }
            .clashModalPresentation(.page)
        }
        .clashProductModal(item: $migrating, role: .form) { target in
            ProxyIdentityMigrationView(
                oldName: target.id,
                candidates: inventory.map(\.name)
            ) { newName in
                var draft = spec
                try draft.renameProxy(from: target.id, to: newName)
                try draft.validate(in: inventory)
                spec = draft
            } remove: {
                spec.removeAssignment(for: target.id)
            }
            .clashModalPresentation(.form)
        }
         
         
        .alert(
            "Enable TCP-only migration?",
            isPresented: Binding(
                get: { confirmingRelay != nil },
                set: { if !$0 { confirmingRelay = nil } }
            ),
            presenting: confirmingRelay
        ) { relay in
            Button("Enable") { setConfirmed(relay) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("UDP is not available on this chain.")
        }
        .alert(
            "Remove TCP-only migration?",
            isPresented: Binding(
                get: { confirmingRelayRemoval != nil },
                set: { if !$0 { confirmingRelayRemoval = nil } }
            ),
            presenting: confirmingRelayRemoval
        ) { relay in
            Button("Remove", role: .destructive) {
                legacyRelayMigrations.removeAll {
                    $0.groupName == relay.groupName
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This profile will stop before connection until this legacy relay is reviewed again. The downloaded source stays unchanged.")
        }
    }

    private var orphanAssignments: [ProxyDialerAssignment] {
        let names = Set(inventory.map(\.name))
        return spec.assignments.filter { !names.contains($0.proxy) }
    }

     
     
    private var overlaidInventory: [ProxyIdentity] {
        ProfileProxyChainDerivedState.overlay(
            inventory: inventory,
            payloadEdits: payloadEdits
        )
    }

    private var editableInventory: [ProxyIdentity] {
        overlaidInventory.filter(\.supportsChainEditing)
    }

     
     
     
    @ViewBuilder
    private var chainRows: some View {
        if chainedProxies.isEmpty {
            ClashEmptyState(
                title: "No Proxy Chains",
                message: "",
                symbol: .link
            )
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("proxy-chain.empty")
        } else {
            ForEach(chainedProxies) { proxy in
                ClashMacDeletableRow(onDelete: {
                    if let index = chainedProxies.firstIndex(
                        where: { $0.id == proxy.id }
                    ) {
                        removeChains(at: IndexSet(integer: index))
                    }
                }) {
                    chainRow(proxy)
                }
            }
            .onDelete(perform: removeChains)
        }
    }

     
     
     
     
    private func removeChains(at offsets: IndexSet) {
        let names = offsets.map { chainedProxies[$0].name }
        var draft = spec
        var edits = payloadEdits
        for name in names {
            if let proxy = chainedProxies.first(where: { $0.name == name }),
               proxy.kind == .payloadProxy, let provider = proxy.provider {
                edits.removeAll { $0.node == name }
                edits.append(ProxyPayloadDialerEdit(
                    provider: provider, node: name, dialerProxy: nil
                ))
            } else {
                let sourceDialerProxy = inventory.first {
                    $0.name == name
                }?.dialerProxy
                draft.clearDialerOverride(
                    for: name,
                    sourceDialerProxy: sourceDialerProxy
                )
            }
        }
        do {
            try draft.validate(in: overlaidInventory)
            spec = draft
            payloadEdits = edits
            validationMessage = ""
        } catch {
            validationMessage = error.localizedDescription
        }
    }

     
     
     
     
     
     
     
     
    @ViewBuilder
    private func chainRow(_ proxy: ProxyIdentity) -> some View {
        let hops: [String] = {
            guard let path = try? spec.orderedPath(
                startingAt: proxy.name, in: overlaidInventory
            ) else { return [] }
            return Array(path.reversed())
        }()
        if let error = pathError(for: proxy) {
            Button {
                editing = proxy
            } label: {
                ClashStatusMessage(
                    text: .copy(error.localizedDescription), kind: .error
                )
            }
            .buttonStyle(.borderless)
            .contentShape(Rectangle())
            .accessibilityIdentifier("proxy-chain.proxy.\(proxy.name)")
        } else {
            HStack(alignment: .center, spacing: ClashTheme.Spacing.compact) {
                Button {
                    editing = proxy
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(hops.enumerated()), id: \.offset) {
                            index, hop in
                            hopLine(
                                hop,
                                role: index == 0
                                    ? "Entry"
                                    : (index == hops.count - 1
                                        ? "Exit" : "Hop"),
                                isLast: index == hops.count - 1
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .contentShape(Rectangle())
                .accessibilityIdentifier("proxy-chain.proxy.\(proxy.name)")

                Button {
                    Task { await measureChain(hops) }
                } label: {
                    Group {
                        if measuring.isDisjoint(with: hops) {
                            Image(
                                systemName: ClashSymbol
                                    .boltHorizontalCircle.rawValue
                            )
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .frame(
                        width: 32,
                        height: ClashClientUI.ClashTheme.Control.minimumHitTarget
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(measure == nil || !measuring.isDisjoint(with: hops))
                .accessibilityLabel("Test Chain")
                .accessibilityIdentifier("proxy-chain.test.\(proxy.name)")
            }
        }
    }

     
     
    @ViewBuilder
    private func hopLine(
        _ name: String, role: String, isLast: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(clash: .copy(role))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)
                 
                Text(clash: .verbatim(name))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                 
                Text(clash: .verbatim(
                    overlaidInventory.first { $0.name == name }?.type ?? ""
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                delayText(for: name)
            }
            if !isLast {
                 
                 
                 
                Image(systemName: ClashSymbol.arrowDown.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .center)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("proxy-chain.hop.\(name)")
    }

    @ViewBuilder
    private func delayText(for name: String) -> some View {
        if measuring.contains(name) {
            ProgressView().controlSize(.mini)
        } else if let delay = delays[name] {
             
             
             
             
            Text(clash: delay > 0
                ? .verbatim("\(delay) ms")
                : .copy(ClashProbeFailureCopy.neutralBadge))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(delay > 0 ? Color.secondary : Color.red)
        }
    }

     
     
    @ViewBuilder
    private var chainsHeader: some View {
                     
                     
                     
                     
                    HStack {
#if !os(macOS)
                         
                         
                        Text("Proxy Chains")
#endif
                        Spacer()
                        if !chainedProxies.isEmpty {
                            Button {
                                Task { await measureEveryChain() }
                            } label: {
                                Group {
                                    if measuring.isEmpty {
                                        Image(
                                            systemName: ClashSymbol
                                                .boltHorizontalCircle.rawValue
                                        )
                                    } else {
                                        ProgressView().controlSize(.small)
                                    }
                                }
                                 
                                 
                                 
                                 
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(
                                    width: ClashClientUI.ClashTheme.Control
                                        .minimumHitTarget,
                                    height: 28
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(measure == nil || !measuring.isEmpty)
                            .accessibilityLabel("Test All Chains")
                            .accessibilityHint(
                                measure == nil
                                    ? "Connect before testing latency"
                                    : "Measures every chain"
                            )
                            .accessibilityIdentifier("proxy-chain.test-all")
                        }
                    }
    }

     
     
     
    @MainActor
    private func measureEveryChain() async {
        for proxy in chainedProxies {
            let hops: [String] = {
                guard let path = try? spec.orderedPath(
                    startingAt: proxy.name, in: overlaidInventory
                ) else { return [] }
                return Array(path.reversed())
            }()
            await measureChain(hops)
        }
    }

     
     
     
     
     
     
    @MainActor
    private func measureChain(_ hops: [String]) async {
        guard let measure else { return }
        for hop in hops {
            measuring.insert(hop)
        }
        for hop in hops {
            let delay = await measure(hop)
            delays[hop] = delay ?? 0
            measuring.remove(hop)
        }
    }

     
     
     
    @ViewBuilder
    private var addChainRow: some View {
        ClashAddRow(Text(ClashCopy.key("Add Proxy Chain"))) {
            addingChain = true
        } touchLabel: {
            Label(
                ClashCopy.key("Add Proxy Chain"),
                systemImage: ClashSymbol.plus.name
            )
        }
        .disabled(editableInventory.count < 2)
        .accessibilityIdentifier("proxy-chain.add")
    }

     
     
     
     
    private func addChain(entry: String, exit exitNode: String) {
        guard let exit = overlaidInventory.first(where: {
            $0.name == exitNode
        }) else {
            validationMessage = "The selected exit is no longer available."
            addingChain = false
            return
        }

        if exit.kind == .payloadProxy {
            guard let provider = exit.provider else {
                validationMessage = ProfileProviderDefinitionError
                    .missingDefinition.localizedDescription
                addingChain = false
                return
            }
            var edits = payloadEdits.filter { $0.node != exitNode }
            let sourceRow = inventory.first { $0.name == exitNode }
            if entry != sourceRow?.dialerProxy {
                edits.append(
                    ProxyPayloadDialerEdit(
                        provider: provider,
                        node: exitNode,
                        dialerProxy: entry
                    )
                )
            }
            var probe = overlaidInventory
            if let index = probe.firstIndex(where: {
                $0.name == exitNode
            }) {
                probe[index] = ProxyIdentity(
                    name: exit.name,
                    type: exit.type,
                    dialerProxy: entry,
                    kind: exit.kind,
                    members: exit.members,
                    provider: provider
                )
            }
            do {
                try spec.validate(in: probe)
                payloadEdits = edits
                validationMessage = ""
                addingChain = false
            } catch {
                validationMessage = error.localizedDescription
                addingChain = false
            }
            return
        }

        var draft = spec
        draft.setDialerProxy(entry, for: exitNode)
        do {
            try draft.validate(in: overlaidInventory)
            spec = draft
            validationMessage = ""
            addingChain = false
        } catch {
            validationMessage = error.localizedDescription
            addingChain = false
        }
    }

     
     
    private var chainedProxies: [ProxyIdentity] {
        editableInventory.filter { proxy in
            let assigned = spec.assignment(for: proxy.name)?.dialerProxy
            let pending = payloadEdits.first { $0.node == proxy.name }
            if let pending { return pending.dialerProxy?.isEmpty == false }
            if let assigned { return !assigned.isEmpty }
            return proxy.dialerProxy?.isEmpty == false
        }
    }

     
     
    private var unchainedProxies: [ProxyIdentity] {
        let chained = Set(chainedProxies.map(\.name))
        return editableInventory.filter { !chained.contains($0.name) }
    }

    private func isConfirmed(_ relay: LegacyRelayAssessment) -> Bool {
        legacyRelayMigrations.contains {
            $0.groupName == relay.groupName && $0.members == relay.members
        }
    }

    private func setConfirmed(_ relay: LegacyRelayAssessment) {
        guard relay.blocker == nil else { return }
        legacyRelayMigrations.removeAll { $0.groupName == relay.groupName }
        legacyRelayMigrations.append(
            LegacyRelayMigration(
                groupName: relay.groupName,
                members: relay.members
            )
        )
    }

    private func pathDescription(for proxy: ProxyIdentity) -> ClashDisplayText {
        if let error = pathError(for: proxy) {
            return .copy(error.localizedDescription)
        }
        let path = (try? spec.orderedPath(startingAt: proxy.name, in: overlaidInventory)) ?? [proxy.name]
        if path.count == 1 {
             
            return .format("Direct connection · %@", [proxy.type])
        }
         
         
         
         
         
         
        return .verbatim(path.reversed().joined(separator: " → "))
    }

    private func pathError(for proxy: ProxyIdentity) -> Error? {
        do {
            _ = try spec.orderedPath(startingAt: proxy.name, in: overlaidInventory)
            return nil
        } catch {
            return error
        }
    }

    @MainActor
    private func refreshDerivedState() async {
        let key = ValidationKey(
            spec: spec,
            payloadEdits: payloadEdits,
            legacyRelayMigrations: legacyRelayMigrations
        )
        guard key != validatedKey else { return }
         
        do {
            try await Task.sleep(nanoseconds: 80_000_000)
        } catch {
            return
        }
        let yaml = baseYAML
        let error = baseError
        let inventory = inventory
        let began = DispatchTime.now().uptimeNanoseconds
        let derived = await Task.detached(priority: .userInitiated) {
            ProfileProxyChainDerivedState.evaluate(
                baseYAML: yaml,
                baseError: error,
                inventory: inventory,
                spec: key.spec,
                payloadEdits: key.payloadEdits,
                legacyRelayMigrations: key.legacyRelayMigrations
            )
        }.value
        guard !Task.isCancelled,
              key == ValidationKey(
                  spec: spec,
                  payloadEdits: payloadEdits,
                  legacyRelayMigrations: legacyRelayMigrations
              ) else { return }
        relayAssessments = derived.relayAssessments
        validationMessage = derived.validationMessage
        validatedKey = key
        ClashPerf.span(
            "chains.validate",
            milliseconds: Double(
                DispatchTime.now().uptimeNanoseconds - began
            ) / 1_000_000,
            detail: "relays=\(derived.relayAssessments.count)"
        )
    }

}

 
 
 
 
 
 
 
 
 
 
private struct ChainBuilder: View {
    let proxies: [ProxyIdentity]
    let create: (_ entry: String, _ exit: String) -> Void

     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @State private var entry = ""
    @State private var exitNode = ""

    private var isComplete: Bool {
        !entry.isEmpty && !exitNode.isEmpty && entry != exitNode
    }

     
     
     
     
     
     
    private var blockingRequirement: String? {
        guard !isComplete else { return nil }
        if entry.isEmpty { return "Choose the node this chain enters through." }
        if exitNode.isEmpty { return "Choose the node this chain leaves from." }
        return "A chain needs two different nodes."
    }

    var body: some View {
        ClashFeatureNavigationContainer {
            Form {
                Section {
                    ChainEndRow(
                        label: "Entry",
                        selection: $entry,
                        proxies: proxies,
                        excluding: exitNode,
                        allowsNone: false
                    )
                    .accessibilityIdentifier("proxy-chain.builder.entry")
                }

                Section {
                    ChainEndRow(
                        label: "Exit",
                        selection: $exitNode,
                        proxies: proxies,
                        excluding: entry,
                        allowsNone: false
                    )
                    .accessibilityIdentifier("proxy-chain.builder.exit")
                }

                 
                 
                 
                 
            }
            .clashPageTitle("New Chain")
            .clashDetailPageInsets()
            .clashProductModalRoot(title: "New Chain")
#if !os(macOS)
             
             
             
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismissPresentation() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { commit() }
                        .disabled(!isComplete)
                        .accessibilityIdentifier("proxy-chain.builder.add")
                }
            }
#endif
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if ClashPlatformLayout.modalEditorUsesGroupedForm {
                    ClashModalActionBar(
                        primaryTitle: "Add",
                        primaryDisabled: !isComplete,
                        primaryHint: blockingRequirement,
                        onPrimary: { commit() }
                    )
                }
            }
        }
        .clashStackNavigationViewStyle()
        .accessibilityIdentifier("proxy-chain.builder")
        .clashCapturesDismiss(dismiss)
    }

    private func commit() {
        create(entry, exitNode)
        dismissPresentation()
    }

    private func dismissPresentation() {
        dismiss.closeModalOrDismiss()
    }
}

 
 
 
 
 
 
 
 
private struct ChainEndRow: View {
    let label: String
    @Binding var selection: String
    let proxies: [ProxyIdentity]
     
     
    let excluding: String
    let allowsNone: Bool

    var body: some View {
        ClashRoutedViewLink {
            ChainEndPicker(
                title: label,
                selection: $selection,
                proxies: proxies.filter { $0.name != excluding },
                allowsNone: allowsNone
            )
            .accessibilityIdentifier("profile.override.chain-end")
        } label: {
            HStack {
                Text(clash: .copy(label))
                Spacer(minLength: ClashTheme.Spacing.compact)
                Text(clash: selection.isEmpty
                    ? .copy(allowsNone ? "No Entry" : "Choose")
                    : .verbatim(selection))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

private struct ChainEndPicker: View {
    let title: String
    @Binding var selection: String
    let proxies: [ProxyIdentity]
    let allowsNone: Bool

     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.clashPopRoute) private var popRoute
    @State private var query = ""

    private var shown: [ProxyIdentity] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return proxies }
        return proxies.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        Form {
            if allowsNone {
                Button {
                    selection = ""
                    dismissRoute()
                } label: {
                    HStack {
                        Text("No Entry")
                        Spacer()
                        if selection.isEmpty {
                            Image(systemName: ClashSymbol.checkmark.rawValue)
                                .foregroundStyle(.tint)
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: ClashClientUI.ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform,
                        alignment: .leading
                    )
                    .contentShape(Rectangle())
                }
                .clashSelectionRowStyle()
                .accessibilityIdentifier("proxy-chain.end.none")
            }
            ForEach(shown) { proxy in
                Button {
                    selection = proxy.name
                    dismissRoute()
                } label: {
                    HStack {
                         
                        Text(clash: .verbatim(proxy.name))
                            .lineLimit(2)
                        Spacer(minLength: ClashTheme.Spacing.compact)
                        if selection == proxy.name {
                            Image(systemName: ClashSymbol.checkmark.rawValue)
                                .foregroundStyle(.tint)
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: ClashClientUI.ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform,
                        alignment: .leading
                    )
                    .contentShape(Rectangle())
                }
                .clashSelectionRowStyle()
                .accessibilityIdentifier("proxy-chain.end.\(proxy.name)")
            }
        }
        .clashProductModalSearchable(text: $query)
        .clashPageTitle(.copy(title))
        .clashDetailPageInsets()
        .clashProductModalChild(
            title: .copy(title),
            searchText: $query
        )
        .clashCapturesDismiss(dismiss)
    }

    private func dismissRoute() {
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

private struct ProxyDialerEditor: View {
    let proxy: ProxyIdentity
    let inventory: [ProxyIdentity]
    let spec: ProxyChainSpec
    let save: (String?) throws -> Void

     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
    @State private var selection: String
    @State private var error = ""
     
     
     
     
    private var openedWith: String {
        Self.effectiveDialer(proxy: proxy, spec: spec)
    }

    private static func effectiveDialer(
        proxy: ProxyIdentity,
        spec: ProxyChainSpec
    ) -> String {
        let effective: String?
        if let assignment = spec.assignment(for: proxy.name) {
            effective = assignment.dialerProxy
        } else {
            effective = proxy.dialerProxy
        }
        return effective ?? Self.noDialer
    }


    private static let noDialer = "__clash_no_dialer_proxy__"

    init(
        proxy: ProxyIdentity,
        inventory: [ProxyIdentity],
        spec: ProxyChainSpec,
        save: @escaping (String?) throws -> Void
    ) {
        self.proxy = proxy
        self.inventory = inventory
        self.spec = spec
        self.save = save
         
         
         
        _selection = State(
            initialValue: Self.effectiveDialer(proxy: proxy, spec: spec)
        )
    }

     
     
     
     
     
     
     
    var body: some View {
        ClashFeatureNavigationContainer {
            Form {
                Section {
                     
                     
                     
                     
                    ChainEndRow(
                        label: "Entry",
                        selection: Binding(
                            get: { selection == Self.noDialer ? "" : selection },
                            set: { selection = $0.isEmpty ? Self.noDialer : $0 }
                        ),
                        proxies: candidates,
                        excluding: proxy.name,
                        allowsNone: true
                    )
                    .accessibilityIdentifier("proxy-chain.dialer-picker")
                }

                Section {
                     
                    keyValue("Exit", proxy.name)
                }

                if case .failure(let pathError) = previewedPath {
                    Section {
                        ClashStatusMessage(
                            text: .copy(pathError.localizedDescription),
                            kind: .error
                        )
                    }
                }

                if !error.isEmpty {
                    ClashStatusMessage(text: .copy(error), kind: .error)
                }
            }
            .clashPageTitle("Edit Chain")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !insideProductModal {
                        Button("Cancel") { dismissPresentation() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !insideProductModal {
                         
                         
                        ClashSaveButton(.copy("Done"), isEnabled: selection != openedWith) { persist() }
                            .accessibilityIdentifier("proxy-chain.hop.save")
                    }
                }
            }
            .clashProductModalRoot(title: "Edit Chain")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if insideProductModal {
                     
                     
                     
                    ClashModalActionBar(
                        primaryTitle: "Done",
                        primaryDisabled: selection == openedWith,
                        onPrimary: persist
                    )
                }
            }
        }
        .clashStackNavigationViewStyle()
        .clashCapturesDismiss(dismiss)
    }

     
     
     
    private var candidates: [ProxyIdentity] {
        inventory.filter { candidate in
            guard candidate.name != proxy.name,
                  candidate.kind != .payloadProxy else { return false }
            return !wouldCycle(through: candidate.name)
        }
    }

    private func wouldCycle(through hop: String) -> Bool {
        var probe = inventory
        var probeSpec = spec
        if proxy.kind == .payloadProxy {
            if let index = probe.firstIndex(where: { $0.name == proxy.name }) {
                probe[index] = ProxyIdentity(
                    name: proxy.name,
                    type: proxy.type,
                    dialerProxy: hop,
                    kind: .payloadProxy,
                    members: proxy.members,
                    provider: proxy.provider
                )
            }
        } else {
            probeSpec.setDialerProxy(hop, for: proxy.name)
        }
        do {
            try probeSpec.validate(in: probe)
            return false
        } catch {
            return true
        }
    }

    private var selectedDialerProxy: String? {
        selection == Self.noDialer ? nil : selection
    }

     
     
     
     
    private var previewedPath: Result<[ProxyIdentity], Error> {
        var probeSpec = spec
        var probe = inventory
        if proxy.kind == .payloadProxy {
            if let index = probe.firstIndex(where: { $0.name == proxy.name }) {
                probe[index] = ProxyIdentity(
                    name: proxy.name,
                    type: proxy.type,
                    dialerProxy: selectedDialerProxy,
                    kind: .payloadProxy,
                    members: proxy.members,
                    provider: proxy.provider
                )
            }
        } else if selectedDialerProxy == proxy.dialerProxy {
            probeSpec.removeAssignment(for: proxy.name)
        } else {
            probeSpec.setDialerProxy(selectedDialerProxy, for: proxy.name)
        }
        do {
             
             
             
             
            let names = try probeSpec
                .orderedPath(startingAt: proxy.name, in: probe)
                .reversed()
            return .success(names.map { name in
                probe.first { $0.name == name } ?? ProxyIdentity(
                    name: name, type: "unknown", dialerProxy: nil, kind: .builtin
                )
            })
        } catch {
            return .failure(error)
        }
    }

    private func chainHopCard(_ hop: ProxyIdentity) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hop.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(hop.type)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, ClashTheme.Spacing.row)
        .padding(.vertical, ClashTheme.Spacing.compact)
        .background(
            RoundedRectangle(cornerRadius: ClashTheme.Radius.control, style: .continuous)
                .fill(ClashTheme.raisedFill)
        )
    }

    private func persist() {
        do {
            try save(selectedDialerProxy)
            dismissPresentation()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func dismissPresentation() {
        dismiss.closeModalOrDismiss()
    }

     
     
     
     
     
    private func keyValue(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(clash: .copy(key)).foregroundStyle(.secondary)
            Spacer(minLength: ClashTheme.Spacing.standard)
            Text(clash: .verbatim(value)).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ProxyIdentityMigrationView: View {
    let oldName: String
    let candidates: [String]
    let migrate: (String) throws -> Void
    let remove: () -> Void

     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
    @State private var selection: String
    @State private var error = ""

    init(
        oldName: String,
        candidates: [String],
        migrate: @escaping (String) throws -> Void,
        remove: @escaping () -> Void
    ) {
        self.oldName = oldName
        self.candidates = candidates
        self.migrate = migrate
        self.remove = remove
        _selection = State(initialValue: candidates.first ?? "")
    }

    var body: some View {
        ClashFeatureNavigationContainer {
            Form {
                Section {
                    ClashStatusMessage(
                        text: .format("Proxy \"%@\" no longer exists in the generated configuration.", [oldName]),
                        kind: .warning
                    )
                }

                if !candidates.isEmpty {
                    Section("Migrate Identity") {
                        Picker("New proxy", selection: $selection) {
                            ForEach(candidates, id: \.self) { Text($0).tag($0) }
                        }
                        .accessibilityIdentifier(
                            "proxy-chain.orphan.destination"
                        )
                    }
                }

                Section {
                    Button("Remove Chain Override", role: .destructive) {
                        remove()
                        dismissPresentation()
                    }
                    .accessibilityIdentifier("proxy-chain.orphan.remove")
                }

                if !error.isEmpty {
                    ClashStatusMessage(text: .copy(error), kind: .error)
                }
            }
            .clashPageTitle("Migrate Proxy")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !insideProductModal {
                        Button("Cancel") { dismissPresentation() }
                            .accessibilityIdentifier("proxy-chain.orphan.cancel")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !insideProductModal {
                        Button("Migrate") {
                            persistMigration()
                        }
                        .disabled(selection.isEmpty)
                        .accessibilityIdentifier("proxy-chain.orphan.migrate")
                    }
                }
            }
            .clashProductModalRoot(title: "Migrate Proxy")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if insideProductModal {
                    ClashModalActionBar(
                        primaryTitle: "Migrate",
                        primaryDisabled: selection.isEmpty,
                        onPrimary: persistMigration
                    )
                }
            }
        }
        .clashStackNavigationViewStyle()
        .clashCapturesDismiss(dismiss)
    }

    private func dismissPresentation() {
        dismiss.closeModalOrDismiss()
    }

    private func persistMigration() {
        do {
            try migrate(selection)
            dismissPresentation()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

 
 
 
enum ProfileOverrideModePolicy {
    static func mode(stored: Profile.OverwriteMode, selectedScriptID: String?) -> Profile.OverwriteMode {
        if stored == .custom { return .custom }
        return selectedScriptID == nil ? .standard : .script
    }
}
