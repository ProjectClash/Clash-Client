import ClashClientKit
import ClashClientUI
import SwiftUI
import UniformTypeIdentifiers

 
 
 
 
 
 
 
@MainActor
func clashLogConfigurationWriteFailure(_ error: Error) {
    let note = ConfigurationLibraryDiagnostics.lastIdentifierNote ?? "-"
    ClashLogStore.shared.append(
        "configuration centre write failed: \(error.localizedDescription) [\(note)]",
        stream: .app, level: .warning)
}

struct ConfigurationCreationAdapter: View {
    @Environment(\.locale) private var locale
    @Environment(\.clashShellLayout) private var shellLayout
    @ObservedObject var model: ProfilesViewModel
     
     
     
     
     
    var changed: ((ConfigurationLibrarySnapshot) -> Void)? = nil
    var editingProfileID: String? = nil
    var editingStep: ConfigurationCreationDraft.Step? = nil

     
     
    struct FirstStepImport: Equatable {
        var kind: ClashConfigurationSourceKind
        var isOriginal: Bool
    }

    @State private var draft = ConfigurationCreationDraft()
    @State private var library = ConfigurationLibrarySnapshot()
    @State private var baseline = ConfigurationCreationDraft()
    @State private var inspectedSourceID: String?
    @State private var creationID = UUID().uuidString.lowercased()
    @State private var legacyPayloads: [String: ConfigurationSourcePayload] = [:]
    @State private var ready = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var importKind: ClashConfigurationSourceKind?
     
     
     
     
     
     
    @State private var firstStepImport: FirstStepImport?
     
     
    @State private var showsSourceLibrary = false
    @State private var showsRuleLibrary = false
    @StateObject private var dismiss = ClashDismissHandle()

    var body: some View {
        ClashFeatureNavigationContainer {
            creationContent
            .clashCapturesDismiss(dismiss)
            .task { await loadLibrary() }
            .clashProductModal(isPresented: Binding(get: { inspectedSourceID != nil },
                set: { if !$0 { inspectedSourceID = nil } }), role: .page) {
                if let id = inspectedSourceID, let source = draft.sources(in: library).first(where: { $0.id == id }) {
                    ConfigurationNodeScopeAdapter(model: model, source: source,
                        staged: draft.newSources.first { $0.record.id == id }, initial: draft.nodeScopes?[id],
                        save: { scope in
                            var scopes = draft.nodeScopes ?? [:]
                            scopes[id] = scope?.isEmpty == true ? nil : scope
                            draft.nodeScopes = scopes.isEmpty ? nil : scopes
                            if scope?.isEmpty == true { draft.selectedSourceIDs.removeAll { $0 == id } }
                            else if !draft.selectedSourceIDs.contains(id) { draft.selectedSourceIDs.append(id) }
                            inspectedSourceID = nil
                        }, close: { inspectedSourceID = nil })
                } else {
                    ClashOpeningCancelButton()
                }
            }
            .clashProductModal(item: $importKind, role: .page) { kind in
                ConfigurationSourceImportAdapter(model: model, kind: kind, choosesKind: true,
                    finishImport: { importKind = nil }) { payload in
                        try Self.acceptImportedSource(payload, into: &draft, isEditing: editingProfileID != nil)
                    }
            }
            .clashProductModal(isPresented: $showsSourceLibrary, role: .page) {
                 
                ConfigurationSourceLibraryAdapter(model: model, library: library,
                    changed: { if ConfigurationCollectionListing.takes($0, over: library) { applyLibrary($0) } },
                    close: { showsSourceLibrary = false })
            }
            .clashProductModal(isPresented: $showsRuleLibrary, role: .page) {
                ConfigurationRuleLibraryAdapter(model: model, library: library,
                    changed: applyLibrary, close: { showsRuleLibrary = false })
            }
        }
    }

    @ViewBuilder
    private var creationContent: some View {
        if ready && (firstStepImport != nil || draft.needsInitialNodeImport(in: library,
            hasLegacyNodes: legacyPayloads.values.contains { $0.record.nodeCount > 0 || $0.record.providerCount > 0 },
            isEditing: editingProfileID != nil)) {
             
             
            ConfigurationSourceImportAdapter(model: model, kind: firstStepImport?.kind ?? .subscription, choosesKind: true,
                isFirstConfigurationStep: true, finishImport: {
                    if firstStepImport != nil { firstStepImport = nil }
                    else { close() }
                }) { payload in
                     
                     
                    let (routed, resolvesItself) = await Task.detached(priority: .userInitiated) {
                        payload.routing
                    }.value
                    try Self.applyFirstStepImport(payload, into: &draft, request: firstStepImport,
                                                  suppliesOwnRouting: routed, resolvesItsNodesItself: resolvesItself)
                    firstStepImport = nil
                }
        } else {
            ClashConfigurationCreationView(draft:$draft,library:library,
                palette: .clashProduct, presentationClass: shellLayout == .regularSidebar ? .regularTouch : .compactTouch,
                icon: { AnyView(ClashSymbolImage(symbol: $0)) },
                legacy: model.profiles.compactMap { profile in
                    guard let payload = legacyPayloads[profile.id] else { return nil }
                    return .init(id: profile.id, label: profile.label, nodeCount: payload.record.nodeCount,
                        providerCount: payload.record.providerCount)
                },
                isBusy:busy,isReady:ready,error:errorMessage,
                reload: { Task { await loadLibrary() } },
                addSource: { kind in
                    if editingProfileID == nil { firstStepImport = .init(kind: kind, isOriginal: false) }
                    else { importKind = kind }
                },
                selectLegacy: { id in
                    if let payload = legacyPayloads[id] { accept(payload) }
                },
                finish:finish,
                cancel:close, isEditing: editingProfileID != nil, editingProfileID: editingProfileID, baseline: baseline, editingStep: editingStep,
                sourceDetails: { inspectedSourceID = $0 },
                manageSources: { showsSourceLibrary = true },
                manageRules: { showsRuleLibrary = true },
                completionNodes: { value in AnyView(completionContents(draft: value, nodes: true)) },
                completionRules: { value in AnyView(completionContents(draft: value, nodes: false)) })
        }
    }

    private func completionContents(draft: ConfigurationCreationDraft, nodes: Bool) -> some View {
        ConfigurationCompletionContentsAdapter(draft: draft, library: model.configurationLibraryStore,
            generation: library.generation, nodes: nodes)
    }

    private func loadLibrary() async {
        guard !ready, !busy else { return }
        errorMessage = nil
        busy = true
        defer { busy = false }
        do {
            try await model.recoverConfigurationPublications()
            do { try await model.registerLegacyConfigurationSources() }
            catch { errorMessage = ClashErrorCopy.message(error, locale: locale) }
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            library = try await Task.detached { try store.snapshot() }.value
            if editingProfileID == nil, draft.selectedRuleID == nil {
                draft.selectedRuleID = ConfigurationBuiltins.basicRuleID
            }
            if let id = editingProfileID {
                if let recipe = library.recipes.first(where: { $0.id == id }) {
                    let fallbackRule = library.rules.contains { $0.id == recipe.ruleSchemeID } || ConfigurationBuiltins.schemes.contains { $0.id == recipe.ruleSchemeID }
                    draft = Self.editingDraft(recipe: recipe, label: model.profiles.first(where: { $0.id == id })?.label ?? recipe.label,
                        selectedRuleID: fallbackRule ? recipe.ruleSchemeID : ConfigurationBuiltins.basicRuleID)
                } else {
                     
                     
                    let source = try await model.configurationSourceFromLegacy(id)
                    accept(source)
                    draft.selectedRuleID = source.record.hasRules ? "rules-" + source.record.id : ConfigurationBuiltins.basicRuleID
                     
                     
                    draft.label = source.record.displayLabel(locale: locale)
                    draft.dnsMode = .source
                }
                draft.connectAfterCreation = false
                draft.step = editingStep ?? .sources
            }
             
             
             
            legacyPayloads = try await model.configurationLegacyNodeSources(in: library)
             
             
            baseline = draft
            ready = true
        } catch { errorMessage = ClashErrorCopy.message(error, locale: locale) }
    }

    private func applyLibrary(_ updated: ConfigurationLibrarySnapshot) {
        let removedSources = Set(library.sources.map(\.id)).subtracting(updated.sources.map(\.id))
        let removedRules = Set(library.rules.map(\.id)).subtracting(updated.rules.map(\.id))
        draft.selectedSourceIDs.removeAll { removedSources.contains($0) }
        baseline.selectedSourceIDs.removeAll { removedSources.contains($0) }
        if let selected = draft.selectedRuleID, removedRules.contains(selected) { draft.selectedRuleID = ConfigurationBuiltins.basicRuleID }
        if let selected = baseline.selectedRuleID, removedRules.contains(selected) { baseline.selectedRuleID = ConfigurationBuiltins.basicRuleID }
         
         
         
         
         
         
        if let id = editingProfileID, draft.selectedRuleID == baseline.selectedRuleID,
           let current = updated.recipes.first(where: { $0.id == id })?.ruleSchemeID, current != draft.selectedRuleID,
           updated.rules.contains(where: { $0.id == current }) || ConfigurationBuiltins.schemes.contains(where: { $0.id == current }) {
            draft.selectedRuleID = current
            baseline.selectedRuleID = current
        }
        library = updated
    }

     
     
     
     
     
     
     
     
     
     
     
     
    static func applyFirstStepImport(_ payload: ConfigurationSourcePayload,
                                     into draft: inout ConfigurationCreationDraft,
                                     request: FirstStepImport?,
                                     suppliesOwnRouting: Bool? = nil,
                                     resolvesItsNodesItself: Bool? = nil) throws {
        if request?.isOriginal == true { draft.useOriginal(payload) }
        else {
            try acceptImportedSource(payload, into: &draft, isEditing: false,
                                     suppliesOwnRouting: suppliesOwnRouting,
                                     resolvesItsNodesItself: resolvesItsNodesItself)
        }
    }

    static func acceptImportedSource(_ payload: ConfigurationSourcePayload,
                                     into draft: inout ConfigurationCreationDraft, isEditing: Bool,
                                     suppliesOwnRouting: Bool? = nil,
                                     resolvesItsNodesItself: Bool? = nil) throws {
        if isEditing { draft.add(payload, rule: nil) }
         
         
        else {
            try draft.acceptNewImport(payload, suppliesOwnRouting: suppliesOwnRouting,
                                      resolvesItsNodesItself: resolvesItsNodesItself)
        }
    }

    private func accept(_ payload: ConfigurationSourcePayload) {
        let hasRules = payload.record.hasRules && payload.record.registersSuppliedRules != false
        let rule: ConfigurationRuleScheme? = hasRules
            ? .init(id:"rules-" + payload.record.id,label:payload.record.label,kind:.supplied,sourceID:payload.record.id) : nil
        draft.add(payload,rule:rule)
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; errorMessage = nil
        Task {
            defer { busy = false }
            do { try await operation() }
            catch {
                errorMessage = ClashErrorCopy.message(error, locale: locale)
                clashLogConfigurationWriteFailure(error)
            }
        }
    }

    private func finish(_ completion: @escaping (Bool) -> Void) {
        guard ready, !busy else { completion(false); return }
        busy = true; errorMessage = nil
        var candidate = draft
        candidate.connectAfterCreation = false
        Task {
            defer { busy = false }
            do {
                if let id = editingProfileID {
                    try await model.editConfiguration(candidate, id: id, generation: library.generation,
                                                      renames: candidate.label != baseline.label)
                } else {
                    _ = try await model.createConfiguration(candidate,generation:library.generation,id:creationID)
                }
                 
                 
                 
                 
                baseline = draft
                if let changed, let store = model.configurationLibraryStore,
                   let saved = try? await Task.detached(operation: { try store.snapshot() }).value {
                    changed(saved)
                }
                completion(true)
                close()
            } catch {
                errorMessage = ClashErrorCopy.message(error, locale: locale)
                clashLogConfigurationWriteFailure(error)  
                completion(false)
            }
        }
    }

    private func close() { dismiss.closeModalOrDismiss() }
}

struct ConfigurationNodeSourceAdapter: View {
    var editorState: CustomNodesEditorState? = nil
    var isFirstConfigurationStep = false
    var tabHeader: ((Bool) -> AnyView)? = nil
    let accept: (ConfigurationSourcePayload) async throws -> Void
     
     
     
     
     
     
     
    var dialerCandidates: (() -> DialerProxyCandidates)? = nil
    @State private var profile = Self.draftProfile()
    @StateObject private var dismiss = ClashDismissHandle()

     
     
     
     
    static func draftProfile() -> Profile {
        Profile(id: UUID().uuidString.lowercased(), label: ConfigurationBuiltins.customNodesName,
            source: .clipboard, autoUpdate: false, updateIntervalHours: 12,
            subscriptionInfo: nil, selectedMap: [:], activeRevision: nil, order: 0, lastUpdatedAt: nil)
    }

    private let emptyNodeDocument = "proxies: []\n"
    var body: some View {
        CustomNodesView(profile: profile, sourceYAML: emptyNodeDocument,
            dialerCandidates: dialerCandidates,
            tabHeader: tabHeader, editorState: editorState,
            loadDraft: { try ProfileProviderDefinitionsDraft(profile: profile, baselineYAML: emptyNodeDocument) },
            saveDraft: { _ in throw ConfigurationLibraryError.unreadable },
            savePayloadAsync: { definition in
                let payload = try await Task.detached {
                    let nodes = try CustomNodePayload.payload(inDefinition: definition)
                    guard !nodes.isEmpty else { throw CustomNodeAppendError.missingName }
                    let document = try JSONSerialization.data(withJSONObject: ["proxies": nodes])
                    let yaml = try ConfigTransforms.jsonToYAML(String(decoding: document, as: UTF8.self))
                    return try ConfigurationCenterSourceBridge.payload(
                        label: nodes.count == 1 ? (nodes[0]["name"] as? String ?? ConfigurationBuiltins.customNodesName)
                            : ConfigurationBuiltins.customNodesName,
                        origin: .customNodes, original: Data(yaml.utf8), yaml: yaml)
                }.value
                try await accept(payload)
            },
            onSaved: { if !isFirstConfigurationStep { dismiss.closeModalOrDismiss() } },
            libraryDraft: true, isFirstConfigurationStep: isFirstConfigurationStep,
            renameNode: { _, _ in })
        .clashProductModalRoot(title: .copy(isFirstConfigurationStep ? "Create Nodes 1/2" : ClashConfigurationAddition.nodes.title))
        .clashCapturesDismiss(dismiss)
    }
}

 
 
 
 
 
 
 
 
 
 
@MainActor
enum ConfigurationSourceUpdate {
    static func run(_ source: ConfigurationSourceRecord, replacingRules: Bool, model: ProfilesViewModel, locale: Locale,
                    changed: @escaping (ConfigurationLibrarySnapshot) -> Void,
                    status: @escaping (String?) -> Void) async throws -> (failures: [String], changed: Bool) {
        var outcome: (failures: [String], changed: Bool) = ([], false)
        var thrown: Error?
         
         
        if model.isUpdatingNodeLibrary || model.isUpdatingRuleCollections {
            status(ClashCopy.string("Waiting for the current update to finish…", locale: locale))
        }
        await model.pageLibraryWrite {
            status(nil)
            do {
                outcome = try await sourceAndItsCollections(source, replacingRules: replacingRules, model: model,
                                                            locale: locale, changed: changed, status: status)
            } catch { thrown = error }
        }
        if let thrown { throw thrown }
        return outcome
    }

     
     
     
     
    static func result(_ outcome: (failures: [String], changed: Bool), label: String) -> ClashFeedbackPresentation {
        let title = outcome.changed ? ClashFeedbackCopy.updated(label) : ClashFeedbackCopy.upToDate(label)
        guard !outcome.failures.isEmpty else { return .success(title: title, accessibilityIdentifier: resultIdentifier) }
        return .warning(title: title, message: .verbatim(outcome.failures.joined(separator: "\n")),
                        accessibilityIdentifier: resultIdentifier)
    }

     
    static func failure(_ error: Error, label: String, locale: Locale) -> ClashFeedbackPresentation {
        .error(title: ClashFeedbackCopy.couldNotUpdate(label),
               message: .verbatim(ClashConfigurationUpdateCopy.message(error, locale: locale)),
               accessibilityIdentifier: resultIdentifier)
    }

    static let resultIdentifier = #"feedback.library.source.update"#

     
     
     
    private static func sourceAndItsCollections(_ source: ConfigurationSourceRecord, replacingRules: Bool,
                                                model: ProfilesViewModel, locale: Locale,
                                                changed: @escaping (ConfigurationLibrarySnapshot) -> Void,
                                                status: @escaping (String?) -> Void) async throws -> (failures: [String], changed: Bool) {
         
         
         
         
        let outcome = try await model.refreshConfigurationSource(source.id, replaceEditedRules: replacingRules,
            expectedVersion: replacingRules ? source.version : nil, restagingConfigurationInUse: false)
        do {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
             
             
             
            let sourceID = source.id
            let entries = try await Task.detached {
                try ConfigurationCollectionContentBridge.catalog(store, snapshot: store.snapshot())
                    .filter { $0.source.id == sourceID }
            }.value
            let downloaded = await ConfigurationCollectionContentBridge.updateNodeCollections(entries, update: { entry in
                let payload = try await Task.detached { try store.payload(.init(entry.source)) }.value
                try await ConfigurationCollectionContentBridge.refresh(entry, source: payload, inUse: model.providerCatalogInUse())
            }, progress: { index, total, name in
                status(ClashCopy.string("Updating Node Collections…", locale: locale) + " \(index) / \(total) · " + name)
            }, naming: { $0.displayLabel(locale: locale) }, describe: { ProfilesViewModel.failureLine($0, $1, locale: locale) })
            changed(try await Task.detached { try store.snapshot() }.value)
             
             
            let failures = downloaded.failures
                 
                 
                + (await model.applyUpdatedCollectionsToConfigurationInUse(
                    downloaded.updatedEntries, failed: downloaded.failedEntries, coreOwned: downloaded.coreOwned,
                    scripts: .surfaced, locale: locale))
            await model.restageConfigurationInUseOwedBySourceRefresh()
            return (failures, outcome == .updated || !downloaded.updatedEntries.isEmpty)
        } catch {
            await model.restageConfigurationInUseOwedBySourceRefresh()
            throw error
        }
    }
}

 
 
struct ConfigurationSourceUpdateConflict: ViewModifier {
    @Binding var isPresented: Bool
    let replace: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog("Update Conflict", isPresented: $isPresented, titleVisibility: .visible) {
            Button("Use Profile URL Rules", role: .destructive, action: replace)
            Button("Cancel", role: .cancel) {}
        } message: { Text(Self.message) }
    }

    static let message: LocalizedStringKey = "Your rule edits conflict with this update. Use the profile URL rules to replace your edits, or cancel to keep the current profile. You can copy your rule scheme before updating."
}

 
 
 
 
struct ConfigurationSourceUpdateConflictFor: ViewModifier {
    @Binding var id: String?
    let replace: (String) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog("Update Conflict",
                                   isPresented: Binding(get: { id != nil }, set: { if !$0 { id = nil } }),
                                   titleVisibility: .visible, presenting: id) { presented in
            Button("Use Profile URL Rules", role: .destructive) { replace(presented) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in Text(ConfigurationSourceUpdateConflict.message) }
    }
}

 
 
private struct ConfigurationSourceDetailAdapter: View {
    @Environment(\.clashFeedback) private var feedback
    @Environment(\.locale) private var locale
    @ObservedObject var model: ProfilesViewModel
    let source: ConfigurationSourceRecord
    let library: ConfigurationLibrarySnapshot
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
    @State private var busy = false
    @State private var updating = false
    @State private var updateStatus: String?
    @State private var errorMessage: String?
    @State private var confirmsRuleReplacement = false
    @State private var showsNodeSource = false

    var body: some View {
        ClashFeatureNavigationContainer {
            ClashConfigurationSourceDetailView(source: source,
                configurations: library.recipes.filter { $0.sources.contains(where: { $0.id == source.id }) || $0.ruleSource.id == source.id }.map(\.label),
                isBusy: busy, error: errorMessage ?? model.sourceRefusals()[source.id]
                    ?? updateIssueMessage(library, sourceID: source.id, locale: locale),
                isUpdating: updating, updateStatus: updateStatus, update: { refreshSource() }, save: { name, settings, completion in
                     
                     
                    perform(completion: completion) {
                        if let settings {
                            changed(try await model.saveConfigurationSourceSettings(source.id, draft: settings, label: name))
                        } else {
                            changed(try await model.renameConfigurationSource(source.id, label: name))
                        }
                    }
                }, close: close, deleteSource: {
                    perform {
                        let deletion = try await model.deleteConfigurationSourceRestorably(source.id, generation: library.generation)
                        changed(deletion.snapshot)
                        close()
                        ConfigurationLibraryUndo.offer(feedback, name: source.displayLabel(locale: locale), deletion: deletion,
                                               model: model, changed: changed)
                    }
                }, editSource: { showsNodeSource = true })
                .deletingWithUndo()
                .clashProductModal(isPresented: $showsNodeSource, role: .page) {
                    ConfigurationNodeSourceEditor(model: model, record: source, changed: changed)
                }
                .modifier(ConfigurationSourceUpdateConflict(isPresented: $confirmsRuleReplacement) {
                    refreshSource(replacingRules: true)
                })
        }
    }
    private func refreshSource(replacingRules: Bool = false) {
        guard !busy else { return }
        updating = true; updateStatus = nil
         
         
         
        var collectionFailures: [String] = []
         
         
         
        var changedAnything = true
        perform(completion: { succeeded in
            updating = false
            if succeeded {
                 
                updateStatus = (changedAnything ? ClashFeedbackCopy.updated(source.displayLabel(locale: locale))
                                                : ClashFeedbackCopy.upToDate(source.displayLabel(locale: locale))).resolved(locale: locale)
                if !collectionFailures.isEmpty { errorMessage = collectionFailures.joined(separator: "\n") }
            } else {
                 
                updateStatus = nil
            }
        }) {
            (collectionFailures, changedAnything) = try await ConfigurationSourceUpdate.run(source, replacingRules: replacingRules,
                model: model, locale: locale, changed: changed, status: { updateStatus = $0 })
        }
    }
    private func perform(completion: @escaping (Bool) -> Void = { _ in },
                         _ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { completion(false); return }
        busy = true; errorMessage = nil
        Task {
            defer { busy = false }
            do { try await operation(); completion(true) }
            catch {
                errorMessage = ClashConfigurationUpdateCopy.message(error, locale: locale)
                if error is ConfigurationRuleReplay.Conflict { confirmsRuleReplacement = true }
                completion(false)
            }
        }
    }
}

 
 
struct ConfigurationSourceImportAdapter: View {
    @ObservedObject var model: ProfilesViewModel
    let kind: ClashConfigurationSourceKind
    var purpose: AddProfilePurpose = .source
    var choosesKind = false
    var isFirstConfigurationStep = false
    var externalTabHeader: ((Bool) -> AnyView)? = nil
    var importRuleCollection: (() -> Void)? = nil
     
     
     
     
    var importRuleSet: ((ConfigurationRuleSetPrefill) -> Void)? = nil
    @State private var chosenKind: ClashConfigurationSourceKind?
    @State private var pendingKind: ClashConfigurationSourceKind?
    @State private var confirmsTabDiscard = false
    var finishImport: (() -> Void)? = nil
    let accept: (ConfigurationSourcePayload) async throws -> Void
    @State private var registerRules = false
    @State private var showsChainForm = false
    @StateObject private var nodeDraft = CustomNodesEditorState()
    @StateObject private var chainDraft = ConfigurationChainEditorDraft()
    @State private var busy = false
    @State private var errorMessage: String?
    @StateObject private var dismiss = ClashDismissHandle()

    private var activeKind: ClashConfigurationSourceKind { chosenKind ?? kind }
    var body: some View {
        Group {
            if activeKind == .customNodes {
                if showsChainForm {
                    ConfigurationChainEditor(model: model, existing: nil, draft: chainDraft,
                        tabHeader: { AnyView(VStack(spacing: 10) {
                            if choosesKind { kindTabs(dirty: chainDraft.isDirty) }
                            nodeKindTabs
                        }) }, isFirstConfigurationStep: isFirstConfigurationStep,
                        accept: accept, close: close, onSaved: isFirstConfigurationStep ? {} : nil)
                } else {
                    ConfigurationNodeSourceAdapter(editorState: nodeDraft, isFirstConfigurationStep: isFirstConfigurationStep, tabHeader: { dirty in
                        AnyView(VStack(spacing: 10) {
                            if choosesKind { kindTabs(dirty: dirty) }
                            nodeKindTabs
                        })
                    }, accept: accept)
                    .environment(\.clashProductModalDismiss, close)
                }
            } else {
                AddProfileView(initialTab: activeKind == .file ? .file : .link, purpose: purpose, dismissAfterSave: purpose != .source,
                    availableTabs: choosesKind ? [.link, .file] : [.link, .file, .blank],
                    tabHeader: externalTabHeader ?? (choosesKind ? { dirty in AnyView(kindTabs(dirty: dirty)) } : nil),
                    sourceKind: (choosesKind || externalTabHeader != nil) ? activeKind : nil,
                    blankFileEntry: choosesKind, isFirstConfigurationStep: isFirstConfigurationStep,
                    registerSuppliedRules: nil, importRuleCollection: importRuleCollection,
                    importRuleSet: importRuleSet,
                    createEmpty: {}, saveAsync: { label, source, raw, resources, nodesOnly in
                        var payload: ConfigurationSourcePayload
                        switch source {
                         
                         
                         
                         
                        case .url(let url): payload = importRuleSet != nil
                            ? try await model.fetchRuleLibrarySource(url: url, label: label)
                            : try await model.fetchConfigurationSource(url: url, label: label, nodesOnly: nodesOnly)
                        case .file(let file):
                            guard let raw else { throw ConfigurationLibraryError.unreadable }
                            payload = try await Task.detached {
                                try ConfigurationCenterSourceBridge.payload(label: label.isEmpty ? file : label,
                                    origin: .file(file), original: Data(raw.utf8), yaml: raw, resources: resources)
                            }.value
                        case .clipboard:
                            guard let raw else { throw ConfigurationLibraryError.unreadable }
                            payload = try await Task.detached {
                                try Self.pastedSourcePayload(label: label, yaml: raw, resources: resources, purpose: purpose)
                            }.value
                        }
                        try await Self.completeImport(payload, purpose: purpose,
                            isFirstConfigurationStep: isFirstConfigurationStep, accept: accept, close: close)
                    }, save: { _, _, _, _ in })
                .environment(\.clashProductModalDismiss, close)
            }
        }
        .clashCapturesDismiss(dismiss)
        .alert("Import Failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(verbatim: errorMessage ?? "") }
    }
     
     
     
    nonisolated static func pastedSourcePayload(label: String, yaml: String, resources: [ExternalResourceImportFile],
                                                purpose: AddProfilePurpose) throws -> ConfigurationSourcePayload {
        if purpose == .source, let node = try ConfigurationCenterSourceBridge.nodeMaterialPayload(label: label, yaml: yaml) {
            return node
        }
        return try ConfigurationCenterSourceBridge.payload(label: label.isEmpty ? "Configuration" : label,
            origin: .file("Configuration.yaml"), original: Data(yaml.utf8), yaml: yaml, resources: resources)
    }

     
     
    @MainActor
    static func completeImport(_ payload: ConfigurationSourcePayload, purpose: AddProfilePurpose,
                               isFirstConfigurationStep: Bool,
                               accept: (ConfigurationSourcePayload) async throws -> Void,
                               close: () -> Void) async throws {
        var value = payload
        if purpose == .source {
            guard value.record.suppliesNodes,
                  value.record.nodeCount > 0 || value.record.providerCount > 0 else {
                throw ConfigurationLibraryError.missingNodes
            }
            value.record.registersSuppliedRules = false
        }
        try await accept(value)
        if purpose == .source && !isFirstConfigurationStep { close() }
    }

    private var nodeKindTabs: some View {
        Picker(ClashCopy.key("Type"), selection: $showsChainForm) {
            Text(ClashCopy.key("Node")).tag(false)
            Text(ClashCopy.key("Proxy Chain")).tag(true)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("configuration.source.import.kind")
        .labelsHidden()
        .padding(.horizontal, 18)
        .padding(.bottom, 2)
        .accessibilityIdentifier("configuration.source.nodeKind")
    }
    private func kindTabs(dirty: Bool) -> some View {
        Picker(ClashCopy.key("Type"), selection: Binding(get: { activeKind }, set: { next in
            guard next != activeKind else { return }
            if (dirty || chainDraft.isDirty || !nodeDraft.customRows.isEmpty) && (activeKind == .customNodes || next == .customNodes) {
                pendingKind = next
                confirmsTabDiscard = true
            } else { chosenKind = next }
        })) {
            Text(ClashCopy.key("URL")).tag(ClashConfigurationSourceKind.subscription)
            Text(ClashCopy.key("File")).tag(ClashConfigurationSourceKind.file)
            Text(ClashCopy.key("Manual")).tag(ClashConfigurationSourceKind.customNodes)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("configuration.source.import.kind")
        .labelsHidden()
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 2)
        .alert("Discard Changes?", isPresented: $confirmsTabDiscard) {
            Button("Discard Changes", role: .destructive) {
                nodeDraft.customRows = nodeDraft.openedWith
                nodeDraft.pendingRenames = []
                chainDraft.name = ""; chainDraft.entry = nil; chainDraft.exit = nil
                chosenKind = pendingKind
                pendingKind = nil
            }
            Button("Keep Editing", role: .cancel) { pendingKind = nil }
        } message: { Text("Switching tabs discards what you have not saved.") }
    }
    private func close() { if let finishImport { finishImport() } else { dismiss.closeModalOrDismiss() } }
}

 
 
struct ConfigurationLibraryBrowseCache {
    let generation: UInt64
    let entries: [ConfigurationCollectionEntry]
     
     
     
    var contentEpoch: UInt64 = 0
    func matches(_ snapshot: ConfigurationLibrarySnapshot, contentEpoch epoch: UInt64) -> Bool {
        generation == snapshot.generation && contentEpoch == epoch
    }
}

 
 
 
 
 
 
 
 
 
 
 
@MainActor
enum ConfigurationCollectionListing {
    static func list(
        _ store: ConfigurationLibraryStore, held: ConfigurationLibrarySnapshot,
        adopt: (ConfigurationLibrarySnapshot) -> Void,
        catalog: @escaping @Sendable (ConfigurationLibraryStore, ConfigurationLibrarySnapshot) throws -> [ConfigurationCollectionEntry]
            = { try ConfigurationCollectionContentBridge.catalog($0, snapshot: $1) },
        snapshot: @escaping @Sendable (ConfigurationLibraryStore) throws -> ConfigurationLibrarySnapshot = { try $0.snapshot() }
    ) async throws -> (entries: [ConfigurationCollectionEntry], library: ConfigurationLibrarySnapshot) {
        do {
            return (try await Task.detached { try catalog(store, held) }.value, held)
        } catch ConfigurationLibraryError.unreadable {
            let fresh = try await Task.detached { try snapshot(store) }.value
            if !Task.isCancelled { adopt(fresh) }
            return (try await Task.detached { try catalog(store, fresh) }.value, fresh)
        }
    }

     
     
     
     
    static func takes(_ read: ConfigurationLibrarySnapshot, over held: ConfigurationLibrarySnapshot) -> Bool {
        read.generation >= held.generation
    }

     
     
     
    static func pageLibrary(holding current: ConfigurationLibrarySnapshot, listed held: ConfigurationLibrarySnapshot,
                            read: ConfigurationLibrarySnapshot) -> ConfigurationLibrarySnapshot? {
        guard current.generation == held.generation else { return nil }
        return takes(read, over: current) ? read : current
    }
}

 
 
 
 
struct ConfigurationListingErrorLine: Equatable {
    private(set) var message: String?
    private var listingWroteIt = false
    init(message: String? = nil) { self.message = message }
    static func listingFailed(_ message: String) -> Self {
        var line = Self(message: message)
        line.listingWroteIt = true
        return line
    }
    mutating func listingSucceeded() {
        if listingWroteIt { self = .init() }
    }
}

 
struct ConfigurationSourceLibraryAdapter: View {
    @Environment(\.locale) private var locale
    @Environment(\.clashFeedback) private var feedback
    @ObservedObject var model: ProfilesViewModel
    @State var library: ConfigurationLibrarySnapshot
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
    var embedded = false
    var showsClose = true
    var browseCache: Binding<ConfigurationLibraryBrowseCache?>? = nil
     
     
    @StateObject private var quickAdd: ProfileQuickAddController

    init(model: ProfilesViewModel, library: ConfigurationLibrarySnapshot,
         changed: @escaping (ConfigurationLibrarySnapshot) -> Void, close: @escaping () -> Void,
         embedded: Bool = false, showsClose: Bool = true,
         browseCache: Binding<ConfigurationLibraryBrowseCache?>? = nil) {
        _model = ObservedObject(wrappedValue: model)
        _library = State(initialValue: library)
        self.changed = changed; self.close = close
        self.embedded = embedded; self.showsClose = showsClose; self.browseCache = browseCache
        _quickAdd = StateObject(wrappedValue: ProfileQuickAddController(model: model, target: .source))
        _running = StateObject(wrappedValue: RunningProvidersReader(container: { [model] in model.appGroupContainer }))
    }
    @State private var ready = false
    @State private var busy = false
     
    @State private var errorLine = ConfigurationListingErrorLine()
     
     
    private var errorMessage: String? {
        get { errorLine.message }
        nonmutating set { errorLine = .init(message: newValue) }
    }
    @State private var statusMessage: String?
    @State private var updateProgress: String?
    @State private var importKind: SourceAddRequest?
     
     
     
    @State private var showsNewNode = false
    @State private var showsNewChain = false
    @State private var inspectedSourceID: String?
    @State private var showsManagement = false
    @State private var collections: [ConfigurationCollectionEntry] = []
     
     
     
    @StateObject private var running: RunningProvidersReader
    @State private var inspectedCollection: ConfigurationCollectionEntry?
     
     
    @State private var adoptingRunID: UUID?
     
    @State private var refusals: [String: String] = [:]
     
     
    @State private var conflictSourceID: String?

    var body: some View {
        ConfigurationLibraryNavigation(embedded: embedded) {
            ClashConfigurationSourceLibraryView(library: library, palette: .clashProduct, isReady: ready || library.generation > 0 || browseCache?.wrappedValue != nil, isBusy: busy || updatingLibrary, error: errorMessage ?? updateIssueMessage(library, locale: locale),
                add: { importKind = .init(kind: $0, showsDoors: true) }, open: { showsManagement = false; inspectedSourceID = $0 },
                reload: { Task { await reload() } }, close: close, updateAll: updateAll,
                refreshAll: {
                     
                     
                     
                    if !updatingLibrary { errorMessage = nil; statusMessage = nil }
                    await model.updateNodeLibrary(locale: locale).value
                    guard !Task.isCancelled else { return }
                    await adoptFinishedUpdate()
                },
                status: statusMessage, updateProgress: model.nodeLibraryUpdate?.progress ?? updateProgress, isCenterSection: embedded, showsClose: showsClose,
                collections: visibleCollections, openCollection: { inspectedCollection = $0 },
                 
                 
                 
                quickAdd: embedded
                    ? { AnyView(ProfileQuickAddCard(controller: quickAdd,
                        identifiers: .init(linkIdentifier: "configuration.library.quick-add.link",
                                           scanIdentifier: "configuration.library.quick-add.scan",
                                           fileIdentifier: "configuration.library.quick-add.file",
                                           manualIdentifier: "configuration.library.quick-add.manual",
                                           statusIdentifier: "configuration.library.quick-add.status"),
                        manual: { showsNewNode = true })
                        .disabled(libraryHeldByRun)) }
                    : nil,
                addMenu: embedded ? { AnyView(sourceAddMenu) } : nil,
                refusals: refusals,
                updateSource: { updateSource($0) }, copySourceLink: copySourceLink, deleteSource: deleteSource)
            .modifier(ConfigurationSourceUpdateConflictFor(id: $conflictSourceID) { id in updateSource(id, replacingRules: true) })
            .profileQuickAddPresenters(quickAdd)
            .onAppear {
                quickAdd.onSourceAdded = { updated in library = updated; changed(updated) }
            }
            .clashProductModal(isPresented: $showsNewNode, role: .page) {
                ConfigurationNewNodeAdapter(model: model, library: library,
                    changed: { updated in library = updated; changed(updated) },
                    close: { showsNewNode = false })
            }
            .clashProductModal(isPresented: $showsNewChain, role: .page) {
                ConfigurationChainEditor(model: model, existing: nil, accept: { payload in
                    let updated = try await model.addConfigurationSource(payload, generation: library.generation)
                    library = updated; changed(updated)
                }, close: { showsNewChain = false })
            }
            .task(id: library.generation) {
                refusals = model.sourceRefusals()
                if !ready {
                    if browseCache?.wrappedValue != nil || library.generation > 0 { ready = true }
                    else { await reload() }
                }
                await loadCollections()
            }
            .onReceive(NotificationCenter.default.publisher(for: ConfigurationSourceRefusals.didChange)) { _ in
                refusals = model.sourceRefusals()
            }
             
             
             
            .task { await adoptFinishedUpdate() }
            .clashOnScreen { running.follow($0) }
            .onReceive(NotificationCenter.default.publisher(for: .clashActiveConfigurationRepublished)) { _ in
                Task { await running.reload() }
            }
            .onChange(of: model.activeProfileID) { _ in Task { await running.reload() } }
            .onChange(of: model.nodeLibraryUpdate?.finished == true) { finished in
                if finished { Task { await adoptFinishedUpdate(); await running.reload() } }
            }
             
            .onChange(of: updatingLibrary) { running in
                if running { errorMessage = nil; statusMessage = nil }
            }
            .onChange(of: inspectedCollection == nil) { closed in
                if closed { Task { await loadCollections(force: true) } }
            }
            .clashProductModal(item: $inspectedCollection, role: .page) { entry in
                ConfigurationCollectionAdapter(model: model, entry: entry, changed: { library = $0; changed($0) }, close: { inspectedCollection = nil })
            }
            .clashProductModal(item: $importKind, role: .page) { request in
                 
                 
                ConfigurationSourceImportAdapter(model: model, kind: request.kind, choosesKind: request.showsDoors) { payload in
                    let updated = try await model.addConfigurationSource(payload, generation: library.generation)
                    library = updated; changed(updated)
                }
            }
            .clashProductModal(isPresented: Binding(get: { inspectedSourceID != nil },
                set: { if !$0 { inspectedSourceID = nil } }), role: .page) {
                if let id = inspectedSourceID, let source = library.sources.first(where: { $0.id == id }) {
                    Group {
                        if source.nodeChain != nil {
                            ConfigurationChainDetail(model: model, source: source,
                                changed: { updated in library = updated; changed(updated) },
                                close: { inspectedSourceID = nil })
                        } else {
                            ConfigurationDocumentBrowserAdapter(model: model, sourceID: source.id, title: source.displayLabel(locale: locale), kind: .nodes, embedded: false,
                                canEditNodes: source.origin == .customNodes && source.isRetainedSnapshot != true,
                                changed: { updated in library = updated; changed(updated) },
                                manage: { showsManagement = true }, close: { inspectedSourceID = nil })
                        }
                    }
                    .clashProductModal(isPresented: $showsManagement, role: .page) {
                        ConfigurationSourceDetailAdapter(model: model, source: source, library: library,
                            changed: { updated in
                                library = updated; changed(updated)
                                if !updated.sources.contains(where: { $0.id == id }) {
                                    showsManagement = false
                                    inspectedSourceID = nil
                                }
                            }, close: { showsManagement = false })
                    }
                }
            }
        }
    }
    private var visibleCollections: [ConfigurationCollectionEntry] {
        let entries: [ConfigurationCollectionEntry]
        if let cached = browseCache?.wrappedValue, cached.matches(library, contentEpoch: model.libraryContentEpoch) {
            entries = cached.entries
        } else {
            entries = collections
        }
         
         
         
        return ConfigurationCollectionContentBridge.withRunningUsage(entries, running: running.current)
    }
     
     
     
     
     
     
    private var sourceAddMenu: some View {
        Menu {
             
             
            Section { addDoor("Scan QR Code", symbol: .qrcodeViewfinder, identifier: "configuration.library.add.scan") { quickAdd.showsQRCapture = true } }
            Section { addDoor("Import File", symbol: .arrowUpDocument, identifier: "configuration.library.add.file") { quickAdd.showsImporter = true } }
            Section { addDoor("quick-add.new.node", symbol: .docBadgePlus, identifier: "configuration.library.add.node") { showsNewNode = true } }
            Section { addDoor("New Proxy Chain", symbol: .link, identifier: "configuration.library.add.chain") { showsNewChain = true } }
        } label: {
            Image(systemName: ClashSymbol.plusCircle.rawValue).clashToolbarGlyph()
        }
         
         
        .disabled(busy || libraryHeldByRun || !ready)
        .accessibilityLabel(ClashCopy.key("Add Nodes"))
        .accessibilityIdentifier("configuration.library.add")
    }

    private func addDoor(_ title: String, symbol: ClashSymbol, identifier: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(ClashCopy.key(title), systemImage: symbol.name)
        }
        .accessibilityIdentifier(identifier)
    }

    private func loadCollections(force: Bool = false) async {
        if !force, let cached = browseCache?.wrappedValue, cached.matches(library, contentEpoch: model.libraryContentEpoch) {
            collections = cached.entries
            errorLine.listingSucceeded()
            return
        }
        guard let store = model.configurationLibraryStore else { return }
        do {
            let snapshot = library
             
             
            let epoch = model.libraryContentEpoch
             
             
             
            let read = try await ConfigurationCollectionListing.list(store, held: snapshot, adopt: changed)
            guard !Task.isCancelled,
                  let taken = ConfigurationCollectionListing.pageLibrary(holding: library, listed: snapshot, read: read.library)
            else { return }
             
            if taken.generation != library.generation { library = taken }
            collections = read.entries
            errorLine.listingSucceeded()
            if model.libraryContentEpoch == epoch {
                browseCache?.wrappedValue = .init(generation: read.library.generation, entries: read.entries, contentEpoch: epoch)
            }
        }
        catch {
             
            guard !Task.isCancelled else { return }
            errorLine = .listingFailed(ClashErrorCopy.message(error, locale: locale))
        }
    }
    private func updateAll() {
        if !updatingLibrary { errorMessage = nil; statusMessage = nil }
        _ = model.updateNodeLibrary(locale: locale)
    }
     
     
     
     
    private func updateSource(_ id: String, replacingRules: Bool = false) {
        guard !busy, !updatingLibrary, let source = library.sources.first(where: { $0.id == id }) else { return }
        busy = true; errorMessage = nil
        let operation = #"configuration.library.source.update"#
        let step = { (said: String?) -> ClashFeedbackPresentation in
            .loading(title: ClashFeedbackCopy.updating, message: .verbatim(said ?? source.displayLabel(locale: locale)),
                     accessibilityIdentifier: ConfigurationSourceUpdate.resultIdentifier)
        }
        let running = feedback?.show(.loading(title: ClashFeedbackCopy.updating, message: .verbatim(source.displayLabel(locale: locale)),
                                              accessibilityIdentifier: ConfigurationSourceUpdate.resultIdentifier),
                                     operation: operation)
        Task { @MainActor in
            defer { busy = false }
            do {
                let outcome = try await ConfigurationSourceUpdate.run(source, replacingRules: replacingRules, model: model,
                    locale: locale, changed: { updated in library = updated; changed(updated) },
                    status: { said in if let running { feedback?.update(running, to: step(said)) } })
                feedback?.answer(running, with: ConfigurationSourceUpdate.result(outcome, label: source.displayLabel(locale: locale)), operation: operation)
            } catch {
                feedback?.answer(running, with: ConfigurationSourceUpdate.failure(error, label: source.displayLabel(locale: locale), locale: locale),
                                 operation: operation)
                if error is ConfigurationRuleReplay.Conflict { conflictSourceID = id }
            }
            refusals = model.sourceRefusals()
        }
    }
     
     
    private func copySourceLink(_ id: String) {
        guard let source = library.sources.first(where: { $0.id == id }), case .subscription(let link) = source.origin else { return }
        ClashClipboard.copy(link, feedback: feedback, noun: "Link", operation: #"configuration.library.source.copy-link"#)
    }
     
    private func deleteSource(_ id: String) {
        guard !busy, let source = library.sources.first(where: { $0.id == id }) else { return }
        busy = true; errorMessage = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let deletion = try await model.deleteConfigurationSourceRestorably(id, generation: library.generation)
                library = deletion.snapshot; changed(deletion.snapshot)
                ConfigurationLibraryUndo.offer(feedback, name: source.displayLabel(locale: locale), deletion: deletion, model: model,
                                               changed: { updated in library = updated; changed(updated) })
            } catch {
                errorMessage = ClashConfigurationUpdateCopy.message(error, locale: locale)
            }
        }
    }
     
     
    private var updatingLibrary: Bool { model.isUpdatingNodeLibrary }
     
     
     
    private var libraryHeldByRun: Bool { model.nodeLibraryUpdate != nil }
     
     
    private func adoptFinishedUpdate() async {
        guard let run = model.nodeLibraryUpdate, run.finished, adoptingRunID != run.id else { return }
        adoptingRunID = run.id
         
         
         
        let recent = run.finishedAt.map { Date().timeIntervalSince($0) < 30 } ?? false
        var failures = run.failures
        if let store = model.configurationLibraryStore {
            do {
                library = try await Task.detached { try store.snapshot() }.value
                changed(library)
            } catch { failures.append(ClashErrorCopy.message(error, locale: locale)) }
        }
         
         
        model.acknowledgeNodeLibraryUpdate(run.id)
         
        await loadCollections(force: true)
         
        guard recent, model.nodeLibraryUpdate == nil else { return }
         
         
        statusMessage = ConfigurationLibraryRunSummary.line(ClashCopy.string("Resources updated", locale: locale),
            updated: run.updated, total: run.total, unconfirmed: run.unconfirmed,
            appliesOnConnect: run.appliesOnConnect, locale: locale)
        if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
    }
    private func reload(showsLoading: Bool = true) async {
        guard !busy else { return }
        if showsLoading { busy = true }
        errorMessage = nil; statusMessage = nil
        defer { if showsLoading { busy = false } }
        do {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            do { try await model.registerLegacyConfigurationSources() }
            catch { errorMessage = ClashErrorCopy.message(error, locale: locale) }
            library = try await Task.detached { try store.snapshot() }.value
            changed(library); ready = true
        } catch { errorMessage = ClashErrorCopy.message(error, locale: locale) }
    }
}

 
 
 
private struct RuleAddPage: View {
    @ObservedObject var model: ProfilesViewModel
    let library: ConfigurationLibrarySnapshot
    let initialDoor: RuleAddRequest
    let apply: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void

    @State private var door: RuleAddRequest
    @State private var pendingDoor: RuleAddRequest?
    @State private var confirmsDiscard = false
    @State private var importingCollection = false
     
     
    @State private var collectionPrefill: ConfigurationRuleSetPrefill?
     
     
    @State private var routedSetSaved = false

    init(model: ProfilesViewModel, library: ConfigurationLibrarySnapshot, initialDoor: RuleAddRequest,
         apply: @escaping (ConfigurationLibrarySnapshot) -> Void, close: @escaping () -> Void) {
        _model = ObservedObject(wrappedValue: model)
        self.library = library; self.initialDoor = initialDoor; self.apply = apply; self.close = close
        _door = State(initialValue: initialDoor)
    }

    var body: some View {
        Group {
            switch door {
            case .url, .file:
                ConfigurationSourceImportAdapter(model: model, kind: door == .url ? .subscription : .file,
                    purpose: .rules, externalTabHeader: { AnyView(doors(dirty: $0)) },
                    importRuleCollection: { collectionPrefill = nil; importingCollection = true },
                    importRuleSet: { collectionPrefill = $0; importingCollection = true }, finishImport: close) { payload in
                    if payload.record.ruleCount > 0 {
                        apply(try await model.addConfigurationRuleScheme(payload, generation: library.generation))
                    } else {
                        var value = payload; value.record.suppliesNodes = false; value.record.registersSuppliedRules = false
                        guard !ConfigurationCollection.read(sourceID: value.record.id,
                            document: try OrderedJSON.parse(value.documentJSON), kind: .rules).isEmpty else {
                            throw ConfigurationLibraryError.missingRules
                        }
                        apply(try await model.addConfigurationSource(value, generation: library.generation))
                    }
                    close()
                }.id(door)
            case .manual, .manualAlone:
                 
                 
                ConfigurationNewRuleAdapter(model: model, library: library,
                    tabHeader: door.showsDoors ? { AnyView(doors(dirty: $0)) } : nil,
                    changed: apply, close: close)
            }
        }
        .clashProductModal(isPresented: $importingCollection, role: .page) {
            ConfigurationCollectionImportAdapter(model: model, library: library,
                changed: { snapshot in
                    apply(snapshot)
                    if collectionPrefill != nil { routedSetSaved = true }
                },
                close: {
                    importingCollection = false
                    if routedSetSaved { close() }
                }, initial: collectionPrefill)
        }
        .alert("Discard Changes?", isPresented: $confirmsDiscard) {
            Button("Keep Editing", role: .cancel) { pendingDoor = nil }
            Button("Discard Changes", role: .destructive) { if let next = pendingDoor { door = next }; pendingDoor = nil }
        } message: { Text("Switching tabs discards what you have not saved.") }
    }

    private func doors(dirty: Bool) -> some View {
        Picker("Add Rules", selection: Binding(get: { door }, set: { next in
            guard next != door else { return }
            if dirty { pendingDoor = next; confirmsDiscard = true } else { door = next }
        })) {
            Text(ClashCopy.key("URL")).tag(RuleAddRequest.url)
            Text(ClashCopy.key("File")).tag(RuleAddRequest.file)
            Text(ClashCopy.key("Manual")).tag(RuleAddRequest.manual)
        }
         
         
        .pickerStyle(.segmented)
        .accessibilityIdentifier("configuration.rules.add.tabs")
        .labelsHidden()
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }
}

 
 
 
 
private struct ConfigurationNewNodeAdapter: View {
    @ObservedObject var model: ProfilesViewModel
    let library: ConfigurationLibrarySnapshot
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void

     
     
     
     
    @State private var candidates: DialerProxyCandidates = .empty

    var body: some View {
        ClashFeatureNavigationContainer {
            ProxyNodeDetailsView(
                record: CustomNodesView.newNodeTemplate,
                retest: {},
                saveNode: { _, edited in try await save(edited) },
                showsTesting: false,
                isNew: true,
                dialerRouting: .payloadField,
                dialerCandidates: { candidates },
                onDone: close
            )
        }
        .clashModalPresentation(.page)
        .task { await loadCandidates() }
    }

    private func loadCandidates() async {
         
         
         
        guard let profile = model.profiles.first(where: { $0.id == model.activeProfileID }),
              let yaml = await model.loadPresentedProxiesYAML(for: profile) else { return }
         
         
         
         
        candidates = DialerProxyCandidates.make(sourceYAML: yaml, excluding: "")
    }

    private func save(_ editedJSON: String) async throws {
        let payload = try await Task.detached {
            let nodes = try CustomNodeAppend.appended(payload: [], editedJSON: editedJSON)
            let document = try JSONSerialization.data(withJSONObject: ["proxies": nodes])
            let yaml = try ConfigTransforms.jsonToYAML(String(decoding: document, as: UTF8.self))
            return try ConfigurationCenterSourceBridge.payload(
                label: nodes.first?["name"] as? String ?? ConfigurationBuiltins.customNodesName,
                origin: .customNodes, original: Data(yaml.utf8), yaml: yaml)
        }.value
        let updated = try await model.addConfigurationSource(payload, generation: library.generation)
        changed(updated)
    }
}

 
 
private struct SourceAddRequest: Identifiable, Hashable {
    let kind: ClashConfigurationSourceKind
    let showsDoors: Bool
    var id: String { "\(kind)-\(showsDoors)" }
}

 
 
private enum RuleAddRequest: Int, Identifiable, Hashable {
     
    case url = 1, file = 2, manual = 3
     
     
     
    case manualAlone = 4
    var id: Int { rawValue }
    var showsDoors: Bool { self != .manualAlone }
}

 
 
 
 
 
enum ConfigurationLibraryRunSummary {
    static func line(_ head: String, updated: Int, total: Int, unconfirmed: Int, appliesOnConnect: Bool,
                     locale: Locale) -> String {
        var parts = [ClashCopy.format("%@: %@", locale: locale, head, ClashCopy.count(updated, locale: locale))]
        let failed = total - updated - unconfirmed
        if failed > 0 { parts.append(ClashCopy.format("%d failed", locale: locale, failed)) }
        if unconfirmed > 0 { parts.append(ClashCopy.format("%d not confirmed", locale: locale, unconfirmed)) }
        if appliesOnConnect { parts.append(ClashCopy.string("Applied when Clash connects", locale: locale)) }
        return parts.joined(separator: " · ")
    }

     
     
     
    static func somethingFailed(updated: Int, total: Int, unconfirmed: Int, failures: [String]) -> Bool {
        total - updated - unconfirmed > 0 || !failures.isEmpty
    }
}

 
 
 
 
 
 
 
@MainActor
enum RuleRunFeedbackRelay {
    static let operation = "rules.update-all"
    private static let identifier = "feedback.rules.update"

    static func relay(_ run: ProfilesViewModel.CollectionUpdateRun?, to center: ClashFeedbackCenter,
                      locale: Locale, acknowledge: @escaping (UUID) -> Void) {
        guard let run, let entry = runningEntry(in: center) else { return }
        guard run.finished else {
            guard let progress = run.progress else { return }
            let running = ClashFeedbackPresentation.loading(title: .verbatim(progress), accessibilityIdentifier: identifier)
            if entry.presentation != running { center.update(entry.id, to: running) }
            return
        }
        let status = ConfigurationLibraryRunSummary.line(
            ClashCopy.string("Rule sets updated", locale: locale), updated: run.updated, total: run.total,
            unconfirmed: run.unconfirmed, appliesOnConnect: run.appliesOnConnect, locale: locale)
        let failed = ConfigurationLibraryRunSummary.somethingFailed(
            updated: run.updated, total: run.total, unconfirmed: run.unconfirmed, failures: run.failures)
         
        let result: ClashFeedbackPresentation = failed
            ? .warning(title: .verbatim(status), message: run.failures.first.map { .verbatim($0) },
                       isBatchSummary: true, accessibilityIdentifier: identifier)
            : .success(title: .verbatim(status), isBatchSummary: true, accessibilityIdentifier: identifier)
        let id = run.id
        center.update(entry.id, to: result, onDismiss: { acknowledge(id) })
    }

     
    private static func runningEntry(in center: ClashFeedbackCenter) -> ClashFeedbackCenterState.ShownResult? {
        [center.state.current, center.state.covered].compactMap { $0 }
            .first { $0.operation == operation && $0.presentation.kind == .loading }
    }
}

 
enum RuleLibraryReload: Equatable {
     
    case apply
     
    case loadCollections

    static func step(held: UInt64, read: UInt64) -> Self {
         
        read <= held ? .loadCollections : .apply
    }
}

struct ConfigurationRuleLibraryAdapter: View {
    @Environment(\.clashFeedback) private var feedback
    @Environment(\.locale) private var locale
    @ObservedObject var model: ProfilesViewModel
    @State var library: ConfigurationLibrarySnapshot
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
    var embedded = false
    var showsClose = true
    var browseCache: Binding<ConfigurationLibraryBrowseCache?>? = nil
     
     
    @StateObject private var quickAdd: ProfileQuickAddController

    init(model: ProfilesViewModel, library: ConfigurationLibrarySnapshot,
         changed: @escaping (ConfigurationLibrarySnapshot) -> Void, close: @escaping () -> Void,
         embedded: Bool = false, showsClose: Bool = true,
         browseCache: Binding<ConfigurationLibraryBrowseCache?>? = nil) {
        self.model = model
        _library = State(initialValue: library)
        self.changed = changed; self.close = close
        self.embedded = embedded; self.showsClose = showsClose; self.browseCache = browseCache
        _quickAdd = StateObject(wrappedValue: ProfileQuickAddController(model: model, target: .rules))
    }
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var openedSchemeID: String?
     
     
     
     
    @State private var addRequest: RuleAddRequest?
    @State private var showsRuleSetImport = false
    @State private var collections: [ConfigurationCollectionEntry] = []
    @State private var inspectedCollection: ConfigurationCollectionEntry?
    @State private var ready = false
    var body: some View {
        ConfigurationLibraryNavigation(embedded: embedded) {
            ClashTowerRulesLibraryView(library: library, palette: .clashProduct, busy: busy,
                error: errorMessage ?? ruleRun.flatMap { $0.finished && !$0.failures.isEmpty ? $0.failures.joined(separator: "\n") : nil },
                open: { openedSchemeID = $0 },
                refresh: refreshScheme,
                delete: { id in perform {
                    let name = library.effectiveRuleScheme(id)?.label ?? id
                    let deletion = try await model.deleteConfigurationRuleSchemeRestorably(id, generation: library.generation)
                    apply(deletion.snapshot)
                    ConfigurationLibraryUndo.offer(feedback, name: name, deletion: deletion, model: model, changed: apply)
                } },
                add: { addRequest = .url }, close: close, showsClose: showsClose, isCenterSection: embedded,
                collections: visibleCollections, openCollection: { inspectedCollection = $0 },
                updateAll: visibleCollections.contains(where: { $0.id.kind == .rules && $0.collection.type == "http" && $0.source.isRetainedSnapshot != true }) ? updateAllRuleSets : nil,
                updateProgress: ruleRun.flatMap { $0.finished ? nil : $0.progress },
                updateStatus: ruleRun.flatMap { run in run.finished ? runSummary(run) : nil } ?? schemeRefreshResult,
                 
                 
                quickAdd: embedded
                    ? { AnyView(ProfileQuickAddCard(controller: quickAdd,
                        identifiers: .init(linkIdentifier: "configuration.library.rules.quick-add.link",
                                           scanIdentifier: "configuration.library.rules.quick-add.scan",
                                           fileIdentifier: "configuration.library.rules.quick-add.file",
                                           manualIdentifier: "configuration.library.rules.quick-add.manual",
                                           statusIdentifier: "configuration.library.rules.quick-add.status"),
                        manual: { addRequest = .manualAlone })
                        .disabled(model.isUpdatingNodeLibrary)) }
                    : nil,
                addMenu: embedded ? { AnyView(ruleAddMenu) } : nil,
                rename: { id, name in perform { apply(try await model.renameConfigurationRuleScheme(id, label: name)) } },
                isUpdating: model.isUpdatingRuleCollections,
                updatingCollections: model.isUpdatingRuleCollections ? (ruleRun?.updating ?? []) : [],
                 
                updateCollection: {
                    errorMessage = nil; schemeRefreshResult = nil
                    model.updateRuleCollections([$0], scripts: .surfaced, locale: locale)
                },
                updateFailed: ruleRun.map { run in
                    run.finished && ConfigurationLibraryRunSummary.somethingFailed(updated: run.updated, total: run.total,
                                                                                    unconfirmed: run.unconfirmed, failures: run.failures)
                } ?? false,
                 
                 
                 
                dismissUpdate: ruleRun.flatMap { run in run.finished ? { model.acknowledgeRuleCollectionUpdate(run.id) } : nil }
                    ?? dismissSchemeRefresh,
                refreshingSchemes: refreshingSchemeIDs,
                deleteSource: { id in perform {
                    let name = library.sources.first(where: { $0.id == id }).map { $0.displayLabel(locale: locale) } ?? id
                    let deletion = try await model.deleteConfigurationSourceRestorably(id, generation: library.generation)
                    apply(deletion.snapshot)
                    ConfigurationLibraryUndo.offer(feedback, name: name, deletion: deletion, model: model, changed: apply)
                } },
                 
                 
                copyLink: { ClashClipboard.copy($0, feedback: feedback, noun: "Link", operation: #"configuration.rules.library.copy-link"#) },
                 
                refreshAll: {
                    errorMessage = nil; schemeRefreshResult = nil
                    await model.updateRuleCollections(visibleCollections, scripts: .silent, locale: locale).value
                    guard !Task.isCancelled else { return }
                    await loadCollections(force: true)
                })
                .deletingWithUndo()
            .profileQuickAddPresenters(quickAdd)
             
             
            .onChange(of: model.libraryContentEpoch) { _ in Task { await loadCollections(force: true) } }
            .onChange(of: model.activeProfileID) { _ in Task { await loadRunningCatalog() } }
            .onReceive(NotificationCenter.default.publisher(for: .clashActiveConfigurationRepublished)) { _ in
                Task { await loadRunningCatalog() }
            }
            .onAppear { Task { await loadRunningCatalog() } }
            .onAppear { quickAdd.onSourceAdded = apply }
            .task {
                if !ready {
                    if browseCache?.wrappedValue != nil { ready = true; await loadCollections() }
                    else { perform { try await reload(); ready = true } }
                }
            }
             
             
             
             
            .clashProductModal(isPresented: Binding(get: { addRequest != nil },
                                                   set: { if !$0 { addRequest = nil } }), role: .page) {
                RuleAddPage(model: model, library: library, initialDoor: addRequest ?? .url,
                            apply: apply, close: { addRequest = nil })
            }
             
             
             
            .clashProductModal(isPresented: $showsRuleSetImport, role: .page) {
                ConfigurationCollectionImportAdapter(model: model, library: library, changed: apply,
                    close: { showsRuleSetImport = false })
            }
            .onChange(of: openedSchemeID == nil) { closed in
                if closed { Task { await loadCollections() } }
            }
            .onChange(of: inspectedCollection == nil) { closed in
                if closed { Task { await loadCollections(force: true) } }
            }
            .clashProductModal(item: $inspectedCollection, role: .page) { entry in
                ConfigurationCollectionAdapter(model: model, entry: entry, changed: apply, close: { inspectedCollection = nil })
            }
            .clashProductModal(isPresented: Binding(get: { openedSchemeID != nil }, set: { if !$0 { openedSchemeID = nil } }), role: .page) {
                if let id = openedSchemeID, let scheme = library.effectiveRuleScheme(id) {
                    ConfigurationTowerRuleCustomizationAdapter(model: model, scheme: scheme, library: library, pushed: false,
                        changed: apply, close: { openedSchemeID = nil })
                }
            }
        }
    }
    private func apply(_ value: ConfigurationLibrarySnapshot) {
        guard library.generation != value.generation else { return }
        library = value; changed(value)
         
         
        if openedSchemeID == nil { Task { await loadCollections() } }
    }
    private func reload() async throws {
        do { try await model.registerLegacyConfigurationSources() } catch { errorMessage = ClashErrorCopy.message(error, locale: locale) }
        guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        let read = try await Task.detached { try store.snapshot() }.value
        switch RuleLibraryReload.step(held: library.generation, read: read.generation) {
        case .apply:
            apply(read)
        case .loadCollections:
             
             
             
            await loadCollections()
        }
    }
    private var visibleCollections: [ConfigurationCollectionEntry] {
        let entries: [ConfigurationCollectionEntry]
        if let cached = browseCache?.wrappedValue, cached.matches(library, contentEpoch: model.libraryContentEpoch) {
            entries = cached.entries
        } else {
            entries = collections
        }
         
         
         
         
         
         
        let read = library.sourcesWhoseRulesAreRead
        let kept = entries.filter { $0.id.kind != .rules || !$0.source.suppliesNodes || read.contains($0.source.id) }
         
         
         
        return runningCatalog.map { ConfigurationCollectionContentBridge.withRunningCounts(kept, catalog: $0) } ?? kept
    }
     
     
     
    @State private var runningCatalog: ProviderCatalog?
    private func loadRunningCatalog() async {
        let container = model.appGroupContainer
        runningCatalog = await Task.detached { () -> ProviderCatalog? in
            guard let container, let store = try? ConfigResourceStore(containerURL: container),
                  let directory = try? store.activeProvidersDirectory() else { return nil }
            return ProviderCatalog.load(providersDir: directory)
        }.value
    }
     
     
     
    private var ruleAddMenu: some View {
        Menu {
             
            Section { ruleDoor("Scan QR Code", symbol: .qrcodeViewfinder, identifier: "configuration.library.rules.add.scan") { quickAdd.showsQRCapture = true } }
            Section { ruleDoor("Import File", symbol: .arrowUpDocument, identifier: "configuration.library.rules.add.file") { quickAdd.showsImporter = true } }
            Section { ruleDoor("quick-add.new.rules", symbol: .docBadgePlus, identifier: "configuration.library.rules.add.manual") { addRequest = .manualAlone } }
             
             
             
            Section { ruleDoor("Import Rule Set", symbol: .listBulletRectangle, identifier: "configuration.library.rules.add.rule-set") { showsRuleSetImport = true } }
        } label: {
            Image(systemName: ClashSymbol.plusCircle.rawValue).clashToolbarGlyph()
        }
        .disabled(busy || model.isUpdatingNodeLibrary)
        .accessibilityLabel(ClashCopy.key("Add Rules"))
        .accessibilityIdentifier("configuration.library.rules.add")
    }

    private func ruleDoor(_ title: String, symbol: ClashSymbol, identifier: String,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(ClashCopy.key(title), systemImage: symbol.name)
        }
        .accessibilityIdentifier(identifier)
    }

    private func loadCollections(force: Bool = false) async {
        if !force, let cached = browseCache?.wrappedValue, cached.matches(library, contentEpoch: model.libraryContentEpoch) {
            collections = cached.entries
            return
        }
        guard let store = model.configurationLibraryStore else { return }
        do {
            let snapshot = library
             
             
            let epoch = model.libraryContentEpoch
            let loaded = try await Task.detached { try ConfigurationCollectionContentBridge.catalog(store, snapshot: snapshot) }.value
            await loadRunningCatalog()
            guard !Task.isCancelled, library.generation == snapshot.generation else { return }
            collections = loaded
            if model.libraryContentEpoch == epoch {
                browseCache?.wrappedValue = .init(generation: snapshot.generation, entries: loaded, contentEpoch: epoch)
            }
        }
        catch { errorMessage = ClashErrorCopy.message(error, locale: locale) }
    }
     
     
    private var ruleRun: ProfilesViewModel.CollectionUpdateRun? { model.ruleCollectionUpdate }
     
     
    private func runSummary(_ run: ProfilesViewModel.CollectionUpdateRun) -> String {
        ConfigurationLibraryRunSummary.line(ClashCopy.string("Rule sets updated", locale: locale), updated: run.updated,
            total: run.total, unconfirmed: run.unconfirmed, appliesOnConnect: run.appliesOnConnect, locale: locale)
    }
    private func updateAllRuleSets() {
        errorMessage = nil
        schemeRefreshResult = nil
        model.updateRuleCollections(visibleCollections, scripts: .silent, locale: locale)
    }
     
    @State private var refreshingSchemeIDs: Set<String> = []
     
     
     
     
     
     
     
    private func refreshScheme(_ id: String) {
        guard refreshingSchemeIDs.insert(id).inserted else { return }
        Task { @MainActor in
            defer { refreshingSchemeIDs.remove(id) }
             
             
             
             
             
            var done = false
            while !done {
                while busy, let running = busyTask { await running.value }
                await model.pageLibraryWrite {
                    guard !busy else { return }
                    done = true
                     
                    guard let scheme = library.effectiveRuleScheme(id) else { return }
                     
                     
                     
                    schemeRefreshResult = nil
                    perform {
                        let outcome = try await model.refreshConfigurationSource(scheme.sourceID); try await reload()
                         
                         
                         
                        if let run = ruleRun, run.finished { model.acknowledgeRuleCollectionUpdate(run.id) }
                         
                        schemeRefreshResult = (outcome == .nothingNew ? ClashFeedbackCopy.upToDate(scheme.label)
                                                                      : ClashFeedbackCopy.updated(scheme.label)).resolved(locale: locale)
                    }
                    await busyTask?.value
                }
            }
        }
    }
    @State private var busyTask: Task<Void, Never>?
    @State private var schemeRefreshResult: String?
    private var dismissSchemeRefresh: (() -> Void)? {
        schemeRefreshResult == nil ? nil : { schemeRefreshResult = nil }
    }
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; errorMessage = nil
        busyTask = Task { @MainActor in defer { busy = false }; do { try await operation() } catch { errorMessage = ClashErrorCopy.message(error, locale: locale) } }
    }
}

struct ConfigurationTowerRuleCustomizationAdapter: View {
    @Environment(\.locale) private var locale
    let model: ProfilesViewModel
    let scheme: ConfigurationRuleScheme
    @State var library: ConfigurationLibrarySnapshot
    var pushed = false
     
     
     
    var profileID: String? = nil
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
     
    var focus: ClashTowerRuleFocus = .all
     
    var savesEachChange = false
     
     
    var single: ClashTowerSingleObject? = nil
     
    var opening: ClashTowerListOpening = .list
    private struct LoadedEditor: Sendable {
        let draft: ConfigurationRuleDraft
        let resetDocument: String
        let ruleSetKeys: Set<String>
    }
    @State private var initial: LoadedEditor?
    @State private var identityDraft: ConfigurationRuleDraft?
     
     
    @State private var targetNodes = RuleTargetNodeSource()
    @State private var errorMessage: String?
     
     
    @State private var catalog: ProfilesViewModel.SyntaxCatalog?
    var body: some View {
        ClashFeatureNavigationContainer(ownsNavigationContainer: !pushed) {
            Group {
                if let initial {
                     
                     
                     
                    ClashTowerRuleCustomizationView(draft: initial.draft, localSets: library.localRuleSets ?? [],
                        resetDocument: initial.resetDocument, palette: .clashProduct, pushed: pushed, ruleSetKeys: initial.ruleSetKeys,
                        save: save, download: { try await ConfigurationTowerRuleReader.ruleSet($0) },
                        saveLocal: { value in apply(try await model.saveConfigurationLocalRuleSet(value, generation: library.generation)); return (try await reloadDraft(), library.localRuleSets ?? []) },
                        deleteLocal: { id in apply(try await model.saveConfigurationLocalRuleSet(nil, deleting: id, generation: library.generation)); return (try await reloadDraft(), library.localRuleSets ?? []) },
                         
                         
                        copy: { draft, name in
                            apply(try await model.copyConfigurationRuleScheme(draft: draft, label: name, generation: library.generation))
                        }, close: close,
                        manualEditor: { draft, accept in AnyView(ConfigurationTowerManualRuleEditor(draft: draft, accept: accept)) },
                         
                         
                        ruleEditor: { request, accept in
                             
                             
                             
                             
                             
                             
                             
                            AnyView(RuleBuilderAdapter(raw: request.editing?.raw ?? "", options: RulePolicyOptions(shared: request.options),
                                showsPersonalMetadata: request.showsTarget, showsTarget: request.showsTarget,
                                createGroup: request.createGroup,
                                enabled: request.editing?.isEnabled ?? true, comment: request.editing?.note ?? "",
                                pageTitle: request.editing == nil ? "Add Rule" : "Rule",
                                saveDetails: { raw, enabled, comment in accept(raw, enabled, comment) },
                                save: { raw in accept(raw, true, "") }))
                        },
                        nodeCandidates: { await loadNodeCandidates() }, focus: focus, savesEachChange: savesEachChange,
                        groupTypes: catalog?.groupTypes.map(\.name) ?? [],
                         
                         
                        groupPage: configurationGroupPage, single: single, opening: opening,
                        rename: ClashTowerRuleCustomizationView.canRenameFromEditor(scheme, openedFromConfiguration: profileID != nil, focus: focus)
                            ? { id, name in apply(try await model.renameConfigurationRuleScheme(id, label: name)) } : nil)
                        .environment(\.clashGroupIconImages, ClashProxiesDisplayPreferences.load().groupIconImages)
                        .environment(\.clashRuleTargetSearch, targetSearchHook)
                        .environment(\.clashGroupPatternCheck, Self.groupPatternCheck)
                } else if let errorMessage {
                    Form { Text(verbatim: errorMessage); Button("Retry") { Task { await load() } }; Button("Close", action: close) }
                } else { ClashOpeningProgress() }
            }.task {
                if catalog == nil { catalog = try? await ProfilesViewModel.loadSyntaxCatalog() }
                if initial == nil { await load() }
            }
        }
    }
     
     
     
    private var configurationGroupPage: ((ClashTowerGroupPageRequest) -> AnyView)? {
        #if os(iOS)
        guard savesEachChange else { return nil }
        let catalog = catalog
        return { request in AnyView(ConfigurationSchemeGroupPage(request: request, catalog: catalog)) }
        #else
        return nil
        #endif
    }
     
     
     
    static let groupPatternCheck = ClashGroupPatternCheck { key, pattern in
        await Task.detached(priority: .userInitiated) {
            try? ConfigurationTextEditing.checkGroupPattern(key: key, pattern: pattern)
        }.value
    }
    private func apply(_ value: ConfigurationLibrarySnapshot) { library = value; changed(value) }
     
     
     
     
     
     
     
    private func loadNodeCandidates() async -> [ConfigurationRuleTargetCandidates.Section] {
        guard let store = model.configurationLibraryStore else { return [] }
        let snapshot = library
        let locale = locale
        let referenced = Self.referencedNames(in: initial?.draft.currentDocument())
        var sections = await Task.detached(priority: .userInitiated) {
            let candidates = try? ConfigurationRuleTargetCandidates.make(groups: [], snapshot: snapshot, providers: true,
                                                                          naming: { $0.displayLabel(locale: locale) },
                                                                          payload: { try store.payload($0) })
            return candidates?.sections.filter { $0.kind == .source || $0.kind == .providers } ?? []
        }.value
         
         
         
         
         
         
         
         
         
        let known = Set(sections.filter { $0.kind == .source }.flatMap(\.names))
        let search = targetSearch
        let existing = await search.existing(referenced.filter { !known.contains($0) })
         
        let groups = Set(initial?.draft.groups.map(\.name) ?? [])
        sections += await search.sections(query: "", current: referenced.filter { existing.contains($0) && !known.contains($0) })
            .compactMap { section in
                let names = section.names.filter { !groups.contains($0) }
                return names.isEmpty ? nil : .init(id: section.id, kind: section.kind, sourceLabel: section.sourceLabel, names: names)
            }
        return sections
    }

     
    private var targetSearch: ConfigurationRuleTargetSearch {
        let nodes = targetNodes
        let profileID = profileID
        return ConfigurationRuleTargetSearch(configurationID: profileID, defaults: DelayTestSettings.appGroupDefaults,
                                             locale: locale) { await nodes.source(profileID: profileID) }
    }

    private var targetSearchHook: ClashRuleTargetSearchHook {
        let search = targetSearch
        return ClashRuleTargetSearchHook(sections: { query, current in await search.sections(query: query, current: current) },
                                         recordUse: { search.recordUse($0) })
    }

     
     
    static func referencedNames(in document: OrderedJSON?) -> [String] {
        guard let document else { return [] }
        var names: [String] = []
        if case .array(let groups)? = document.topLevelValue("proxy-groups") {
            for group in groups {
                if case .array(let members)? = group.topLevelValue("proxies") {
                    names += members.compactMap { if case .string(let name) = $0 { return name }; return nil }
                }
            }
        }
        if case .array(let rules)? = document.topLevelValue("rules") {
            for rule in rules {
                if case .string(let raw) = rule, let target = ClashStructuredRule.parse(raw)?.target, !target.isEmpty {
                    names.append(target)
                }
            }
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
    private func load() async {
        do {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let selected = scheme
            let loaded = try await Task.detached {
                _ = ConfigurationRuleCatalog.builtIn
                let draft = try ConfigurationRuleDraft(scheme: selected, payload: store.ruleSchemePayload(selected.id))
                let currentBase = try selected.baseSchemeID.flatMap { ConfigurationBuiltins.isNative($0) ? try ConfigurationBuiltins.source(for: $0)?.documentJSON : nil }
                return LoadedEditor(draft: draft, resetDocument: currentBase ?? selected.initialDocumentJSON ?? draft.originalDocument.serialized(),
                    ruleSetKeys: draft.referencedRuleSets)
            }.value
            identityDraft = loaded.draft; initial = loaded
        } catch { errorMessage = ClashErrorCopy.message(error, locale: locale) }
    }
    private func reloadDraft() async throws -> ConfigurationRuleDraft {
        let id = identityDraft?.schemeID ?? scheme.id
         
        let exact = profileID == nil ? nil : library.rules.first { $0.id == id } ?? ConfigurationBuiltins.schemes.first { $0.id == id }
        guard let store = model.configurationLibraryStore, let current = exact ?? library.effectiveRuleScheme(id) else { throw ConfigurationLibraryError.unreadable }
        let previous = identityDraft
        let result = try await Task.detached {
            let loaded = try ConfigurationRuleDraft(scheme: current, payload: store.ruleSchemePayload(current.id))
            return previous.map { loaded.preservingIdentity(from: $0) } ?? loaded
        }.value
        identityDraft = result
        return result
    }
    private func save(_ draft: ConfigurationRuleDraft) async throws -> ConfigurationRuleDraft {
        apply(try await model.saveConfigurationRuleCustomization(draft, profileID: profileID, generation: library.generation))
         
         
         
        let own = profileID.flatMap { id in library.recipes.first { $0.id == id }?.ruleSchemeID }
            .flatMap { id in library.rules.first { $0.id == id } ?? ConfigurationBuiltins.schemes.first { $0.id == id } }
        guard let store = model.configurationLibraryStore,
              let current = own ?? library.ruleSchemeAfterSavingCustomization(draft.schemeID) else { throw ConfigurationLibraryError.unreadable }
        let result = try await Task.detached {
            try ConfigurationRuleDraft(scheme: current, payload: store.ruleSchemePayload(current.id)).preservingIdentity(from: draft)
        }.value
        identityDraft = result
        return result
    }
}

private struct ConfigurationTowerRuleImportAdapter: View {
    @Environment(\.locale) private var locale
    @ObservedObject var model: ProfilesViewModel
    let generation: UInt64
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
    @State private var link = ""
    @State private var name = ""
    @State private var busy = false
    @State private var errorMessage: String?
    var body: some View {
        ClashFeatureNavigationContainer {
            Form {
                Section("Rule URL") { TextField("URL", text: $link, prompt: Text("https://…")).accessibilityIdentifier("configuration.rule.import.url").autocorrectionDisabled().textInputAutocapitalization(.never) }
                Section("Name (Optional)") { TextField("Leave blank to use the file name", text: $name).accessibilityIdentifier("configuration.rule.import.name") }
                Section { Text("Import Clash YAML rule schemes.").font(.footnote).foregroundStyle(.secondary) }
                if let errorMessage { Text(verbatim: errorMessage).foregroundStyle(.orange) }
            }.disabled(busy).clashPageTitle("Import Rules")
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: close).disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button(ClashCopy.key(busy ? "Downloading…" : "Import")) { submit() }.disabled(busy || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
             
            .clashRegistersDeparture(isDirty: !link.isEmpty || !name.isEmpty, isBusy: busy,
                whySaveIsBlocked: { link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .copy("Enter a valid link.") : nil },
                save: { submit($0) }, discard: { link = ""; name = "" })
        }
    }
    private func submit(_ completion: @escaping (Bool) -> Void = { _ in }) {
        guard !busy, !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { completion(false); return }
        busy = true; errorMessage = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let payload = try await model.fetchConfigurationSource(url: ConfigurationTowerRuleReader.normalizedURL(link), label: name)
                changed(try await model.addConfigurationRuleScheme(payload, generation: generation)); completion(true); close()
            } catch { errorMessage = ClashErrorCopy.message(error, locale: locale); completion(false) }
        }
    }
}

private struct ConfigurationChainChoice: Identifiable, Sendable {
    let hop: ConfigurationNodeChain.Hop
    let sourceLabel: String
    var id: String { hop.source.id + "/" + hop.nodeName }
}

 
private final class ConfigurationChainEditorDraft: ObservableObject {
    var isDirty: Bool { !name.isEmpty || entry != nil || exit != nil }
    @Published var name: String
    @Published var entry: ConfigurationNodeChain.Hop?
    @Published var exit: ConfigurationNodeChain.Hop?
    init(existing: ConfigurationSourceRecord? = nil) {
        name = existing?.label ?? ""; entry = existing?.nodeChain?.entry; exit = existing?.nodeChain?.exit
    }
}

private struct ConfigurationChainEditor: View {
    @Environment(\.locale) private var locale
    @Environment(\.clashInsideProductModalPresentation) private var insideProductModal
    let model: ProfilesViewModel
    let existing: ConfigurationSourceRecord?
    let accept: (ConfigurationSourcePayload) async throws -> Void
    let close: () -> Void
    @StateObject private var draft: ConfigurationChainEditorDraft
    private let tabHeader: (() -> AnyView)?
    private let onSaved: (() -> Void)?
    private let isFirstConfigurationStep: Bool
    private var name: String { get { draft.name } nonmutating set { draft.name = newValue } }
    private var entry: ConfigurationNodeChain.Hop? { get { draft.entry } nonmutating set { draft.entry = newValue } }
    private var exit: ConfigurationNodeChain.Hop? { get { draft.exit } nonmutating set { draft.exit = newValue } }
    @State private var choices: [ConfigurationChainChoice] = []
    @State private var loadedGeneration: UInt64?
    @State private var pickingEntry: Bool?
    @State private var search = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var confirmsDiscard = false

    init(model: ProfilesViewModel, existing: ConfigurationSourceRecord?, draft: ConfigurationChainEditorDraft? = nil,
        tabHeader: (() -> AnyView)? = nil, isFirstConfigurationStep: Bool = false, accept: @escaping (ConfigurationSourcePayload) async throws -> Void, close: @escaping () -> Void, onSaved: (() -> Void)? = nil) {
        self.tabHeader = tabHeader; self.onSaved = onSaved
        self.isFirstConfigurationStep = isFirstConfigurationStep
        self.model = model; self.existing = existing; self.accept = accept; self.close = close
        _draft = StateObject(wrappedValue: draft ?? ConfigurationChainEditorDraft(existing: existing))
    }
    private var dirty: Bool { name != (existing?.label ?? "") || entry != existing?.nodeChain?.entry || exit != existing?.nodeChain?.exit }
    private var canSave: Bool { !busy && loadedGeneration != nil && entry != nil && exit != nil && entry != exit && dirty }
    var body: some View {
        ClashFeatureNavigationContainer {
            Form {
            Section { TextField("Name", text: $draft.name, prompt: Text("Entry → Exit")).accessibilityIdentifier("configuration.chain.name") }
            Section {
                Text("This Device")
                hopRow("Entry Node", hop: entry) { pickingEntry = true; search = "" }
                hopRow("Exit Node", hop: exit) { pickingEntry = false; search = "" }
                Text("Destination Website")
            } header: { Text("Connection Order") }
            if loadedGeneration == nil { ProgressView("Loading Nodes") }
            else if choices.isEmpty { Text("Add nodes to Node Library first.").foregroundStyle(.secondary) }
            if let errorMessage { Section { Text(verbatim: errorMessage).foregroundStyle(.orange) } }
            }
             
             
             
             
             
            .clashPinnedTopBar {
                if let tabHeader { tabHeader().disabled(busy) }
            }
            .disabled(busy)
            .clashPageTitle(.copy(isFirstConfigurationStep ? "Create Nodes 1/2" : (tabHeader != nil ? ClashConfigurationAddition.nodes.title : (existing == nil ? "Add Proxy Chain" : "Edit Proxy Chain"))))
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { confirmsDiscard = true } else { close() } }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button { save() } label: { ClashActionProgressLabel(.copy(isFirstConfigurationStep ? "Next" : "Done"), isBusy: busy) }.disabled(!canSave) }
            }
            .clashProductModalRoot(title: .copy(isFirstConfigurationStep ? "Create Nodes 1/2" : (tabHeader != nil ? ClashConfigurationAddition.nodes.title : "Proxy Chain")))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if insideProductModal { ClashModalActionBar(primaryTitle: isFirstConfigurationStep ? "Next" : "Done", primaryDisabled: !canSave, isBusy: busy) { save() } }
            }
            .interactiveDismissDisabled(dirty || busy)
             
            .clashRegistersDeparture(isDirty: dirty, isBusy: busy, whySaveIsBlocked: {
                if loadedGeneration == nil { return ClashDepartureSaveAnswer.incomplete }
                if entry == nil || exit == nil { return .copy("Choose an entry node and an exit node.") }
                return entry == exit ? .copy("The entry and exit nodes must be different.") : nil
            }, save: { save($0) }, discard: {
                name = existing?.label ?? ""; entry = existing?.nodeChain?.entry; exit = existing?.nodeChain?.exit
            })
            .clashUnsavedChangesAlert(isPresented: $confirmsDiscard, message: "This proxy chain has unsaved changes.",
                isBusy: busy, saveDisabled: !canSave, save: { save() }, discard: {
                    name = existing?.label ?? ""; entry = existing?.nodeChain?.entry; exit = existing?.nodeChain?.exit
                    close()
                })
            .task { if loadedGeneration == nil { await load() } }
            .clashProductModal(isPresented: Binding(get: { pickingEntry != nil }, set: { if !$0 { pickingEntry = nil } }), role: .page) {
                ClashFeatureNavigationContainer {
                    List {
                        ForEach(choices.filter { search.isEmpty || $0.hop.nodeName.localizedCaseInsensitiveContains(search) || $0.sourceLabel.localizedCaseInsensitiveContains(search) }) { choice in
                            Button {
                                if pickingEntry == true { entry = choice.hop } else { exit = choice.hop }
                                pickingEntry = nil
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(verbatim: choice.hop.nodeName).foregroundStyle(.primary)
                                        Text(verbatim: choice.sourceLabel).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: (pickingEntry == true ? entry : exit) == choice.hop ? ClashSymbol.checkmarkCircleFill.name : ClashSymbol.circle.name)
                                        .foregroundStyle(.tint)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    .clashProductModalSearchable(text: $search)
                    .clashPageTitle(pickingEntry == true ? "Entry Node" : "Exit Node")
                    .clashToolbarUnlessInPanel {
                        ToolbarItem(placement: .cancellationAction) { ClashSheetCloseButton(dismiss: { pickingEntry = nil }) }
                    }
                }
            }
        }
    }
    private func hopRow(_ title: String, hop: ConfigurationNodeChain.Hop?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: ClashSymbol.arrowDown.name).foregroundStyle(.secondary)
                Text(ClashCopy.key(title))
                Spacer()
                if let hop { Text(verbatim: hop.nodeName).lineLimit(1).truncationMode(.middle) }
                else { Text("Choose Node") }
                Image(systemName: ClashSymbol.infoCircle.name).foregroundStyle(Color.blue)
            }
        }.disabled(loadedGeneration == nil || choices.isEmpty)
    }
    private func load() async {
        do {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let locale = locale
            let loaded = try await Task.detached {
                let snapshot = try store.snapshot()
                var choices: [ConfigurationChainChoice] = []
                for record in snapshot.availableSources where record.suppliesNodes && record.nodeChain == nil {
                    let payload = try store.payload(.init(record))
                    guard case .array(let nodes) = try OrderedJSON.parse(payload.documentJSON).topLevelValue("proxies") else { continue }
                    for node in nodes {
                        guard case .string(let name) = node.topLevelValue("name") else { continue }
                        if case .string(let dialer) = node.topLevelValue("dialer-proxy"), !dialer.isEmpty, dialer != "DIRECT" { continue }
                        choices.append(.init(hop: .init(source: .init(record), nodeName: name),
                                             sourceLabel: record.displayLabel(locale: locale)))
                    }
                }
                return (choices, snapshot.generation)
            }.value
            choices = loaded.0; loadedGeneration = loaded.1
        } catch { errorMessage = ClashErrorCopy.message(error, locale: locale) }
    }
    private func save(_ completion: @escaping (Bool) -> Void = { _ in }) {
        guard canSave, let entry, let exit, let generation = loadedGeneration else { completion(false); return }
        busy = true; errorMessage = nil
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = existing ?? ConfigurationSourceRecord(label: "", origin: .customNodes)
        Task {
            defer { busy = false }
            do {
                guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                let payload = try await Task.detached {
                    guard try store.snapshot().generation == generation else { throw ConfigurationLibraryError.staleGeneration }
                    var record = record
                    record.label = label.isEmpty ? entry.nodeName + " → " + exit.nodeName : label
                    return try ConfigurationNodeChain.materialize(record: record, chain: .init(entry: entry, exit: exit), load: store.payload)
                }.value
                try await accept(payload); completion(true)
                name = existing?.label ?? ""; self.entry = existing?.nodeChain?.entry; self.exit = existing?.nodeChain?.exit
                (onSaved ?? close)()
            } catch { errorMessage = ClashErrorCopy.message(error, locale: locale); completion(false) }
        }
    }
}

private struct ConfigurationChainDetail: View {
    @Environment(\.locale) private var locale
    @Environment(\.clashFeedback) private var feedback
    let model: ProfilesViewModel
    let source: ConfigurationSourceRecord
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
    @State private var editing = false
    @State private var deleting = false
    @State private var busy = false
    @State private var errorMessage: String?
    private func chainHopLine(_ name: String) -> some View {
        HStack {
            Image(systemName: ClashSymbol.arrowDown.name).foregroundStyle(.secondary)
            Text(verbatim: name).lineLimit(1).truncationMode(.middle)
        }
    }
    var body: some View {
        ClashFeatureNavigationContainer {
            Form {
                if let chain = source.nodeChain {
                    Section {
                         
                         
                         
                        Text("This Device")
                        chainHopLine(chain.entry.nodeName)
                        chainHopLine(chain.exit.nodeName)
                        Text("Destination Website")
                    } header: { Text("Connection Order") }
                }
                Section { Button("Delete Proxy Chain", role: .destructive) { deleteChain() } }
                if let errorMessage { Text(verbatim: errorMessage).foregroundStyle(.orange) }
            }.disabled(busy)
            .clashPageTitle(ClashConfigurationSourceCopy.name(source), watchAs: "Proxy Chain")
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) { ClashSheetCloseButton(dismiss: close).disabled(busy) }
                ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true }.disabled(busy) }
            }
            .interactiveDismissDisabled(busy)
            .clashProductModal(isPresented: $editing, role: .page) {
                ConfigurationChainEditor(model: model, existing: source, accept: { payload in
                    changed(try await model.saveConfigurationChain(.init(source), replacement: payload))
                }, close: { editing = false })
            }
        }
    }
}

private struct ConfigurationNodeSourceEditor: View {
    @Environment(\.locale) private var locale
    let model: ProfilesViewModel
    let record: ConfigurationSourceRecord
    let changed: (ConfigurationLibrarySnapshot) -> Void
    @State private var yaml: String?
    @State private var version: ConfigurationSourceVersion?
    @State private var errorMessage: String?
    private var profile: Profile {
        .init(id: record.id, label: record.label, source: .clipboard, autoUpdate: false,
            updateIntervalHours: 0, subscriptionInfo: nil, selectedMap: [:], activeRevision: nil,
            order: 0, lastUpdatedAt: nil)
    }
    var body: some View {
        Group {
            if let yaml, let version {
                ProfileEditView(profile: profile, rawYAML: yaml, editorTitle: "Edit Nodes Source") { _, text, files, _ in
                    guard let text else { return }
                    guard files.isEmpty else { throw CocoaError(.featureUnsupported) }
                    changed(try await model.saveConfigurationNodeSource(version, yaml: text))
                }
            } else if let errorMessage {
                Form {
                    Text(verbatim: errorMessage).foregroundStyle(.orange)
                    Button("Retry") { Task { await load() } }
                    if ClashSheetSurface.coversOnThisSystem { ClashOpeningCancelButton() }
                }
            } else { ProfileEditorOpeningPlaceholder(identifier: "configuration.nodeSource.opening") }
        }.task { if yaml == nil { await load() } }
    }
    private func load() async {
        errorMessage = nil
        do {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let id = record.id
            let loaded = try await Task.detached {
                guard let current = try store.snapshot().sources.first(where: { $0.id == id }) else {
                    throw ConfigurationLibraryError.missingDependency(id)
                }
                let payload = try store.payload(.init(current))
                guard case .object(let entries) = try OrderedJSON.parse(payload.documentJSON) else {
                    throw ConfigurationLibraryError.unreadable
                }
                let nodes = OrderedJSON.object(entries.filter { ["proxies", "proxy-providers"].contains($0.key) })
                return (try ConfigTransforms.jsonToYAML(nodes.serialized()), ConfigurationSourceVersion(current))
            }.value
            yaml = loaded.0; version = loaded.1
        } catch { errorMessage = ClashErrorCopy.message(error, locale: locale) }
    }
}

 
private struct ConfigurationTowerManualRuleEditor: View {
    @Environment(\.locale) private var locale
    let draft: ConfigurationRuleDraft
    let accept: (ConfigurationRuleDraft) async throws -> Void
    @State private var source: String?
    @State private var errorMessage: String?
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()

     
     
    private var document: Profile {
        Profile(id: draft.schemeID, label: draft.label, source: .clipboard,
            autoUpdate: false, updateIntervalHours: 0, subscriptionInfo: nil,
            selectedMap: [:], activeRevision: nil, order: 0, lastUpdatedAt: nil)
    }
    var body: some View {
        Group {
            if let source {
                ProfileEditView(profile: document, rawYAML: source, editorTitle: "Edit Rules Source") { _, yaml, resources, _ in
                    guard let yaml else { return }
                     
                     
                    guard resources.isEmpty else { throw CocoaError(.featureUnsupported) }
                    let original = draft
                    let value = try await Task.detached(priority: .userInitiated) {
                        let root = try OrderedJSON.parse(ConfigTransforms.yamlToJSON(yaml))
                        if case .object(let entries) = root,
                           entries.contains(where: { !ConfigurationRuleDocument.keys.contains($0.key) }) {
                            throw NSError(domain: "ConfigurationRuleEditor", code: 1, userInfo: [
                                NSLocalizedDescriptionKey: ClashCopy.string("Only rules and policy groups belong here. Add nodes in Node Library.", locale: .current)])
                        }
                        var updated = original
                        try updated.replaceContents(root)
                        return updated
                    }.value
                    try await accept(value)
                }
            } else if let errorMessage {
                Form {
                    Text(verbatim: errorMessage).foregroundStyle(.orange)
                    Button("Retry") { Task { await load() } }
                    Button("Close") { dismiss.closeModalOrDismiss() }
                }
            } else {
                ProfileEditorOpeningPlaceholder(identifier: "configuration.manualRule.opening")
            }
        }
        .task { if source == nil { await load() } }
        .clashCapturesDismiss(dismiss)
    }
    private func load() async {
        errorMessage = nil
        let snapshot = draft
        do {
            source = try await Task.detached(priority: .userInitiated) {
                try ConfigTransforms.jsonToYAML(snapshot.currentDocument().serialized())
            }.value
        } catch { errorMessage = ClashErrorCopy.message(error, locale: locale) }
    }
}

enum ConfigurationTowerRuleReader {
    static func normalizedURL(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: value) else { return value }
        if parts.host == "github.com" {
            let path = parts.path.split(separator: "/").map(String.init)
            if path.count > 4, path[2] == "blob" {
                parts.host = "raw.githubusercontent.com"; parts.path = "/" + ([path[0], path[1]] + Array(path.dropFirst(3))).joined(separator: "/")
            }
        }
        return parts.string ?? value
    }
     
     
     
     
     
     
     
     
     
     
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TowerRuleSets", isDirectory: true)
        configuration.urlCache = URLCache(memoryCapacity: 4 << 20, diskCapacity: 32 << 20, directory: directory)
        return URLSession(configuration: configuration)
    }()

     
    private static let catalogLinks: Set<String> = Set(ConfigurationRuleCatalog.builtIn.entries.compactMap {
        URL(string: normalizedURL($0.sourceURLString))?.absoluteString
    })

     
     
     
     
    private actor Memo {
        private var lists: [String: ConfigurationRuleSetContent] = [:]
        private var order: [String] = []
        func value(for key: String) -> ConfigurationRuleSetContent? { lists[key] }
        func store(_ value: ConfigurationRuleSetContent, for key: String) {
            if lists[key] == nil { order.append(key) }
            lists[key] = value
            while order.count > 64, let oldest = order.first { order.removeFirst(); lists[oldest] = nil }
        }
    }
    private static let memo = Memo()

     
     
     
    static func ruleSet(in data: Data) async -> ClashRuleSetSniff.Found? {
        guard let sniffed = await Task.detached(priority: .userInitiated, operation: { ClashRuleSetSniff.ruleSet(in: data) }).value
        else { return nil }
        let found = await resolvedBehavior(sniffed, data: data)
        return found.behavior == nil ? nil : found
    }

     
     
     
     
    static func resolvedBehavior(_ found: ClashRuleSetSniff.Found, data: Data) async -> ClashRuleSetSniff.Found {
        guard found.behavior == nil, found.format == "mrs" else { return found }
        return await Task.detached(priority: .userInitiated) {
            guard AppCoreSetup.ensureForReaders() else { return found }
            for behavior in ["domain", "ipcidr"] {
                var count = 0
                var error: NSError?
                if AppCore.inspectProvider("rule", behavior, "mrs", data, &count, &error), error == nil {
                    return ClashRuleSetSniff.Found(format: "mrs", behavior: behavior)
                }
            }
            return found
        }.value
    }

    static func rules(_ input: String, session: URLSession = session) async throws -> [String] {
        try await ruleSet(input, session: session).rules
    }

     
     
     
     
     
    static func ruleSet(_ input: String, session: URLSession = session) async throws -> ConfigurationRuleSetContent {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: normalizedURL(text)), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            let catalog = catalogLinks.contains(url.absoluteString)
            if catalog, let known = await memo.value(for: url.absoluteString) { return known }
            let request = URLRequest(url: url, cachePolicy: catalog ? .returnCacheDataElseLoad : .useProtocolCachePolicy, timeoutInterval: 30)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count <= 32 * 1024 * 1024 else { throw ConfigurationLibraryError.unreadable }
             
            if data.starts(with: [0x28, 0xB5, 0x2F, 0xFD]) {
                let read = try await mrs(data, url: url.absoluteString)
                if catalog { await memo.store(read, for: url.absoluteString) }
                return read
            }
            guard let decoded = String(data: data, encoding: .utf8) else { throw ConfigurationLibraryError.unreadable }
            text = decoded
        }
        let raw = text
        let key = URL(string: normalizedURL(input.trimmingCharacters(in: .whitespacesAndNewlines)))
            .flatMap { ["https", "http"].contains($0.scheme?.lowercased() ?? "") ? $0.absoluteString : nil }
        let parsed = try await Task.detached { () -> ConfigurationRuleSetContent in
            let lines: [String]
             
             
             
             
             
             
            var format: String?
            let asWritten = raw.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
             
             
             
             
             
             
             
            let isYAMLPayload = raw.split(whereSeparator: \.isNewline).contains { $0.hasPrefix("payload:") }
            if isYAMLPayload {
                let object = try OrderedJSON.parse(ConfigTransforms.yamlToJSON(raw))
                guard case .array(let values) = object.topLevelValue("payload") else { throw ConfigurationLibraryError.missingRules }
                lines = try values.map { guard case .string(let value) = $0 else { throw ConfigurationLibraryError.missingRules }; return value }
                let items = asWritten.dropFirst()
                format = asWritten.first == "payload:" && items.count == lines.count && items.allSatisfy { $0.hasPrefix("- ") }
                    ? "yaml" : nil
            } else {
                 
                 
                lines = raw.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("//") }
                    .map { line -> String in
                        var value = Substring(line)
                        if value.hasPrefix("- ") { value = value.dropFirst(2).drop(while: { $0 == " " }) }
                        if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
                            value = value.dropFirst().dropLast()
                        }
                        return String(value)
                    }
                    .filter { !$0.isEmpty }
                format = asWritten == lines ? "text" : nil
            }
            guard !lines.isEmpty else { throw ConfigurationLibraryError.missingRules }
             
             
             
             
             
            let bytes = Data(raw.utf8)
            let behavior = ClashRuleSetSniff.ruleSet(in: bytes)?.behavior ?? "classical"
             
            var coreCount: Int?
            if behavior == "classical" {
                let document = OrderedJSON.object([
                    ("rule-providers", .object([("check", .object([("type", .string("inline")), ("behavior", .string("classical")), ("payload", .array(lines.map(OrderedJSON.string)))]))])),
                    ("rules", .array([.string("RULE-SET,check,DIRECT"), .string("MATCH,DIRECT")]))
                ])
                try ConfigTransforms.validateSource(document.serialized())
            } else {
                 
                 
                func counted(_ data: Data, _ format: String) -> Int {
                    var count = 0
                    var error: NSError?
                    guard AppCoreSetup.ensureForReaders(), AppCore.inspectProvider("rule", behavior, format, data, &count, &error),
                          error == nil else { return 0 }
                    return count
                }
                 
                 
                 
                 
                 
                 
                if let written = format {
                    let count = counted(bytes, written)
                    if count == 0 { format = nil } else if count != lines.count { coreCount = count }
                }
                if format == nil, counted(Data(lines.joined(separator: "\n").utf8), "text") == 0 {
                    throw ConfigurationLibraryError.missingRules
                }
            }
             
             
            if raw.utf8.count > 16 * 1024 * 1024 { format = nil }
            return ConfigurationRuleSetContent(rules: lines, link: key.flatMap { url in
                format.map { .init(url: url, format: $0, behavior: behavior, count: coreCount) }
            }, behavior: behavior == "classical" ? nil : behavior)
        }.value
        if let key, catalogLinks.contains(key) { await memo.store(parsed, for: key) }
        return parsed
    }

     
     
     
     
    static func mrs(_ data: Data, url: String) async throws -> ConfigurationRuleSetContent {
        guard data.count <= 16 * 1024 * 1024 else { throw ConfigurationLibraryError.unreadable }
         
         
        let found = await Task.detached(priority: .userInitiated) { () -> (behavior: String, count: Int)? in
            guard AppCoreSetup.ensureForReaders() else { return nil }
            for behavior in ["domain", "ipcidr"] {
                var count = 0
                var error: NSError?
                if AppCore.inspectProvider("rule", behavior, "mrs", data, &count, &error), error == nil, count > 0 {
                    return (behavior, count)
                }
            }
            return nil
        }.value
        guard let found else { throw ConfigurationLibraryError.unreadable }
        return ConfigurationRuleSetContent(rules: [], link: .init(url: url, format: "mrs", behavior: found.behavior, count: found.count),
                                           behavior: found.behavior)
    }
}

private struct ConfigurationRuleEditingAdapter: View {
    @ObservedObject var model: ProfilesViewModel
    @Environment(\.locale) private var locale
    let scheme: ConfigurationRuleScheme
    let generation: UInt64
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
    @State private var initialDraft: ConfigurationRuleDraft?
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        ClashFeatureNavigationContainer {
            Group {
                if let initialDraft {
                    ClashConfigurationRuleEditingView(draft: initialDraft, isBusy: busy, error: errorMessage,
                        save: { draft, completion in
                            guard !busy else { completion(false); return }
                            busy = true; errorMessage = nil
                            Task {
                                defer { busy = false }
                                do { changed(try await model.saveConfigurationRuleDraft(draft, generation: generation)); completion(true) }
                                catch { errorMessage = ClashErrorCopy.message(error, locale: locale); completion(false) }
                            }
                        }, close: close, ruleEditor: { raw, draft, accept, delete in
                            AnyView(ClashFeatureNavigationContainer {
                                RuleBuilderAdapter(raw: raw, options: ConfigurationGroupEditorBridge.ruleOptions(draft), showsPersonalMetadata: true,
                                    delete: delete, enabled: draft.isEnabled(raw), comment: draft.note(for: raw),
                                    saveDetails: { raw, enabled, comment in accept(raw, enabled, comment) },
                                    save: { raw in accept(raw, true, "") })
                            })
                        }, groupEditor: { draft, groupID, accept in
                            AnyView(ConfigurationGroupEditorBridge.editor(draft: draft, groupID: groupID, schemeID: scheme.id, locale: locale, accept: accept))
                        })
                } else if let errorMessage {
                    Form { Text(verbatim: errorMessage); Button("Close", action: close) }
                } else { ProgressView() }
            }
            .task {
                guard initialDraft == nil else { return }
                do {
                    guard let library = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                    let payload = try await Task.detached {
                        guard try library.snapshot().generation == generation else { throw ConfigurationLibraryError.staleGeneration }
                        return try library.ruleSchemePayload(scheme.id)
                    }.value
                    initialDraft = try await Task.detached {
                        try ConfigurationRuleDraft(scheme: scheme, payload: payload)
                    }.value
                } catch { errorMessage = ClashErrorCopy.message(error, locale: locale) }
            }
        }
    }
}

private struct ConfigurationNewRuleAdapter: View {
    @ObservedObject var model: ProfilesViewModel
    let library: ConfigurationLibrarySnapshot
    var tabHeader: ((Bool) -> AnyView)? = nil
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var options: RulePolicyOptions = .empty
    @Environment(\.locale) private var locale

     
     
     
     
     
    var body: some View {
        ClashFeatureNavigationContainer {
            RuleBuilderAdapter(raw: "", options: options, showsPersonalMetadata: true,
                pageTitle: ClashConfigurationAddition.rules.title,
                saveDetails: { raw, enabled, note in submit(raw, enabled: enabled, note: note) },
                save: { raw in submit(raw, enabled: true, note: "") })
            .disabled(busy)
            .safeAreaInset(edge: .top, spacing: 0) { if let tabHeader { tabHeader(false).disabled(busy) } }
            .alert("Cannot Save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") {}
            } message: {
                Text(verbatim: errorMessage ?? "")
            }
            .task { await loadOptions() }
        }
    }

    private var activeRecipe: ConfigurationRecipe? {
        guard let id = model.activeProfileID else { return nil }
        return library.recipes.first { $0.id == id }
    }

    private var plan: QuickRulePlan {
        QuickRulePlan.make(activeSchemeID: activeRecipe?.ruleSchemeID, schemes: library.rules,
            myRulesLabel: ClashCopy.string("My Rules", locale: locale))
    }

     
     
    private func loadOptions() async {
        guard let store = model.configurationLibraryStore else { return }
        let schemeID: String
        switch plan { case .reuse(let id): schemeID = id; case .copy(let base): schemeID = base }
        guard let scheme = library.effectiveRuleScheme(schemeID) else { return }
        let loaded: RulePolicyOptions? = await Task.detached(priority: .userInitiated) {
            guard let payload = try? store.ruleSchemePayload(schemeID),
                  let draft = try? ConfigurationRuleDraft(scheme: scheme, payload: payload) else { return nil }
            return ConfigurationGroupEditorBridge.ruleOptions(draft)
        }.value
        if let loaded { options = loaded }
    }

    private func submit(_ raw: String, enabled: Bool, note: String) {
        guard !busy else { return }
        busy = true; errorMessage = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await create(raw, enabled: enabled, note: note); close() }
            catch { errorMessage = ClashErrorCopy.message(error, locale: locale) }
        }
    }

    private func create(_ raw: String, enabled: Bool, note: String) async throws {
        guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        var snapshot = library
        let myRules = ClashCopy.string("My Rules", locale: locale)
        let schemeID: String
        switch plan {
        case .reuse(let id):
            schemeID = id
        case .copy(let base):
            let before = Set(snapshot.rules.map(\.id))
            snapshot = try await model.copyConfigurationRuleScheme(base, label: myRules, generation: snapshot.generation)
            guard let made = snapshot.rules.first(where: { !before.contains($0.id) }) else { throw ConfigurationLibraryError.invalidIdentifier }
            schemeID = made.id
        }
        guard let scheme = snapshot.rules.first(where: { $0.id == schemeID }) else { throw ConfigurationLibraryError.missingDependency(schemeID) }
        var draft = try await Task.detached(priority: .userInitiated) {
            try ConfigurationRuleDraft(scheme: scheme, payload: try store.ruleSchemePayload(schemeID))
        }.value
        draft.insertRuleFirst(raw)
        if let first = draft.rows.first { draft.setRule(raw, enabled: enabled, note: note, rowID: first.id) }
        snapshot = try await model.saveConfigurationRuleDraft(draft, generation: snapshot.generation)
        if let active = model.activeProfileID,
           let recipe = snapshot.recipes.first(where: { $0.id == active }),
           recipe.ruleSchemeID != schemeID {
            var edit = ConfigurationCreationAdapter.editingDraft(recipe: recipe,
                label: model.profiles.first(where: { $0.id == active })?.label ?? recipe.label)
            edit.selectedRuleID = schemeID
             
             
             
             
            edit.step = .rules
            try await model.editConfiguration(edit, id: active, generation: snapshot.generation)
            snapshot = try await Task.detached { try store.snapshot() }.value
        }
        changed(snapshot)
    }
}

private struct ConfigurationRuleGroupsAdapter: View {
    @Environment(\.locale) private var locale
    @ObservedObject var model: ProfilesViewModel
    let scheme: ConfigurationRuleScheme
    let close: () -> Void
    @State private var groups: [ConfigurationRuleGroupSnapshot] = []
    @State private var loading = true
    @State private var errorMessage: String?
    var body: some View {
        ClashFeatureNavigationContainer {
            ClashConfigurationRuleGroupsView(groups: groups, isLoading: loading, error: errorMessage,
                reload: { Task { await load() } }, close: close)
                .task { await load() }
        }
    }
    private func load() async {
        loading = true; errorMessage = nil
        defer { loading = false }
        do {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let id = scheme.id
            groups = try await Task.detached {
                let payload = try store.ruleSchemePayload(id)
                return try ConfigurationRuleGroupSnapshot.read(OrderedJSON.parse(payload.documentJSON))
            }.value
        } catch { errorMessage = ClashErrorCopy.message(error, locale: locale) }
    }
}

 
enum ConfigurationGroupEditorBridge {
    static func applying(_ edited: CustomProxyGroup, to original: OrderedJSON) throws -> OrderedJSON {
        let baseline = CustomProxyGroup(json: original.foundationValue as? [String: Any] ?? [:]).json
        let updated = edited.json
        var result = original
        for key in Set(baseline.keys).union(updated.keys).sorted() {
            if let before = baseline[key] as? NSObject, let after = updated[key] as? NSObject, before.isEqual(after) { continue }
            if let value = updated[key] {
                let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
                result = result.settingTopLevel(key, to: try OrderedJSON.parse(String(decoding: data, as: UTF8.self)))
            } else { result = result.removingTopLevel(key) }
        }
        return result
    }
    static func ruleOptions(_ draft: ConfigurationRuleDraft) -> RulePolicyOptions {
        let root = (try? draft.document().foundationValue as? [String: Any]) ?? [:]
        return RulePolicyOptions(groups: draft.groups.map { ($0.name, $0.type) }, proxies: [],
            ruleSets: draft.ruleSetNames,
            hiddenGroups: Set(draft.groups.filter(\.isHidden).map(\.name)),
            subRuleNames: (root["sub-rules"] as? [String: Any]).map { $0.keys.sorted() }, ruleSetsAreKnown: true)
    }
    @MainActor static func editor(draft: ConfigurationRuleDraft, groupID: UUID?, schemeID: String, locale: Locale, accept: @escaping (OrderedJSON) -> Void) -> some View {
        let original = groupID.flatMap { id in draft.groups.first { $0.id == id }?.document }
            ?? .object([("name", .string("")), ("type", .string("select")), ("include-all", .scalar("true"))])
        let group = CustomProxyGroup(json: original.foundationValue as? [String: Any] ?? [:])
        let root = draft.currentDocument().foundationValue as? [String: Any] ?? [:]
        let nodes = (root["proxies"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        let otherNames = Set(draft.groups.filter { $0.id != groupID }.map(\.name))
        return CustomProxyGroupEditor(group: group, existingNames: otherNames, profileProxyNames: nodes,
            validationContext: .init(nodeNames: Set(nodes), groupNames: otherNames,
                providerNames: Set((root["proxy-providers"] as? [String: Any] ?? [:]).keys), siblingGroupNames: otherNames),
            validateChange: { edited in
                do {
                    var candidate = draft
                    try candidate.setGroup(applying(edited, to: original), groupID: groupID)
                    return nil
                } catch { return ClashConfigurationRuleGroupCopy.message(error, locale: locale) }
            }, draftKey: CustomProxyGroupEditor.draftKey(scope: "scheme:\(schemeID)", groupName: group.name),
            save: { edited in
                 
                if let value = try? applying(edited, to: original) { accept(value) }
            })
    }
}

 
private struct ConfigurationDocumentBrowserAdapter: View {
    @Environment(\.locale) private var locale
    @Environment(\.clashFeedback) private var feedback
    enum Kind { case nodes, rules }
    @ObservedObject var model: ProfilesViewModel
    let sourceID: String
    let title: String
    var schemeID: String? = nil
    let kind: Kind
    var embedded = false
    var canEditNodes = false
    var changed: (ConfigurationLibrarySnapshot) -> Void = { _ in }
    var manage: (() -> Void)? = nil
    let close: () -> Void
    @State private var sections: [ClashConfigurationReadSection] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var payload: ConfigurationSourcePayload?
    @State private var editingIndex: Int?
    @State private var editingNode: ProxyNodeRecord?
    @State private var inspectedNode: ProxyNodeRecord?
    @State private var nodeDensity = ClashProxiesRowDensity.from(ClashProxiesDisplayPreferences.load())
    @State private var adding = false
    @State private var deletingIndex: Int?
    @State private var busy = false
    @State private var consumers: [String] = []
    var body: some View {
        ConfigurationLibraryNavigation(embedded: embedded) {
            Group {
                if let editingNode, let index = editingIndex, let payload {
                    ProxyNodeDetailsView(record: editingNode, retest: {}, saveNode: { _, json in
                        let updated = try await model.saveConfigurationCustomNode(.init(payload.record), nodeJSON: json, index: index)
                        changed(updated)
                    }, showsTesting: false, onDone: {
                        self.editingNode = nil; editingIndex = nil
                        Task { await load() }
                    }, commitTitle: "Save")
                    .environment(\.clashProductModalDismiss, {
                        self.editingNode = nil; editingIndex = nil
                    })
                    .safeAreaInset(edge: .bottom) {
                        Button("Delete Node", role: .destructive) { remove(index) }.padding()
                    }
                } else {
                    ClashConfigurationContentsView(title: .verbatim(title), sections: sections,
                        loading: loading, error: errorMessage, reload: { Task { await load() } }, close: close,
                        showsClose: !embedded, openNode: kind == .nodes ? openNode : nil,
                        deleteNode: canEditNodes ? { remove($0) } : nil,
                        addNode: canEditNodes ? { adding = true } : nil, isBusy: busy, manage: manage, nodeDensity: nodeDensity)
                        .environment(\.clashProductModalDismiss, close)
                }
            }
            .task { await load() }
            .clashProductModal(item: $inspectedNode, role: .page) { node in
                ProxyNodeDetailSheet(nodeName: node.name, yaml: nil, providersDir: nil,
                    suppliedDetails: node.protocolDetails)
            }
            .clashProductModal(isPresented: $adding, role: .page) {
                ConfigurationNodeSourceAdapter { imported in
                    guard let payload,
                          case .array(let nodes) = try OrderedJSON.parse(imported.documentJSON).topLevelValue("proxies"),
                          nodes.count == 1 else { throw ConfigurationLibraryError.unreadable }
                    let updated = try await model.saveConfigurationCustomNode(.init(payload.record), nodeJSON: nodes[0].serialized(), index: nil)
                    changed(updated)
                    await load()
                }
            }
            .disabled(busy)
            .interactiveDismissDisabled(busy)
        }
    }
    private func openNode(_ index: Int) {
        if canEditNodes { edit(index); return }
        guard let json = sections.flatMap(\.rows).first(where: { $0.nodeIndex == index })?.content,
              let node = CustomNodesView.record(fromNodeJSON: json) else {
            errorMessage = ClashErrorCopy.message(ConfigurationLibraryError.unreadable, locale: locale)
            return
        }
        inspectedNode = node
    }
    private func edit(_ index: Int) {
        do {
            guard let payload,
                  case .array(let nodes) = try OrderedJSON.parse(payload.documentJSON).topLevelValue("proxies"),
                  nodes.indices.contains(index),
                  let node = CustomNodesView.record(fromNodeJSON: nodes[index].serialized()) else { throw ConfigurationLibraryError.unreadable }
            editingNode = node; editingIndex = index
        } catch { errorMessage = ClashErrorCopy.message(error, locale: locale) }
    }
    private func remove(_ index: Int) {
        guard let payload, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                 
                let title = sections.flatMap(\.rows).first(where: { $0.nodeIndex == index })?.title
                    ?? ClashCopy.string("Node", locale: .current)
                let nodeJSON: String? = {
                    guard case .array(let nodes)? = try? OrderedJSON.parse(payload.documentJSON).topLevelValue("proxies"),
                          nodes.indices.contains(index) else { return nil }
                    return nodes[index].serialized()
                }()
                let updated = try await model.deleteConfigurationCustomNode(.init(payload.record), index: index)
                changed(updated)
                editingNode = nil; editingIndex = nil; deletingIndex = nil
                await load()
                if let nodeJSON, let record = updated.sources.first(where: { $0.id == payload.record.id }) {
                    let model = model, changed = changed, feedback = feedback
                    feedback?.show(.success(title: ClashFeedbackCopy.deleted(title), action: .undo,
                                            accessibilityIdentifier: "feedback.library.delete"),
                                   operation: "library.delete",
                                   perform: {
                        Task { @MainActor in
                            do {
                                changed(try await model.insertConfigurationCustomNode(.init(record), nodeJSON: nodeJSON, at: index))
                                 
                                 
                                await load()
                                feedback?.show(.success(title: ClashFeedbackCopy.restored(title),
                                                        accessibilityIdentifier: "feedback.library.delete"), operation: "library.delete")
                            } catch {
                                feedback?.show(.error(title: ClashFeedbackCopy.couldNotUndo, message: ClashErrorCopy.text(error),
                                                      accessibilityIdentifier: "feedback.library.delete"), operation: "library.delete")
                            }
                        }
                    })
                }
            } catch {
                 
                 
                editingNode = nil; editingIndex = nil; deletingIndex = nil
                errorMessage = ClashErrorCopy.message(error, locale: locale)
            }
        }
    }
    private func load() async {
        loading = true; errorMessage = nil
        defer { loading = false }
        do {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let id = sourceID, scheme = schemeID, nodes = kind == .nodes
            let loaded = try await Task.detached {
                let snapshot = try store.snapshot()
                let payload: ConfigurationSourcePayload
                if let scheme { payload = try store.ruleSchemePayload(scheme) }
                else {
                    guard let source = snapshot.sources.first(where: { $0.id == id }) else { throw ConfigurationLibraryError.missingDependency(id) }
                    payload = try store.payload(.init(source))
                }
                let document = try OrderedJSON.parse(payload.documentJSON)
                var result: [ClashConfigurationReadSection] = []
                if nodes {
                    if case .array(let values) = document.topLevelValue("proxies") {
                        result.append(.init(title: "Nodes", rows: values.enumerated().map { index, node in
                            let name = node.topLevelValue("name")?.foundationValue as? String ?? String(index + 1)
                            let type = node.topLevelValue("type")?.foundationValue as? String ?? ""
                            return .init(title: name, subtitle: type, content: node.serialized(), nodeIndex: index)
                        }))
                    }
                } else {
                    if case .array(let rules) = document.topLevelValue("rules") {
                        result.append(.init(title: "Rules", rows: rules.map { .init(title: $0.foundationValue as? String ?? $0.serialized()) }))
                    }
                    if case .object(let entries) = document.topLevelValue("sub-rules") {
                        result.append(.init(title: "Sub-rules", rows: entries.map { .init(title: $0.key, content: $0.value.serialized()) }))
                    }
                }
                let key = nodes ? "proxy-providers" : "rule-providers"
                let collections = ConfigurationCollection.read(sourceID: id, document: document, kind: nodes ? .nodes : .rules)
                if !nodes && !collections.isEmpty {
                    result.append(.init(title: nodes ? "Node Collections" : "Rule Collections", rows: collections.map {
                        .init(title: $0.name, collection: $0)
                    }))
                }
                let users = snapshot.recipes.filter { $0.sources.contains(where: { $0.id == id }) || $0.ruleSource.id == id }.map(\.label)
                return (result, payload, users)
            }.value
            sections = loaded.0; payload = loaded.1; consumers = loaded.2
        } catch { errorMessage = ClashErrorCopy.message(error, locale: locale) }
    }
}

private struct ConfigurationLibraryNavigation<Content: View>: View {
    let embedded: Bool
    @ViewBuilder var content: () -> Content
    var body: some View {
        if embedded { content() }
        else { ClashFeatureNavigationContainer { content() } }
    }
}


struct ConfigurationNodeScopeAdapter: View {
    @Environment(\.locale) private var locale
    @ObservedObject var model: ProfilesViewModel
    let source: ConfigurationSourceRecord
    let staged: ConfigurationSourcePayload?
    let initial: ConfigurationNodeScope?
    let save: (ConfigurationNodeScope?) -> Void
    let close: () -> Void
    @State private var collections: [ConfigurationCollection]?
    @State private var nodes: [ClashConfigurationSelectableNode] = []
    @State private var error: String?
    var body: some View {
        ClashFeatureNavigationContainer {
            Group {
                if let collections {
                    ClashConfigurationNodeScopeView(source: source, collections: collections, nodes: nodes, initial: initial, save: save, close: close)
                } else if let error {
                    VStack(spacing: ClashTheme.Spacing.row) {
                        Text(verbatim: error).foregroundStyle(.red)
                        if ClashSheetSurface.coversOnThisSystem {
                            Button { close() } label: { Text(clash: .copy("Cancel")) }.buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                else { ClashOpeningProgress() }
            }.task {
                do {
                    let store = model.configurationLibraryStore
                    let result = try await Task.detached {
                        let payload: ConfigurationSourcePayload
                        if let staged { payload = staged }
                        else {
                            guard let store else { throw ConfigurationLibraryError.unreadable }
                            payload = try store.payload(.init(source))
                        }
                        let document = try OrderedJSON.parse(payload.documentJSON)
                        let nodes: [ClashConfigurationSelectableNode]
                        if case .array(let entries) = document.topLevelValue("proxies") {
                            nodes = entries.compactMap { node in
                                guard let name = node.topLevelValue("name")?.foundationValue as? String else { return nil }
                                return .init(name: name, type: node.topLevelValue("type")?.foundationValue as? String ?? "")
                            }
                        } else { nodes = [] }
                        return (ConfigurationCollection.read(sourceID: source.id, document: document, kind: .nodes), nodes)
                    }.value
                    nodes = result.1
                    collections = result.0
                } catch { self.error = ClashErrorCopy.message(error, locale: locale) }
            }
        }
    }
}

private func updateIssueMessage(_ library: ConfigurationLibrarySnapshot, sourceID: String? = nil, locale: Locale) -> String? {
    let issues = (library.updateIssues ?? []).filter { sourceID == nil || $0.sourceID == sourceID }
    guard !issues.isEmpty else { return nil }
    let names = issues.map { issue in
        library.recipes.first { $0.id == issue.itemID }?.label
            ?? library.sources.first { $0.id == issue.itemID }.map { $0.displayLabel(locale: locale) } ?? issue.itemID
    }
    return ClashCopy.string("Some references are unavailable. Previous versions were kept:", locale: locale)
        + " " + names.joined(separator: ", ")
}

 
 
 
struct ConfigurationCollectionIdentitySections: View {
    let entry: ConfigurationCollectionEntry
    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var fieldCopy

    var body: some View {
        Group {
            Section("Source") { Text(clash: ClashConfigurationSourceCopy.name(entry.source)) }
            Section {
                HStack { Text("Name"); Spacer(); Text(verbatim: entry.collection.name) }
                 
                if entry.id.kind == .nodes {
                    HStack {
                        Text("Type"); Spacer()
                        Text(verbatim: ConfigurationTypeWords.Collections(copy: fieldCopy, locale: locale).type(of: entry.collection))
                    }
                }
                if let location = entry.collection.location { Text(verbatim: location).textSelection(.enabled) }
            }
        }.accessibilityIdentifier("configuration.collection.settings")
    }
}

struct ConfigurationCollectionAdapter: View {
    let model: ProfilesViewModel
    let entry: ConfigurationCollectionEntry
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
    init(model: ProfilesViewModel, entry: ConfigurationCollectionEntry,
         changed: @escaping (ConfigurationLibrarySnapshot) -> Void, close: @escaping () -> Void) {
        self.model = model; self.entry = entry; self.changed = changed; self.close = close
        _running = StateObject(wrappedValue: RunningProvidersReader(container: { [model] in model.appGroupContainer }))
    }
     
     
     
     
    @StateObject private var running: RunningProvidersReader
    @Environment(\.locale) private var locale
    @State private var page = ConfigurationCollectionContentBridge.Page()
    @State private var rows: [ClashConfigurationReadRow] = []
    @State private var query = ""
    @State private var loading = false
    @State private var error: String?
    @State private var management = false
    @State private var editor = false
    @State private var deleting = false
    @State private var inspectedNode: ProxyNodeRecord?
    @State private var requestID = UUID()
     
     
     
    @State private var updating = false
     
     
    @State private var updatePhase: String?
    @State private var updateFailures: [String] = []
     
     
     
    @State private var runHasThis = false
     
     
     
    @State private var shownCopyDate: Date?
     
     
    private var runningCount: Int? {
        guard let catalog = running.current?.catalog else { return nil }
        var bare = entry
        bare.memberCount = nil
        return ConfigurationCollectionContentBridge.withRunningCounts([bare], catalog: catalog).first?.memberCount
    }
     
     
     
     
     
     
     
    @State private var updateWord: String?
    private var status: String {
        var parts = [entry.source.displayLabel(locale: locale)]
        if let updateWord { parts.insert(ClashCopy.string(updateWord, locale: locale), at: 0) }
        if let count = page.count {
            parts.append(ClashCopy.format(entry.id.kind == .nodes ? "%@ nodes" : "%@ rules", locale: locale, String(count)))
        }
         
         
         
         
        if let runningCount, runningCount != page.count {
            parts.append(ClashCopy.format(entry.id.kind == .nodes ? "%@ nodes in the configuration in use" : "%@ rules in the configuration in use",
                                          locale: locale, String(runningCount)))
        }
        if let date = page.updatedAt {
            parts.append(ClashCopy.format("Updated on %@", locale: locale,
                                          date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))))
        }
        if let message = page.statusMessage(locale: locale) { parts.append(message) }
        return parts.joined(separator: " · ")
    }
    private var shownError: String? {
        let lines = (error.map { [$0] } ?? []) + updateFailures
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
    var body: some View {
        ClashFeatureNavigationContainer {
            ClashConfigurationCollectionContentsView(title: entry.collection.name, rows: rows, query: $query,
                status: status, error: shownError, loading: loading,
                refresh: entry.collection.type == "http" ? { Task { await update() } } : nil,
                next: page.nextOffset.map { offset in { Task { await load(offset: offset) } } },
                openNode: { index in
                    guard page.nodes.indices.contains(index) else { return }
                    inspectedNode = CustomNodesView.record(fromNodeJSON: page.nodes[index])
                }, manage: { management = true }, close: close,
                details: entry.id.kind == .rules ? { AnyView(identitySections) } : nil,
                actions: entry.id.kind == .rules ? { AnyView(managementActions) } : nil,
                 
                 
                subscriptionUsage: ConfigurationCollectionContentBridge.shownUsage(page, of: entry, running: running.current),
                isUpdating: updating || runHasThis, updateProgress: updatePhase)
                .task(id: query) {
                    if !query.isEmpty { try? await Task.sleep(nanoseconds: 180_000_000) }
                    guard !Task.isCancelled else { return }
                    await load()
                }
                .clashOnScreen { running.follow($0) }
                .onReceive(NotificationCenter.default.publisher(for: .clashActiveConfigurationRepublished)) { _ in
                    Task { await running.reload() }
                }
                 
                 
                 
                .onReceive(model.$ruleCollectionUpdate.map { [id = entry.id] run in
                    run.map { !$0.finished && $0.updating.contains(id) } ?? false
                }.removeDuplicates()) { inFlight in
                    let wasInFlight = runHasThis
                    runHasThis = inFlight
                    if wasInFlight && !inFlight { Task { await reloadIfTheCopyChanged(); await running.reload() } }
                }
                .clashProductModal(item: $inspectedNode, role: .page) { node in
                    ProxyNodeDetailSheet(nodeName: node.name, yaml: nil, providersDir: nil, suppliedDetails: node.protocolDetails)
                }
                .clashProductModal(isPresented: $management, role: .page) {
                    ClashFeatureNavigationContainer {
                        Form { identitySections; managementActions }
                            .clashPageTitle(.verbatim(entry.collection.name), watchAs: "Collection Management")
                            .clashToolbarUnlessInPanel {
                                ToolbarItem(placement: .cancellationAction) { ClashSheetCloseButton(dismiss: { management = false }) }
                            }
                    }
                }
        }
    }
    private var identitySections: some View { ConfigurationCollectionIdentitySections(entry: entry) }
    private var managementActions: some View {
        Group {
            if entry.id.kind == .rules {
                Section {
                    Button("Add Rule Scheme") {
                        Task {
                            do {
                                guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                                let updated = try await Task.detached {
                                    try store.addRuleScheme(collection: entry, expectedGeneration: store.snapshot().generation)
                                }.value
                                changed(updated); close()
                            } catch { self.error = ClashErrorCopy.message(error, locale: locale); management = false }
                        }
                    }
                }
            }
             
             
             
            Section { Button("Edit Source") { editor = true }.buttonStyle(.plain).foregroundStyle(.primary) }
                .disabled(!entry.definitionIsEditable)
            Section { Button("Delete Collection", role: .destructive) { deleting = true } }
                .disabled(!entry.definitionIsEditable)
        }
        .clashDeleteConfirmation(entry.collection.name, isPresented: $deleting,
            actionTitle: .copy("Delete Collection"),
            message: .copy("Remove this collection from its source. Profiles that reference it must choose another collection first."),
            identifier: "configuration.collection.delete.confirm") {
                Task {
                    do { changed(try await model.saveConfigurationCollection(entry, definitionJSON: nil)); close() }
                    catch { self.error = ClashErrorCopy.message(error, locale: locale); management = false }
                }
        }
        .clashProductModal(isPresented: $editor, role: .page) {
            let profile = Profile(id: entry.source.id, label: entry.collection.name, source: .clipboard,
                autoUpdate: false, updateIntervalHours: 0, subscriptionInfo: nil, selectedMap: [:], activeRevision: nil, order: 0, lastUpdatedAt: nil)
            ProfileEditView(profile: profile, rawYAML: entry.collection.definition.serialized(), editorTitle: "Edit Source") { _, text, files, _ in
                guard let text, files.isEmpty else { throw ConfigurationLibraryError.unreadable }
                let json = try ConfigTransforms.yamlToJSON(text)
                changed(try await model.saveConfigurationCollection(entry, definitionJSON: json))
                close()
            }
        }
    }
     
     
     
     
     
     
     
    private func update() async {
        guard !updating else { return }
        updating = true; updateFailures = []; updateWord = nil
        defer { updating = false; updatePhase = nil }
        if model.isUpdatingNodeLibrary || model.isUpdatingRuleCollections {
            updatePhase = ClashCopy.string("Waiting for the current update to finish…", locale: locale)
        }
         
         
         
        await model.pageLibraryWrite {
            updatePhase = nil
            do {
                guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                let source = try await Task.detached { try store.payload(.init(entry.source)) }.value
                var libraryFailure: Error?
                var refreshed = ConfigurationCollectionContentBridge.CollectionRefresh.downloaded
                do { refreshed = try await ConfigurationCollectionContentBridge.refresh(entry, source: source, inUse: model.providerCatalogInUse()) }
                catch { libraryFailure = error }
                if libraryFailure == nil, refreshed == .downloaded { await load() }
                updatePhase = ClashCopy.string("Applying to the configuration in use…", locale: locale)
                 
                 
                 
                 
                 
                let take: ProfilesViewModel.CollectionTake
                switch (libraryFailure, refreshed) {
                case (nil, .downloaded):
                    take = await model.takeUpdatedCollections([entry], scripts: .surfaced, locale: locale)
                case (nil, .coreOwned):
                    take = await model.takeUpdatedCollections([], coreOwned: [entry], scripts: .surfaced, locale: locale)
                default:
                    take = await model.takeUpdatedCollections([], failed: [entry], scripts: .surfaced, locale: locale)
                }
                updateFailures = ProfilesViewModel.joiningReasons(
                    libraryFailure.map { [ClashErrorCopy.message($0, locale: locale)] } ?? [], take.failures)
                updateWord = ProfilesViewModel.CollectionTake.word(
                    for: entry.id, take: take, libraryCopyIn: libraryFailure == nil && refreshed == .downloaded)
            } catch {
                 
                updateFailures = [ClashErrorCopy.message(error, locale: locale)]
            }
        }
        await running.reload()
    }
     
     
     
     
     
     
     
    private func reloadIfTheCopyChanged() async {
        let entry = self.entry
        let copy = await Task.detached { ConfigurationCollectionContentBridge.libraryCopyDate(of: entry) }.value
        guard copy != shownCopyDate else { return }
        await load()
    }
    private func load(offset: Int = 0) async {
        let token = UUID(); requestID = token; loading = true; error = nil
        defer { if requestID == token { loading = false } }
        do {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let source = try await Task.detached { try store.payload(.init(entry.source)) }.value
            let search = query
            let loaded = try await Task.detached {
                 
                 
                 
                let copyDate = ConfigurationCollectionContentBridge.libraryCopyDate(of: entry)
                let page = try ConfigurationCollectionContentBridge.page(entry, source: source, query: search, offset: offset)
                let rows: [ClashConfigurationReadRow]
                if entry.id.kind == .nodes {
                    rows = page.nodes.enumerated().map { index, json in
                        let node = try? OrderedJSON.parse(json)
                        return .init(title: node?.topLevelValue("name")?.foundationValue as? String ?? "", subtitle: node?.topLevelValue("type")?.foundationValue as? String, nodeIndex: index)
                    }
                } else { rows = page.lines.map { .init(title: $0) } }
                return (page, rows, copyDate)
            }.value
            guard requestID == token, !Task.isCancelled else { return }
            if offset == 0 {
                page = loaded.0
                rows = loaded.1
                shownCopyDate = loaded.2
            } else {
                 
                 
                let base = page.nodes.count
                var next = loaded.0
                next.nodes = page.nodes + loaded.0.nodes
                page = next
                rows += loaded.1.map { row in
                    row.nodeIndex.map { .init(title: row.title, subtitle: row.subtitle, nodeIndex: base + $0) } ?? row
                }
            }
        } catch {
            guard requestID == token else { return }
            self.error = ClashErrorCopy.message(error, locale: locale)
        }
    }
}

 
 
 
struct ConfigurationLinkIsARuleSet: LocalizedError {
    let found: ClashRuleSetSniff.Found
    let link: String
    let underlying: Error
    var errorDescription: String? { underlying.localizedDescription }
}

 
 
struct ConfigurationRuleSetPrefill: Equatable {
    var name = ""
    var link = ""
    var behavior = "domain"
    var format = "yaml"
    var fileName: String?
    var fileData: Data?

     
     
     
     
    static func local(label: String, fileName: String, data: Data) async -> Self? {
        guard let found = await ConfigurationTowerRuleReader.ruleSet(in: data) else { return nil }
        return local(label: label, fileName: fileName, data: data, found: found)
    }

    static func local(label: String, fileName: String, data: Data, found: ClashRuleSetSniff.Found) -> Self {
        let name = ClashRuleSetSniff.name(typed: label, fileName: fileName)
        return Self(name: name, behavior: found.behavior ?? "domain", format: found.format,
                    fileName: ClashRuleSetSniff.fileName(fileName, found: found),
                    fileData: data)
    }

     
    static func link(_ link: String, found: ClashRuleSetSniff.Found, label: String) -> Self {
        let typed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self(name: typed.isEmpty ? ClashRuleSetSniff.linkStem(link) : typed, link: link,
                    behavior: found.behavior ?? "domain", format: found.format)
    }
}

private struct ConfigurationCollectionImportAdapter: View {
    @Environment(\.locale) private var locale
    let model: ProfilesViewModel
    let library: ConfigurationLibrarySnapshot
    var tabHeader: ((Bool) -> AnyView)? = nil
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
    @State private var name: String
    @State private var link: String
    @State private var behavior: String
    @State private var format: String
    @State private var fileData: Data?
    @State private var fileName: String?

     
     
    init(model: ProfilesViewModel, library: ConfigurationLibrarySnapshot, tabHeader: ((Bool) -> AnyView)? = nil,
         changed: @escaping (ConfigurationLibrarySnapshot) -> Void, close: @escaping () -> Void,
         initial: ConfigurationRuleSetPrefill? = nil) {
        self.model = model; self.library = library; self.tabHeader = tabHeader; self.changed = changed; self.close = close
        _name = State(initialValue: initial?.name ?? "")
        _link = State(initialValue: initial?.link ?? "")
        _behavior = State(initialValue: initial?.behavior ?? "domain")
        _format = State(initialValue: initial?.format ?? "yaml")
        _fileData = State(initialValue: initial?.fileData)
        _fileName = State(initialValue: initial?.fileName)
    }
    @State private var pickingFile = false
    @State private var busy = false
    @State private var error: String?
    private var dirty: Bool { !name.isEmpty || !link.isEmpty || fileData != nil }
    private var missingRequired: Bool { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (fileData == nil && link.isEmpty) }
    @Environment(\.clashInsideProductModalPresentation) private var insideProductModal
    var body: some View {
        ClashFeatureNavigationContainer {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("configuration.rules.import.name")
                    TextField("URL", text: $link).autocorrectionDisabled().textInputAutocapitalization(.never)
                        .disabled(fileData != nil)
                        .accessibilityIdentifier("configuration.rules.import.url")
                    Button { pickingFile = true } label: {
                         
                        if let fileName { Text(verbatim: fileName) } else { Text("Choose File") }
                    }.buttonStyle(.plain).foregroundStyle(.primary)
                    if fileData != nil { Button("Remove File") { fileData = nil; fileName = nil } }
                }
                Section {
                    Picker("Rule Type", selection: $behavior) {
                        Text("Domain").tag("domain"); Text("IP CIDR").tag("ipcidr"); Text("Classical").tag("classical")
                    }
                    .accessibilityIdentifier("configuration.rules.import.behavior")
                    Picker("Format", selection: $format) {
                        Text("YAML").tag("yaml"); Text("Text").tag("text")
                        if behavior != "classical" { Text("MRS").tag("mrs") }
                    }
                    .accessibilityIdentifier("configuration.rules.import.format")
                }
                if let error { Text(verbatim: error).foregroundStyle(.red) }
            }.disabled(busy)
                .onChange(of: behavior) { if $0 == "classical" && format == "mrs" { format = "yaml" } }
                .safeAreaInset(edge: .top, spacing: 0) { if let tabHeader { tabHeader(dirty).disabled(busy) } }
                .clashPageTitle(tabHeader == nil ? "Add Rule Set" : "Add Rules")
                .clashToolbarUnlessInPanel {
                    ToolbarItem(placement: .cancellationAction) { ClashSheetCloseButton(dismiss: close) }
                    ToolbarItem(placement: .confirmationAction) { Button { save() } label: { ClashActionProgressLabel(.copy("Save"), isBusy: busy) }.disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (fileData == nil && link.isEmpty)) }
                }
                .clashRegistersDeparture(isDirty: dirty, isBusy: busy, save: { save($0) }, discard: { name = ""; link = ""; fileData = nil; fileName = nil })
                 
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if insideProductModal {
                        ClashModalActionBar(primaryTitle: "Save", primaryDisabled: missingRequired, isBusy: busy, onPrimary: { save() })
                    }
                }
                .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.data]) { result in
                    do {
                        let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url)
                        fileData = data; fileName = url.lastPathComponent
                        if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
                         
                         
                         
                        if url.pathExtension.lowercased() == "mrs" { format = "mrs" }
                         
                         
                        let (formatAtPick, behaviorAtPick) = (format, behavior)
                        Task { @MainActor in
                            guard let found = await ConfigurationTowerRuleReader.ruleSet(in: data),
                                  fileData == data, format == formatAtPick, behavior == behaviorAtPick else { return }
                            format = found.format
                            if let detected = found.behavior { behavior = detected }
                        }
                    } catch { self.error = ClashErrorCopy.message(error, locale: locale) }
                }
        }
    }
    private func save(_ completion: @escaping (Bool) -> Void = { _ in }) {
        guard !busy else { completion(false); return }; busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                let (name, behavior, format, link) = (name, behavior, format, link)
                let file = fileName.flatMap { name in fileData.map { (name: name, data: $0) } }
                 
                let payload = try await Task.detached(priority: .userInitiated) {
                    try ProfilesViewModel.ruleSetSourcePayload(name: name, behavior: behavior, format: format,
                                                               link: file == nil ? link : nil, file: file)
                }.value
                changed(try await model.addConfigurationSource(payload, generation: library.generation)); completion(true); close()
            } catch { self.error = ClashErrorCopy.message(error, locale: locale); completion(false) }
        }
    }
}


 
extension ConfigurationCollectionContentBridge.Page {
     
     
    func statusMessage(locale: Locale) -> String? {
        let lines = notes.map { ClashCopy.string($0, locale: locale) } + issues
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

enum ConfigurationCompletionPreview {
    static func sections(draft: ConfigurationCreationDraft, library: ConfigurationLibraryStore,
                         generation: UInt64, nodes: Bool, locale: Locale = .current) throws -> [ClashConfigurationReadSection] {
        let prepared = try library.prepare(draft, profileID: "completion-preview", expectedGeneration: generation,
            resolveInput: ConfigurationCenterSourceBridge.boundInput)
        let document = prepared.composition.document
        if !nodes {
            func ruleRow(_ value: OrderedJSON) -> ClashConfigurationReadRow {
                let raw = value.foundationValue as? String ?? value.serialized()
                let parsed = ClashStructuredRule.parse(raw)
                return .init(title: raw, rule: .init(raw: raw, type: parsed?.action.rawValue ?? "RAW",
                    payload: parsed?.content ?? raw, target: parsed?.target ?? ""))
            }
            var sections: [ClashConfigurationReadSection] = []
            if case .array(let values) = document.topLevelValue("rules") {
                sections.append(.init(title: "Rules", rows: values.map(ruleRow)))
            }
            if case .object(let groups) = document.topLevelValue("sub-rules") {
                for group in groups {
                    if case .array(let values) = group.value {
                        sections.append(.init(title: .verbatim(group.key), rows: values.map(ruleRow)))
                    }
                }
            }
            return sections
        }
        var index = 0
        func row(_ node: OrderedJSON) -> ClashConfigurationReadRow {
            defer { index += 1 }
            return .init(title: node.topLevelValue("name")?.foundationValue as? String ?? String(index + 1),
                subtitle: node.topLevelValue("type")?.foundationValue as? String,
                content: node.serialized(), nodeIndex: index,
                chainedThrough: node.topLevelValue("dialer-proxy")?.foundationValue as? String)
        }
        var sections: [ClashConfigurationReadSection] = []
        if case .array(let values) = document.topLevelValue("proxies"), !values.isEmpty {
            sections.append(.init(title: "Nodes", rows: values.map(row)))
        }
        let references = prepared.recipe.sources
        let payloads = try references.map { reference in
            try prepared.payloads.first(where: { $0.record.id == reference.id }) ?? library.payload(reference)
        }
         
         
        let parents = try payloads.flatMap { payload -> [(ConfigurationSourcePayload, ConfigurationCollection, ConfigurationCollection)] in
            let original = ConfigurationCollection.read(sourceID: payload.record.id,
                document: try OrderedJSON.parse(payload.documentJSON), kind: .nodes)
            let bound = ConfigurationCollection.read(sourceID: payload.record.id,
                document: try ConfigurationCenterSourceBridge.boundInput(payload).document, kind: .nodes)
            return original.compactMap { collection in
                bound.first(where: { $0.name == collection.name }).map { (payload, collection, $0) }
            }
        }
        for collection in ConfigurationCollection.read(sourceID: "completion-preview", document: document, kind: .nodes) {
            guard let parent = parents.first(where: {
                $0.2.type == collection.type && (collection.type == "inline"
                    ? $0.2.definition.topLevelValue("payload") == collection.definition.topLevelValue("payload")
                    : $0.2.location == collection.location)
            }) else {
                sections.append(.init(title: .verbatim(collection.name), rows: [.init(title: collection.name + " · " + ClashCopy.string("Not Loaded", locale: locale))]))
                continue
            }
            do {
                let page = try ConfigurationCollectionContentBridge.page(.init(source: parent.0.record, collection: parent.1),
                    source: parent.0, query: "")
                var rows = try page.nodes.map { row(try OrderedJSON.parse($0)) }
                if let message = page.statusMessage(locale: locale) { rows.append(.init(title: collection.name + " · " + message)) }
                sections.append(.init(title: .verbatim(collection.name), rows: rows))
            } catch {
                sections.append(.init(title: .verbatim(collection.name), rows: [.init(title: ClashErrorCopy.message(error, locale: locale))]))
            }
        }
        return sections
    }
}


struct ConfigurationCompletionContentsAdapter: View {
    let draft: ConfigurationCreationDraft
    let library: ConfigurationLibraryStore?
    let generation: UInt64
    let nodes: Bool
    @State private var sections: [ClashConfigurationReadSection] = []
    @State private var loading = true
    @State private var failure: String?
    @State private var inspectedNode: ProxyNodeRecord?
    @Environment(\.locale) private var locale

    var body: some View {
        ClashConfigurationContentsView(title: .copy(nodes ? "Nodes" : "Rules"),
            sections: sections, loading: loading, error: failure, reload: { Task { await load() } },
            close: {}, showsClose: false, openNode: nodes ? inspect : nil,
            searchPrompt: nodes ? "Search Nodes" : "Search Rules", palette: .clashProduct)
        .task { await load() }
        .clashProductModal(item: $inspectedNode, role: .page) { node in
            ProxyNodeDetailSheet(nodeName: node.name, yaml: nil, providersDir: nil, suppliedDetails: node.protocolDetails)
        }
    }
    private func inspect(_ index: Int) {
        guard let json = sections.flatMap(\.rows).first(where: { $0.nodeIndex == index })?.content,
              let node = CustomNodesView.record(fromNodeJSON: json) else { return }
        inspectedNode = node
    }
    private func load() async {
        loading = true; failure = nil
        defer { loading = false }
        do {
            guard let library else { throw ConfigurationLibraryError.unreadable }
            let value = draft, revision = generation, showNodes = nodes
            let result = try await Task.detached(priority: .userInitiated) {
                try ConfigurationCompletionPreview.sections(draft: value, library: library, generation: revision, nodes: showNodes, locale: locale)
            }.value
            guard !Task.isCancelled else { return }
            sections = result
        } catch { failure = ClashErrorCopy.message(error, locale: locale) }
    }
}

extension ConfigurationCreationAdapter {
     
     
    static func editingDraft(recipe: ConfigurationRecipe, label: String, selectedRuleID: String? = nil) -> ConfigurationCreationDraft {
        var draft = ConfigurationCreationDraft()
        draft.selectedSourceIDs = recipe.sources.map(\.id)
        draft.nodeScopes = recipe.nodeScopes
        draft.selectedRuleID = selectedRuleID ?? recipe.ruleSchemeID
        draft.label = label
        draft.dnsMode = recipe.dnsMode ?? .system
        draft.nodeNameservers = recipe.nodeNameservers
        draft.customDNSJSON = recipe.customDNSJSON
        return draft
    }
}

 
 
 
 
 
enum QuickRulePlan: Equatable {
    case reuse(String)
    case copy(base: String)

    static func make(activeSchemeID: String?, schemes: [ConfigurationRuleScheme], myRulesLabel: String) -> QuickRulePlan {
         
         
         
        if let activeSchemeID, schemes.contains(where: { $0.id == activeSchemeID && $0.kind == .custom && $0.collectionKey == nil }) {
            return .reuse(activeSchemeID)
        }
        if let mine = schemes.first(where: { $0.kind == .custom && $0.collectionKey == nil && $0.label == myRulesLabel }) {
            return .reuse(mine.id)
        }
        return .copy(base: activeSchemeID ?? ConfigurationBuiltins.basicRuleID)
    }
}

 
 
 
@MainActor
enum ConfigurationLibraryUndo {
    static func offer(
        _ feedback: ClashFeedbackCenter?,
        name: String,
        deletion: (snapshot: ConfigurationLibrarySnapshot, removal: ConfigurationLibraryRemoval),
        model: ProfilesViewModel,
        changed: @escaping (ConfigurationLibrarySnapshot) -> Void
    ) {
        let committed = deletion.snapshot.generation
        feedback?.show(
            .success(title: ClashFeedbackCopy.deleted(name), action: .undo, accessibilityIdentifier: "feedback.library.delete"),
            operation: "library.delete",
            perform: { undo(feedback, name: name, removal: deletion.removal, committed: committed, model: model, changed: changed) }
        )
    }

     
     
     
     
    @MainActor
    private static func undo(_ feedback: ClashFeedbackCenter?, name: String, removal: ConfigurationLibraryRemoval,
                             committed: UInt64, model: ProfilesViewModel,
                             changed: @escaping (ConfigurationLibrarySnapshot) -> Void) {
        Task { @MainActor in
            var attempt = 0
            while true {
                do {
                    changed(try await model.restoreConfigurationLibraryRemoval(removal, expectedGeneration: committed))
                    feedback?.show(.success(title: ClashFeedbackCopy.restored(name), accessibilityIdentifier: "feedback.library.delete"),
                                   operation: "library.delete")
                    return
                } catch ConfigurationLibraryError.busy where attempt < 10 {
                    attempt += 1
                    try? await Task.sleep(nanoseconds: 300_000_000)
                } catch ConfigurationLibraryError.busy {
                    feedback?.show(.error(title: ClashFeedbackCopy.couldNotUndo, action: .undo,
                                          accessibilityIdentifier: "feedback.library.delete"),
                                   operation: "library.delete",
                                   perform: { undo(feedback, name: name, removal: removal, committed: committed,
                                                   model: model, changed: changed) })
                    return
                } catch {
                    feedback?.show(.error(title: ClashFeedbackCopy.couldNotUndo, message: ClashErrorCopy.text(error),
                                          accessibilityIdentifier: "feedback.library.delete"),
                                   operation: "library.delete")
                    return
                }
            }
        }
    }
}

extension ConfigurationChainDetail {
     
    fileprivate func deleteChain() {
        busy = true
        Task {
            defer { busy = false }
            do {
                guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                let generation = try await Task.detached { try store.snapshot().generation }.value
                let deletion = try await model.deleteConfigurationSourceRestorably(source.id, generation: generation)
                changed(deletion.snapshot)
                close()
                ConfigurationLibraryUndo.offer(feedback, name: source.displayLabel(locale: locale), deletion: deletion,
                                               model: model, changed: changed)
            } catch { errorMessage = ClashErrorCopy.message(error, locale: locale) }
        }
    }
}
