#if os(iOS)
import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 

 
 
@MainActor
final class ConfigurationEditorSession: ObservableObject {
    let profileID: String
    let model: ProfilesViewModel
    @Published private(set) var page: ProfilesViewModel.ConfigurationEditorPage? {
        didSet {
            running = page.map { page in page.ownLayer.map { page.document.mergingAsTheCoreMerges($0) } ?? page.document }
            layouts = [:]
        }
    }
     
     
    private var running: OrderedJSON?
    @Published private(set) var catalog: ProfilesViewModel.SyntaxCatalog? {
        didSet { layouts = [:] }
    }
     
     
     
     
     
    private var layouts: [String: ConfigurationSectionLayout] = [:]

     
    func layout(_ key: String, make: () -> ConfigurationSectionLayout) -> ConfigurationSectionLayout {
        if let made = layouts[key] { return made }
        let made = make()
        layouts[key] = made
        return made
    }
    @Published private(set) var isSaving = false
    @Published var failure: String?
     
     
     
    @Published var pendingEdits: [ConfigurationPageEdit]?
     
     
     
    @Published var refusal: Refusal?
     
    @Published var notice: ClashDisplayText?

    struct Refusal: Equatable {
        let sentence: String
        let coreWords: String?
        let editTheSourceInstead: Bool
    }

     
    let selections: GroupSelectionCarrying?
     
     
    private let catalogSource: @Sendable () async throws -> ProfilesViewModel.SyntaxCatalog

    init(profileID: String, model: ProfilesViewModel, selections: GroupSelectionCarrying? = nil,
         catalogSource: @escaping @Sendable () async throws -> ProfilesViewModel.SyntaxCatalog = {
             try await ProfilesViewModel.loadSyntaxCatalog()
         }) {
        self.profileID = profileID
        self.model = model
        self.selections = selections
        self.catalogSource = catalogSource
    }

    func reload() async {
         
         
         
         
        let loadingCatalog: Task<ProfilesViewModel.SyntaxCatalog?, Never>? = catalog == nil
            ? Task { [catalogSource] in try? await catalogSource() } : nil
        let loaded: ProfilesViewModel.ConfigurationEditorPage?
        do {
            loaded = try await model.loadConfigurationEditorPage(profileID: profileID)
        } catch is CancellationError {
            loaded = nil
        } catch {
            failure = error.localizedDescription
            loaded = nil
        }
        if let loadingCatalog {
            catalog = await loadingCatalog.value
            catalogUnavailable = catalog == nil
        }
        if let loaded { page = loaded }
    }

     
     
    @Published private(set) var catalogUnavailable = false

     
    var awaitsCatalog: Bool { catalog == nil && !catalogUnavailable }

     
    private var queuedEdits: [ConfigurationPageEdit] = []
     
     
    private var savingEdits: [ConfigurationPageEdit] = []

     
     
     
     
     
     
    func edit(_ edits: [ConfigurationPageEdit]) {
        guard !edits.isEmpty else { return }
        if isSaving {
            queuedEdits += edits
            return
        }
        if page?.ownLayer == nil, case .composed(_, .shared)? = page?.form {
             
             
            pendingEdits = (pendingEdits ?? []) + edits
            return
        }
        savingEdits = edits
        Task { await save(edits) }
    }

    func confirmPendingEdits() {
        guard let edits = pendingEdits else { return }
        pendingEdits = nil
        savingEdits = edits
        Task { await save(edits) }
    }

    private func save(_ edits: [ConfigurationPageEdit]) async {
         
         
        var readScheme: String?
        if page?.ownLayer == nil {
            guard case .composed(let scheme, _)? = page?.form else {
                savingEdits = []
                return
            }
            readScheme = scheme.id
        }
        await run { try await self.model.editConfigurationSettings(self.profileID, edits: edits, readScheme: readScheme) }
    }

     
    func setOwnDNSSwitch(_ on: Bool) {
        guard !isSaving else { return }
        Task { await run { try self.model.updateOwnDNSSwitch(profileID: self.profileID, on: on) } }
    }

    func switchScheme(to schemeID: String) async {
        await run { try await self.model.switchConfigurationScheme(self.profileID, to: schemeID) }
    }

    func saveAsScheme(named label: String) async {
        await run { try await self.model.saveConfigurationAsScheme(self.profileID, label: label) }
    }

     
    @discardableResult
    func editOriginal(_ path: [ConfigurationTextPathStep], _ edit: ConfigurationTextEdit) async -> Bool {
         
         
        let read = page?.readDigest
        return await run { try await self.model.editOriginalConfiguration(self.profileID, at: path, edit, readDigest: read) }
    }

     
     
     
     
    func turnOff(_ path: [String]) async {
        guard let page else { return }
        switch ConfigurationListenOff.of(path: path, page: page) {
        case .remove?: edit([.remove(path: path)])
        case .fileText?: await editOriginal(path.map(ConfigurationTextPathStep.key), .delete)
        case .layerAndFileText?: await delete(path, .layerAndFileText)
        case .writeEmpty?: edit([.set(path: path, to: .string(""))])
        case nil: break
        }
    }

     
     
    @discardableResult
    func delete(_ path: [String], _ deletion: ConfigurationRowDeletion?) async -> Bool {
        switch deletion {
        case .layer?:
            edit([.remove(path: path)])
            return true
        case .fileText?:
            return await editOriginal(path.map(ConfigurationTextPathStep.key), .delete)
        case .layerAndFileText?:
            let read = page?.readDigest
            return await run { try await self.model.deleteInOriginalConfiguration(self.profileID, at: path, readDigest: read) }
        case .sourceOnly?, nil:
            return false
        }
    }

     
     
    @discardableResult
    func renameOriginal(_ kind: ConfigurationReferenceKind, from oldName: String, to newName: String) async -> Bool {
        var carried: GroupSelectionCarryOver = .nothing
        let read = page?.readDigest
        let saved = await run {
            carried = try await self.model.renameInOriginalConfiguration(self.profileID, kind: kind, from: oldName, to: newName,
                                                                         selections: self.selections, readDigest: read)
        }
        if saved, case .needsChoosingAgain = carried {
            notice = .format("Renamed. Choose what “%@” uses again.", [newName])
        }
        return saved
    }

    @discardableResult
    func run(_ work: @escaping () async throws -> Void) async -> Bool {
        let appliesBefore = model.lastTunnelApply.sequence
        isSaving = true
        defer {
            isSaving = false
             
            let queued = queuedEdits
            queuedEdits = []
            edit(queued)
        }
        var saved = false
        do {
            try await work()
            saved = true
        } catch is CancellationError {
        } catch let refused as ConfigurationTextEditRefusal {
            refusal = Refusal(sentence: refused.errorDescription ?? refused.message, coreWords: refused.failureReason,
                              editTheSourceInstead: refused.editTheSourceInstead)
        } catch OriginalEditingError.followsSubscription {
             
             
             
             
             
            model.detachingLinkOriginals.insert(profileID)
            defer { model.detachingLinkOriginals.remove(profileID) }
            do { try await work(); saved = true } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        } catch let refused as OriginalEditingError where refused == .notYAMLText {
            refusal = Refusal(sentence: refused.errorDescription ?? "", coreWords: nil, editTheSourceInstead: true)
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        await reload()
         
        savingEdits = []
         
         
         
        if saved {
            Task { [weak self] in
                guard let self else { return }
                await self.model.waitForPendingActivation()
                if self.notice == nil,
                   let restarted = ProfilesViewModel.restartNotice(profileID: self.profileID, since: appliesBefore,
                                                      last: self.model.lastTunnelApply) {
                    self.notice = restarted
                }
            }
        }
        return saved
    }

     
    func value(at path: [String]) -> OrderedJSON? { page?.document.node(at: path) }

     
     
    func settingsValue(at path: [String]) -> OrderedJSON? { running?.node(at: path) }

     
     
     
     
     
     
     
    func expectedSettingsValue(at path: [String]) -> OrderedJSON? {
        let waiting = savingEdits + queuedEdits + (pendingEdits ?? [])
        guard !waiting.isEmpty, let running else { return settingsValue(at: path) }
        return waiting.reduce(running) { document, edit in (try? document.applying(edit)) ?? document }.node(at: path)
    }

     
     
    var settingsDocument: OrderedJSON { settingsValue(at: []) ?? .object([]) }

     
     
    func field(at steps: [ConfigurationDocumentStep], in document: OrderedJSON) -> ConfigurationField? {
        catalog?.field(at: steps, in: document)
    }

     
    func ownLayerWrites(_ path: [String]) -> Bool { page?.ownLayer?.node(at: path) != nil }

    var isComposed: Bool {
        if case .composed? = page?.form { return true }
        return false
    }
}

 

 
 
 
 
 
enum ConfigurationEditorSheet: String, Identifiable {
    case saveAsScheme
    var id: String { rawValue }
}

 
struct ConfigurationCompileResult: Identifiable {
    let id = UUID()
    let answer: ConfigurationCompileAnswer
}

 
 
 
 
struct ConfigurationEditorAlerts: ViewModifier {
    @ObservedObject var session: ConfigurationEditorSession
    let editSource: () -> Void
    var isActive = true
    @Environment(\.clashFeedback) private var feedback

    func body(content: Content) -> some View {
        content
            .alert(
                Text(clash: .copy("Not Saved")),
                isPresented: Binding(get: { isActive && session.refusal != nil }, set: { if !$0 { session.refusal = nil } })
            ) {
                if session.refusal?.editTheSourceInstead == true {
                    Button {
                        session.refusal = nil
                        editSource()
                    } label: { Text(clash: .copy("Edit Source")) }
                    .accessibilityIdentifier("configuration-editor.refusal.edit-source")
                }
                Button(role: .cancel) { session.refusal = nil } label: { Text(clash: .copy("OK")) }
            } message: {
                 
                 
                let words = session.refusal?.coreWords ?? ""
                Text(clash: .copy(session.refusal?.sentence ?? "")) + Text(verbatim: words.isEmpty ? "" : "\n\n" + words)
            }
             
             
             
            .onChange(of: session.notice) { notice in
                guard isActive, let notice, let feedback else { return }
                feedback.show(.information(title: notice, accessibilityIdentifier: "feedback.configuration-editor.notice"),
                              operation: "configuration-editor.notice")
                session.notice = nil
            }
            .alert(
                Text(clash: session.notice ?? .copy("")),
                isPresented: Binding(get: { isActive && feedback == nil && session.notice != nil },
                                     set: { if !$0 { session.notice = nil } })
            ) {
                Button { session.notice = nil } label: { Text(clash: .copy("OK")) }
            }
            .alert(
                Text(clash: .copy("Not Saved")),
                isPresented: Binding(get: { isActive && session.failure != nil }, set: { if !$0 { session.failure = nil } })
            ) {
                Button { session.failure = nil } label: { Text(clash: .copy("OK")) }
            } message: {
                Text(clash: .copy(session.failure ?? ""))
            }
            .alert(
                Text(clash: .copy("Save as your own rule scheme?")),
                isPresented: Binding(get: { isActive && session.pendingEdits != nil }, set: { if !$0 { session.pendingEdits = nil } })
            ) {
                Button { session.confirmPendingEdits() } label: { Text(clash: .copy("Save")) }
                    .accessibilityIdentifier("configuration-editor.confirm-own-scheme")
                Button(role: .cancel) { session.pendingEdits = nil } label: { Text(clash: .copy("Cancel")) }
            } message: {
                if case .composed(let scheme, _)? = session.page?.form {
                    Text(clash: .format("Only “%@” will use it; rule scheme “%@” stays as it is.",
                                       [session.page?.label ?? "", scheme.displayLabel]))
                }
            }
    }
}

 
 
 
 
struct ConfigurationEditorHost: View {
    let profileID: String
    let selections: GroupSelectionCarrying?
    @StateObject private var model: ProfilesViewModel
    @StateObject private var importRouter = ProfileImportRouter(inbox: nil)

    init(vpn: VPNController, profileID: String, selections: GroupSelectionCarrying? = nil) {
        self.profileID = profileID
        self.selections = selections
        _model = StateObject(wrappedValue: ProfilesViewModel(vpn: vpn))
    }

    init(model: ProfilesViewModel, profileID: String, selections: GroupSelectionCarrying? = nil) {
        self.profileID = profileID
        self.selections = selections
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        ProfileCenterAdapter(profiles: model, importRouter: importRouter,
                             initialDestination: .profileDetail(id: profileID), selections: selections)
    }
}

 

struct ConfigurationSchemeNameSheet: View {
    let initial: String
    let save: (String) -> Void
    @State private var name = ""
    @State private var dismiss = ClashDismissHandle()

    var body: some View {
        ClashFeatureNavigationContainer {
            Form {
                TextField(text: $name) { Text(clash: .copy("Name")) }
                    .accessibilityIdentifier("configuration-editor.scheme-name")
            }
            .navigationTitle(Text(clash: .copy("Save as Rule Scheme")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(clash: .copy("Cancel")) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save(name.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    } label: { Text(clash: .copy("Save")) }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .clashCapturesDismiss(dismiss)
        .onAppear { if name.isEmpty { name = initial } }
    }
}

 

struct ConfigurationCompileResultView: View {
    let answer: ConfigurationCompileAnswer
    @State private var dismiss = ClashDismissHandle()

    var body: some View {
        ClashFeatureNavigationContainer {
            List {
                switch answer {
                case .accepted:
                    Label { Text(clash: .copy("Passed")) } icon: {
                        Image(systemName: ClashSymbol.checkmarkCircleFill.name).foregroundStyle(.green)
                    }
                    .accessibilityIdentifier("configuration-editor.compile.passed")
                case .refused(let problems):
                    ForEach(Array(problems.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                             
                            Text(verbatim: item.message).textSelection(.enabled)
                            if let place = ConfigurationEditorCopy.place(of: item) {
                                Text(verbatim: place).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("configuration-editor.compile.error")
                    }
                case .unavailable(let words):
                    Text(clash: .copy("The configuration could not be checked."))
                        .accessibilityIdentifier("configuration-editor.compile.unavailable")
                    if let words, !words.isEmpty {
                        Text(verbatim: words).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(Text(clash: .copy("Compile Configuration")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text(clash: .copy("Done")) }
                }
            }
        }
        .clashCapturesDismiss(dismiss)
    }
}

 

 
 
 
struct ConfigurationInboundListenersSection: View {
    @ObservedObject var session: ConfigurationEditorSession
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

     
    static let shownAtMost = 30

    var body: some View {
        let location = ConfigurationListLocation.key(["listeners"])
        let items = location.items(in: session.settingsDocument)
        let types = ConfigurationTypeWords.names(.listeners, copy: fieldCopy, locale: locale)
        Section {
            if items.isEmpty {
                Text(clash: ConfigurationEmptyList.sentence(for: "listeners")).foregroundStyle(.secondary)
                    .accessibilityIdentifier("configuration-editor.inbound.listeners.empty")
            }
            ForEach(Array(items.prefix(Self.shownAtMost).enumerated()), id: \.offset) { index, item in
                NavigationLink {
                    ConfigurationObjectItemView(session: session, location: location, index: index)
                } label: {
                    ConfigurationRowLabel(title: .verbatim(ConfigurationObjectList.title(of: item, index: index)),
                                          value: .verbatim(ConfigurationObjectListView.summary(of: item, typeNames: types)))
                }
                .accessibilityIdentifier("configuration-editor.inbound.listener.\(index)")
            }
            if items.count > Self.shownAtMost {
                NavigationLink {
                    ConfigurationObjectListView(session: session, location: location,
                                                title: ClashCopy.string("Inbound Listeners", locale: locale))
                } label: {
                    Text(clash: .format("All %@", [String(items.count)]))
                }
                .accessibilityIdentifier("configuration-editor.inbound.listeners.all")
            }
            ConfigurationNewListItemButton(session: session, location: location, title: .copy("Add Listener"),
                                           identifier: "configuration-editor.inbound.listeners.add")
        } header: {
            Text(clash: .copy("Inbound Listeners"))
        } footer: {
             
             
             
            Text(clash: .copy("Extra ports, each with its own protocol, account and route. The proxy ports this device and the LAN use by default are in LAN Proxy Share."))
        }
    }
}

 
 
 
 
 
 
 
 
struct ConfigurationSettingsSectionView: View {
    @ObservedObject var session: ConfigurationEditorSession
    let section: ConfigurationOutlineSection
     
     
    let basePath: [String]
    @Environment(\.configurationLinkedPage) private var linkedPage
    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @State private var search = ""
    @State private var adding = false
     
    @State private var notesRead = 0

    private var isOriginal: Bool { session.page?.form == .original }

    private var drawn: (layout: ConfigurationSectionLayout, listsListeners: Bool) {
        let conditions = session.model.platformConditionsHolding()
        let key = [section.rawValue, basePath.joined(separator: "\u{1F}"), isOriginal ? "o" : "c",
                   conditions.sorted().joined(separator: ","), locale.identifier].joined(separator: "|")
        let layout = session.layout(key) {
            ConfigurationSectionLayout.make(section: section, basePath: basePath, document: session.settingsDocument,
                                            catalog: session.catalog, original: isOriginal, conditions: conditions)
                .arranged(by: fieldCopy, locale: locale, catalog: session.catalog, document: session.settingsDocument)
        }
        return Self.listingItsListeners(layout, section: section, basePath: basePath)
    }

     
     
     
     
     
    static func listingItsListeners(_ layout: ConfigurationSectionLayout, section: ConfigurationOutlineSection,
                                    basePath: [String]) -> (layout: ConfigurationSectionLayout, listsListeners: Bool) {
        guard section == .inbound, basePath.isEmpty else { return (layout, false) }
        let groups = layout.groups.compactMap { group -> ConfigurationSectionLayout.Group? in
            var group = group
            group.rows.removeAll { $0.path == ["listeners"] }
            return group.rows.isEmpty ? nil : group
        }
        return (ConfigurationSectionLayout(groups: groups, platformDecided: layout.platformDecided), true)
    }

     
     
     
    private func title(of row: ConfigurationSectionLayout.Row) -> String {
        isMapEntry(row) ? row.key : fieldCopy.title(for: row.field, key: row.key, locale: locale)
    }

     
     
    @ViewBuilder
    private func heading(of group: ConfigurationSectionLayout.Group) -> some View {
        switch group.title {
        case .none: EmptyView()
        case .copy(let title): Text(clash: .copy(title))
        case .words(let words): Text(verbatim: words)
        case .key(let key):
            if group.path.isEmpty {
                Text(verbatim: key)
            } else {
                Text(verbatim: fieldCopy.title(for: session.field(at: group.path.map(ConfigurationDocumentStep.key),
                                                                  in: session.settingsDocument),
                                               key: key, locale: locale))
            }
        }
    }

     
     
    private func conditionNote(_ row: ConfigurationSectionLayout.Row) -> ClashDisplayText? {
        guard row.conditionalEffective != nil, let field = row.field else { return nil }
        return ConfigurationValueWords.conditionalLine(for: field, conditions: session.model.platformConditionsHolding())
    }

     
    private func shown(_ layout: ConfigurationSectionLayout) -> [ConfigurationSectionLayout.Group] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return layout.groups }
        return layout.groups.compactMap { group in
            var group = group
            group.rows = group.rows.filter { Self.matches($0, query: query, copy: fieldCopy, locale: locale) }
            return group.rows.isEmpty ? nil : group
        }
    }

     
     
    static func matches(_ row: ConfigurationSectionLayout.Row, query: String, copy: ConfigurationFieldCopy,
                        locale: Locale) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        return row.path.joined(separator: ".").lowercased().contains(query)
            || copy.title(for: row.field, key: row.key, locale: locale).lowercased().contains(query)
    }

     
    private var writtenKeys: Set<String> {
        guard case .object(let entries)? = session.settingsValue(at: basePath) else { return [] }
        return Set(entries.map(\.key))
    }

     
     
    private var entryField: ConfigurationField? {
        ConfigurationSectionLayout.entryField(of: basePath, in: session.settingsDocument, catalog: session.catalog)
    }

    var body: some View {
        if session.page == nil || session.awaitsCatalog {
             
             
            List {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("configuration-editor.loading")
                }
            }
            .navigationTitle(Text(clash: .copy(ConfigurationEditorCopy.title(of: section))))
        } else {
            content
        }
    }

    private var content: some View {
        let (layout, listsListeners) = drawn
        return List {
            if section == .dns, basePath == ConfigurationSectionLayout.base(of: .dns), let on = session.page?.ownDNSSwitch {
                 
                 
                Section {
                    Toggle(isOn: Binding(get: { on }, set: { session.setOwnDNSSwitch($0) })) {
                        Text(clash: .copy("Use custom DNS"))
                    }
                    .accessibilityIdentifier("configuration-editor.dns.custom")
                } footer: {
                    Text(clash: .copy("Off: these settings apply only when this configuration’s file has no DNS of its own."))
                }
            }
            if showsLANShareRow { lanShareRow }
            ForEach(shown(layout)) { group in
                Section {
                    ForEach(group.rows) { row in
                         
                         
                        rowView(row).disabled(inactive(row))
                    }
                    if let entry = mapEntryPath(of: group) {
                         
                         
                        entryDelete(entry)
                    }
                } header: {
                    heading(of: group)
                } footer: {
                    if let footer = group.footer { Text(verbatim: footer) }
                    note(for: group)
                    if let summary = offSwitchSummary(in: group) {
                        Text(clash: fieldCopy.turnOnLine(summary, locale: locale))
                    }
                }
            }
            if listsListeners, search.trimmingCharacters(in: .whitespaces).isEmpty {
                ConfigurationInboundListenersSection(session: session)
            }
            if entryField != nil, layout.groups.isEmpty, search.trimmingCharacters(in: .whitespaces).isEmpty {
                 
                 
                Section {
                    Button { adding = true } label: {
                        Label { Text(clash: .copy("Add")) } icon: { Image(systemName: ClashSymbol.plus.name) }
                    }
                    .accessibilityIdentifier("configuration-editor.key.add-first")
                }
            }
            if !layout.platformDecided.isEmpty, search.trimmingCharacters(in: .whitespaces).isEmpty {
                 
                 
                 
                Section {
                    NavigationLink {
                        ConfigurationSettingsNotApplyingView(items: layout.notApplying)
                    } label: {
                        ConfigurationNotApplyingLabel(count: layout.platformDecided.count)
                    }
                    .accessibilityIdentifier("configuration-editor.not-applying")
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle(basePath == ConfigurationSectionLayout.base(of: section)
                         ? Text(clash: .copy(ConfigurationEditorCopy.title(of: section)))
                         : Text(verbatim: fieldCopy.title(for: session.field(at: basePath.map(ConfigurationDocumentStep.key),
                                                                             in: session.settingsDocument),
                                                          key: basePath.last ?? "", locale: locale)))
        .toolbar {
             
             
             
            if entryField != nil {
                ToolbarItem(placement: .primaryAction) {
                    ControlGroup {
                        Button { adding = true } label: { Image(systemName: ClashSymbol.plus.name) }
                            .accessibilityIdentifier("configuration-editor.key.add")
                    }
                    .clashReaderControlGroupStyle()
                }
            }
        }
         
         
         
         
        .sheet(isPresented: $adding) {
            let map = session.field(at: basePath.map(ConfigurationDocumentStep.key), in: session.settingsDocument)
            ConfigurationNewKeyForm(suggestions: map?.key?.values ?? [], taken: writtenKeys,
                                    document: session.settingsDocument, entryField: entryField,
                                    keyFormat: map?.key?.format,
                                    policyKeys: ConfigurationPolicyKey.isPolicyMap(basePath)) { key, value in
                session.edit([.set(path: basePath + [key], to: value)])
            }
            .clashModalPresentation(.form)
        }
    }

     
     
    private func inactive(_ row: ConfigurationSectionLayout.Row) -> Bool {
        guard let field = row.field, let catalog = session.catalog?.fieldCatalog else { return false }
        return catalog.isInactive(field, at: row.path.map(ConfigurationDocumentStep.key), in: session.settingsDocument)
    }

     
     
    private func offSwitchSummary(in group: ConfigurationSectionLayout.Group) -> ConfigurationOffSwitchSummary? {
        guard let catalog = session.catalog?.fieldCatalog else { return nil }
        return catalog.offSwitchSummary(over: group.rows.compactMap { row in
            row.field.map { (field: $0, steps: row.path.map(ConfigurationDocumentStep.key)) }
        }, in: session.settingsDocument)
    }

    @ViewBuilder
    private func rowView(_ row: ConfigurationSectionLayout.Row) -> some View {
        switch row.control {
        case .inline:
            if let field = row.field, let draft = ConfigurationFieldDraft(field: field, value: row.value, in: session.settingsDocument) {
                ConfigurationInlineFieldRow(title: title(of: row), draft: draft,
                                            identifier: "configuration-editor.key.inline.\(row.id)",
                                            save: { session.edit([.set(path: row.path, to: $0)]) },
                                            isDefault: row.value == nil, defaultText: field.defaultText,
                                            useDefault: useDefault(of: row, draft: draft),
                                            caption: conditionNote(row), field: field)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) { useDefault(row) }
            }
        case .page:
            NavigationLink {
                ConfigurationValueView(session: session, path: row.path)
                    .configurationPushedAlertHost(session)
            } label: { label(row) }
                .accessibilityIdentifier("configuration-editor.key.\(row.id)")
                .swipeActions(edge: .trailing, allowsFullSwipe: false) { useDefault(row) }
        case .drill:
            NavigationLink {
                if row.field?.kind == .objectList {
                     
                     
                    ConfigurationObjectListView(session: session, location: .key(row.path), title: title(of: row))
                        .configurationPushedAlertHost(session)
                } else {
                    ConfigurationSettingsSectionView(session: session, section: section, basePath: row.path)
                        .configurationPushedAlertHost(session)
                }
            } label: { label(row) }
            .accessibilityIdentifier("configuration-editor.key.\(row.id)")
            .swipeActions(edge: .trailing, allowsFullSwipe: false) { useDefault(row) }
        case .platform:
             
            EmptyView()
        case .owned(let owner):
            ownedRow(row, owner)
        }
    }

     
    private func isMapEntry(_ row: ConfigurationSectionLayout.Row) -> Bool {
        entryField != nil && row.path.count == basePath.count + 1
    }

     
     
    private func mapEntryPath(of group: ConfigurationSectionLayout.Group) -> [String]? {
        guard entryField != nil, group.id.hasPrefix("entry:"), case .key(let key) = group.title else { return nil }
        let path = basePath + [key]
        return group.id == "entry:" + path.joined(separator: ".") ? path : nil
    }

     
     
     
    @ViewBuilder
    private func entryDelete(_ path: [String]) -> some View {
        let deletion = ConfigurationRowDeletion.of(path: path, isMapEntry: true, page: session.page,
                                                   running: session.settingsDocument)
        if let deletion {
            Button(role: .destructive) {
                if deletion == .sourceOnly {
                    session.refusal = .init(sentence: ClashCopy.string(for: .copy(Self.fromProfileURLSentence),
                                                                      locale: AppPreferences.language().locale),
                                            coreWords: nil, editTheSourceInstead: true)
                } else {
                    Task { await session.delete(path, deletion) }
                }
            } label: {
                Text(clash: .copy("Delete"))
            }
            .accessibilityIdentifier("configuration-editor.group.delete")
        }
    }

     
     
     
     
     
     
    @ViewBuilder
    private func useDefault(_ row: ConfigurationSectionLayout.Row) -> some View {
        let entry = isMapEntry(row)
        switch ConfigurationRowDeletion.of(path: row.path, isMapEntry: entry, page: session.page, running: session.settingsDocument) {
        case .layer?:
            if entry {
                 
                 
                Button(role: .destructive) { session.edit([.remove(path: row.path)]) } label: { Text(clash: .copy("Delete")) }
                    .accessibilityIdentifier("configuration-editor.key.delete")
            } else {
                Button { session.edit([.remove(path: row.path)]) } label: { Text(clash: .copy("Use Default")) }
                    .tint(.orange)
                    .accessibilityIdentifier("configuration-editor.key.use-default")
            }
        case .fileText?:
            Button(role: .destructive) {
                Task { await session.editOriginal(row.path.map(ConfigurationTextPathStep.key), .delete) }
            } label: { Text(clash: .copy("Delete")) }
            .accessibilityIdentifier("configuration-editor.key.delete-in-text")
        case .sourceOnly?:
            Button(role: .destructive) {
                session.refusal = .init(sentence: ClashCopy.string(for: .copy(Self.fromProfileURLSentence),
                                                                  locale: AppPreferences.language().locale),
                                        coreWords: nil, editTheSourceInstead: true)
            } label: { Text(clash: .copy("Delete")) }
            .accessibilityIdentifier("configuration-editor.key.delete-in-source")
        case .layerAndFileText?:
            Button(role: .destructive) {
                Task { await session.delete(row.path, .layerAndFileText) }
            } label: { Text(clash: .copy("Delete")) }
            .accessibilityIdentifier("configuration-editor.key.delete-in-text")
        case nil:
            EmptyView()
        }
    }

    static let fromProfileURLSentence =
        "This entry comes from the Profile URL and returns at its next update. Delete it in the source."

    private func removable(_ row: ConfigurationSectionLayout.Row) -> Bool {
        row.value != nil && (session.page?.ownLayer == nil || session.ownLayerWrites(row.path))
    }

     
     
     
     
    private func useDefault(of row: ConfigurationSectionLayout.Row, draft: ConfigurationFieldDraft) -> (() -> Void)? {
        if ConfigurationPresetMenuRow.isAddress(draft) {
            guard row.value != nil else { return nil }
            return { Task { await session.turnOff(row.path) } }
        }
        return removable(row) ? { session.edit([.remove(path: row.path)]) } : nil
    }

     
     
    @ViewBuilder
    private func ownedRow(_ row: ConfigurationSectionLayout.Row, _ owner: ConfigurationKeyOwner) -> some View {
        let caption = ClashDisplayText.formatCopy("Change in %@", [Self.pageTitle(of: owner)])
        if let page = linkedPage?(.owner(owner)) {
             
            NavigationLink { page } label: { label(row, caption: caption) }
                .accessibilityIdentifier("configuration-editor.key.owner.\(row.id)")
        } else {
            label(row, caption: caption)
        }
    }

     
     
     
     
    private var showsLANShareRow: Bool {
        guard basePath.isEmpty, section == .inbound || section == .general else { return false }
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return section == .inbound }
        return ConfigurationLANShareStatus.matches(query, copy: fieldCopy, locale: locale)
    }

    private var lanShareRow: some View {
        Section {
            NavigationLink {
                ProxyShareConfigurationView(profiles: session.model, session: session)
            } label: {
                ConfigurationRowLabel(title: .copy("LAN Proxy Share"), value: ConfigurationLANShareStatus.words(for: session))
            }
            .accessibilityIdentifier("configuration-editor.key.lan-share")
        }
    }

    private func label(_ row: ConfigurationSectionLayout.Row, caption: ClashDisplayText? = nil) -> some View {
        ConfigurationRowLabel(title: .verbatim(title(of: row)),
                              caption: caption ?? conditionNote(row),
                              value: ConfigurationValueWords.summary(row.value, field: row.field, locale: locale, copy: fieldCopy),
                              isDefault: row.value == nil)
    }

     
     
    @ViewBuilder
    private func note(for group: ConfigurationSectionLayout.Group) -> some View {
        let _ = notesRead
        if basePath.isEmpty, section == .general {
            if group.rows.contains(where: { $0.key == "mode" }), let home = session.model.outboundModeSetOnHome() {
                VStack(alignment: .leading, spacing: 6) {
                    Text(clash: .formatCopy("Home is set to “%@”, which runs over this for now.", [Self.modeTitle(home)]))
                    Button {
                        do { try session.model.followConfigurationOutboundMode() } catch {
                            session.failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        }
                        notesRead += 1
                    } label: { Text(clash: .copy("Follow the Configuration Again")) }
                    .accessibilityIdentifier("configuration-editor.general.follow-configuration")
                }
            } else if group.rows.contains(where: { $0.key == "log-level" }), let level = session.model.logLevelForcedByLogSettings() {
                Text(clash: .format("Log Settings is set to “%@”, which runs over this.", [level]))
            }
        }
    }

    static func modeTitle(_ mode: Profile.OutboundMode) -> String {
        switch mode {
        case .global: "Global"
        case .rule: "Rule"
        case .direct: "Direct"
        }
    }

     
    static func pageTitle(of owner: ConfigurationKeyOwner) -> String {
        switch owner {
        case .lanSharing: "LAN Proxy Share"
        case .clientSettings: "Client Settings"
        case .certificatesAndTrust: "Certificates & Trust"
        case .tunnelAndRoutes: "Tunnel & Routes"
        }
    }
}

 
 
 
 
struct ConfigurationRowLabel: View {
    let title: ClashDisplayText
    var caption: ClashDisplayText? = nil
    let value: ClashDisplayText
     
    var isDefault = false

    private var valueStyle: HierarchicalShapeStyle { isDefault ? .tertiary : .secondary }

    var body: some View {
        if #available(iOS 16.0, *) {
            LabeledContent {
                Text(clash: value).foregroundStyle(valueStyle).lineLimit(1)
            } label: {
                Text(clash: title)
                if let caption { Text(clash: caption) }
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(clash: title)
                    if let caption { Text(clash: caption).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Text(clash: value).foregroundStyle(valueStyle).lineLimit(1)
            }
        }
    }
}

 
 
 
extension ConfigurationLANShareStatus {
    @MainActor
    static func words(for session: ConfigurationEditorSession) -> ClashDisplayText {
        let override = session.model.profiles.first { $0.id == session.profileID }
            .map { KernelLANShareOverride(patch: OverridePatch(patchJSON: $0.override.patchJSON)) }
        return words(override: override ?? KernelLANShareOverride(), document: session.settingsDocument)
    }
}

 
 
enum ConfigurationLinkedPage: Equatable {
    case owner(ConfigurationKeyOwner)
}

 
 
struct ConfigurationLinkedPageKey: EnvironmentKey {
    static var defaultValue: (@MainActor (ConfigurationLinkedPage) -> AnyView?)? { nil }
}

extension EnvironmentValues {
    var configurationLinkedPage: (@MainActor (ConfigurationLinkedPage) -> AnyView?)? {
        get { self[ConfigurationLinkedPageKey.self] }
        set { self[ConfigurationLinkedPageKey.self] = newValue }
    }
}

 
 
 
 
 
struct ConfigurationValueView: View {
    @ObservedObject var session: ConfigurationEditorSession
    let path: [String]
    @State private var draft: ConfigurationDraft?
     
     
    @State private var opened: ConfigurationDraft?
     
    @State private var usedDefault = false
    @State private var dismiss = ClashDismissHandle()
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

     
     
     
     
    private var current: OrderedJSON? { session.expectedSettingsValue(at: path) }
    private var platformReason: String? { session.catalog?.platformReason(for: path, in: session.settingsDocument) }
     
    private var field: ConfigurationField? {
        session.field(at: path.map(ConfigurationDocumentStep.key), in: session.settingsDocument)
    }
     
    private var removable: Bool {
        current != nil && (session.page?.ownLayer == nil || session.ownLayerWrites(path))
    }
     
    private var isMapEntry: Bool { field?.path.hasSuffix("*") == true }
     
    private var words: ConfigurationFieldCopy.Entry? { isMapEntry ? nil : fieldCopy.entry(for: field, locale: locale) }

    var body: some View {
        Form {
            if platformReason != nil {
                 
                 
                 
                Section {
                    Text(clash: ConfigurationValueWords.categoryLine(for: field?.platformDecision, device: ConfigurationDevice.name))
                    if let words = fieldCopy.platformWords(for: field, locale: locale) {
                        Text(verbatim: words).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            if let draft = Binding($draft) {
                 
                 
                 
                 
                 
                if let presets = words?.presets, !presets.isEmpty, field?.format != .ipPort, platformReason == nil {
                    ConfigurationFieldPresets(draft: draft, presets: presets, defaultValue: field?.defaultText)
                }
                ConfigurationDraftEditor(draft: draft, choices: session.catalog?.choices(for: path), field: field)
                    .disabled(platformReason != nil)
            } else if let current {
                Section {
                    Text(verbatim: current.serialized()).font(.footnote.monospaced()).textSelection(.enabled)
                } footer: {
                    Text(clash: .copy("Change this one in the source."))
                }
            }
            if removable, platformReason == nil {
                Section {
                    Button {
                        usedDefault = true
                        session.edit([.remove(path: path)])
                        dismiss()
                    } label: { Text(clash: .copy("Use Default")) }
                    .accessibilityIdentifier("configuration-editor.value.use-default")
                }
            }
             
             
            ConfigurationFieldAbout(summary: draft?.isList == true ? nil : words?.summary,
                                    key: isMapEntry ? nil : path.last)
        }
        .configurationKnownValueSearch(for: field)
        .navigationTitle(Text(verbatim: words?.title ?? path.last ?? ""))
        .clashCapturesDismiss(dismiss)
        .onAppear { if draft == nil { start() } }
         
         
        .onChange(of: session.catalog) { _ in
            if draft == opened { start() }
        }
        .onDisappear { commit() }
    }

    private func start() {
        draft = ConfigurationDraft.make(current, field: field, in: session.settingsDocument)
            ?? (current == nil ? .plain(ConfigurationValueDraft(kind: .text)) : nil)
        opened = draft
    }

     
     
     
     
    private func commit() {
        guard !usedDefault, platformReason == nil else { return }
         
         
         
         
        if case .field(let address)? = draft, address.text.isEmpty,
           ConfigurationFormatPresets.addressChoices(path: address.path) != nil {
            if let expected = session.expectedSettingsValue(at: path), expected != .string("") {
                Task { await session.turnOff(path) }
            }
            opened = draft
            return
        }
         
         
        let infersKind = current == nil && field == nil
        guard let value = ConfigurationDraft.handedOn(draft, since: &opened, expected: session.expectedSettingsValue(at: path), value: { draft in
            if infersKind, case .plain(let plain) = draft, plain.kind == .text { return ConfigurationNewKeyForm.inferredValue(plain.text) }
            return draft.value
        }) else { return }
        session.edit([.set(path: path, to: value)])
    }
}

 
 
 
enum ConfigurationDraft: Equatable {
    case plain(ConfigurationValueDraft)
    case field(ConfigurationFieldDraft)

     
     
    static func make(_ value: OrderedJSON?, field: ConfigurationField?, in document: OrderedJSON) -> ConfigurationDraft? {
        if let field, let draft = ConfigurationFieldDraft(field: field, value: value, in: document) { return .field(draft) }
        return value.flatMap(ConfigurationValueDraft.init).map(ConfigurationDraft.plain)
    }

     
     
     
     
     
     
     
    static func change(_ draft: ConfigurationDraft?, since baseline: inout ConfigurationDraft?) -> ConfigurationDraft? {
        guard let draft, draft != baseline, draft.isValid else { return nil }
        baseline = draft
        return draft
    }

     
     
     
     
     
     
    static func handedOn(_ draft: ConfigurationDraft?, since baseline: inout ConfigurationDraft?, expected: OrderedJSON?,
                         value: (ConfigurationDraft) -> OrderedJSON = { $0.value }) -> OrderedJSON? {
        guard let changed = change(draft, since: &baseline) else { return nil }
        let handed = value(changed)
        return handed == expected ? nil : handed
    }

    var value: OrderedJSON {
        switch self {
        case .plain(let draft): return draft.value
        case .field(let draft): return draft.value
        }
    }

    var isValid: Bool {
        switch self {
        case .plain(let draft): return draft.isValid
        case .field(let draft): return draft.isValid
        }
    }
}

 
struct ConfigurationValueDraft: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case text, number, toggle, list
        var id: String { rawValue }
        var title: String {
            switch self {
            case .text: "Text"
            case .number: "Number"
            case .toggle: "On/Off"
            case .list: "List"
            }
        }
    }
    var kind: Kind
    var text = ""
    var flag = false
    var lines = ""
     
     
    var pending = ""

    init(kind: Kind) { self.kind = kind }

     
    init?(_ value: OrderedJSON) {
        switch value {
         
         
        case .string(let text) where !text.contains(where: \.isNewline):
            kind = .text; self.text = text
        case .scalar(let token) where token == "true" || token == "false":
            kind = .toggle; flag = token == "true"
        case .scalar(let token) where Double(token) != nil:
            kind = .number; text = token
        case .array(let items):
            var strings: [String] = []
            for item in items {
                switch item {
                 
                 
                case .string(let text) where !text.contains(where: \.isNewline): strings.append(text)
                case .scalar(let token) where token != "null": strings.append(token)
                default: return nil
                }
            }
            kind = .list; lines = strings.joined(separator: "\n")
        default:
            return nil
        }
    }

    var isValid: Bool {
        switch kind {
        case .number: return Double(text.trimmingCharacters(in: .whitespaces)) != nil
        default: return true
        }
    }

    var value: OrderedJSON {
        switch kind {
        case .text: return .string(text)
        case .number: return .scalar(text.trimmingCharacters(in: .whitespaces))
        case .toggle: return .scalar(flag ? "true" : "false")
        case .list:
            var entries = lines.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let typed = pending.trimmingCharacters(in: .whitespacesAndNewlines)
            if !typed.isEmpty, !typed.contains(where: \.isNewline), !entries.contains(typed) { entries.append(typed) }
            return .array(entries.map(OrderedJSON.string))
        }
    }
}

struct ConfigurationValueEditor: View {
    @Binding var draft: ConfigurationValueDraft
     
    let choices: [String]?

    var body: some View {
        if draft.kind == .list {
             
            ConfigurationListRows(items: Binding(get: {
                draft.lines.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }, set: { draft.lines = $0.joined(separator: "\n") }), newItem: $draft.pending, ordered: true)
        } else {
            single
        }
    }

    private var single: some View {
        Section {
            switch draft.kind {
            case .toggle:
                Toggle(isOn: $draft.flag) { Text(clash: .copy("On")) }
                    .accessibilityIdentifier("configuration-editor.value.toggle")
            case .number:
                TextField(text: $draft.text) { Text(clash: .copy("Value")) }
                    .keyboardType(.numbersAndPunctuation)
                    .accessibilityIdentifier("configuration-editor.value.number")
            case .text:
                if let choices, !choices.isEmpty {
                    Picker(selection: $draft.text) {
                        ForEach(choices, id: \.self) { Text(verbatim: $0).tag($0) }
                    } label: { Text(clash: .copy("Value")) }
                    .accessibilityIdentifier("configuration-editor.value.choice")
                } else {
                    TextField(text: $draft.text) { Text(clash: .copy("Value")) }
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .accessibilityIdentifier("configuration-editor.value.text")
                }
            case .list:
                EmptyView()
            }
        }
    }
}

 
 
struct ConfigurationDraftEditor: View {
    @Binding var draft: ConfigurationDraft
     
    let choices: [String]?
     
    var field: ConfigurationField? = nil

    var body: some View {
        switch draft {
        case .plain(let plain):
            ConfigurationValueEditor(draft: Binding(get: {
                if case .plain(let current) = draft { return current }
                return plain
            }, set: { draft = .plain($0) }), choices: choices)
        case .field(let fieldDraft):
            ConfigurationFieldEditor(draft: Binding(get: {
                if case .field(let current) = draft { return current }
                return fieldDraft
            }, set: { draft = .field($0) }), field: field)
        }
    }
}

 
 
 
 
 
struct ConfigurationFieldEditor: View {
    @Binding var draft: ConfigurationFieldDraft
     
     
    var field: ConfigurationField? = nil

     
    @Environment(\.configurationKnownValueSearch) private var knownSearch
     
    @Environment(\.configurationValueStartsOnCustom) private var startsOnCustom
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

     
     
    private func words(_ value: String) -> String {
        fieldCopy.valueLabel(value, for: field, locale: locale) ?? value
    }

     
    static let customTag = "\u{1F}custom"
     
    @State private var choosesCustom = false
     
    @State private var showsCustomField = false

     
     
     
     
    static func suggestionSelection(_ draft: ConfigurationFieldDraft, choosesCustom: Bool, options: [String]) -> String {
        if choosesCustom { return customTag }
        return draft.choice(in: options) ?? customTag
    }

     
     
    static func pickSuggestion(_ tag: String, draft: inout ConfigurationFieldDraft, choosesCustom: inout Bool) {
        if tag == customTag {
            choosesCustom = true
        } else {
            draft.text = tag
            choosesCustom = false
        }
    }

     
     
    static let menuLimit = ConfigurationSectionLayout.menuLimit

    var body: some View {
        switch draft.control {
        case .select, .reference:
            if draft.choices.count <= Self.menuLimit { menu } else { longList }
        case .suggest(let options):
            suggestion(options)
        case .toggle:
            Section {
                Toggle(isOn: $draft.flag) { Text(clash: .copy("On")) }
                    .accessibilityIdentifier("configuration-editor.value.toggle")
            }
        case .number(let min, let max, let unit):
             
             
            ConfigurationNumberEditors(draft: $draft, min: min, max: max, unit: unit, defaultText: field?.defaultText)
        case .text(let format) where ConfigurationFormatEditors.shapes(format):
             
             
            ConfigurationFormatEditor(draft: $draft)
        case .text:
            text
        case .textList(_, let suggestions):
            list(suggestions)
        case .multiSelect(let options, let ordered), .references(let options, let ordered):
            choices(options, ordered: ordered)
        }
    }

    private var menu: some View {
        Section {
            Picker(selection: $draft.text) {
                ForEach(draft.choices, id: \.self) { choice in
                    if draft.unknown.contains(choice) {
                        Label { Text(verbatim: choice) } icon: { Image(systemName: ClashSymbol.exclamationmarkTriangle.name) }
                            .tag(choice)
                    } else {
                        Text(verbatim: words(choice)).tag(choice)
                    }
                }
            } label: { Text(clash: .copy("Value")) }
            .pickerStyle(.menu)
            .accessibilityIdentifier("configuration-editor.value.choice")
        } footer: {
            if draft.showsUnknown { Text(clash: .copy("Not among the choices; kept until you change it.")) }
            ConfigurationUnavailableReasons(reasons: draft.unavailableInUse)
        }
    }

     
     
     
    private var longList: some View {
        Section {
            Picker(selection: $draft.text) {
                ForEach(draft.choices, id: \.self) { choice in
                    if draft.unknown.contains(choice) {
                        Label { Text(verbatim: choice) } icon: { Image(systemName: ClashSymbol.exclamationmarkTriangle.name) }
                            .tag(choice)
                    } else {
                        Text(verbatim: words(choice)).tag(choice)
                    }
                }
            } label: { Text(clash: .copy("Value")) }
            .pickerStyle(.inline)
            .labelsHidden()
            .accessibilityIdentifier("configuration-editor.value.choice")
        } footer: {
            if draft.showsUnknown { Text(clash: .copy("Not among the choices; kept until you change it.")) }
            ConfigurationUnavailableReasons(reasons: draft.unavailableInUse)
        }
    }

     
     
    static func picksOneKnownValue(_ field: ConfigurationField?) -> Bool {
        field?.kind == .suggest && ConfigurationFieldExamples.knownSet(for: field) != nil
    }

    @ViewBuilder
    private func suggestion(_ options: [String]) -> some View {
        if let known = ConfigurationFieldExamples.knownSet(for: field) {
             
             
             
             
            ConfigurationKnownValueChoices(set: known,
                                           title: fieldCopy.title(for: field, key: field.map(ConfigurationSectionLayout.key(of:)) ?? "",
                                                                  locale: locale),
                                           text: $draft.text, search: knownSearch, defaultValue: field?.defaultText)
        } else {
            suggestionMenu(options)
        }
    }

     
     
     
    static func suggestionTitle(_ value: String, field: ConfigurationField?, copy: ConfigurationFieldCopy,
                                locale: Locale) -> String {
        copy.valueLabel(value, for: field, locale: locale) ?? value
    }

    private func suggestionMenu(_ options: [String]) -> some View {
        Section {
            Picker(selection: Binding(get: { Self.suggestionSelection(draft, choosesCustom: choosesCustom, options: options) },
                                      set: { tag in
                var next = draft
                Self.pickSuggestion(tag, draft: &next, choosesCustom: &choosesCustom)
                if tag == Self.customTag { showsCustomField = true }
                if next.text != draft.text { draft.text = next.text }
            })) {
                ForEach(options, id: \.self) {
                    Text(verbatim: Self.suggestionTitle($0, field: field, copy: fieldCopy, locale: locale)).tag($0)
                }
                Text(clash: .copy("Custom")).tag(Self.customTag)
            } label: { Text(clash: .copy("Value")) }
            .pickerStyle(.menu)
            .accessibilityIdentifier("configuration-editor.value.suggestion")
             
             
            .onAppear {
                if startsOnCustom, !showsCustomField {
                    choosesCustom = true
                    showsCustomField = true
                }
            }
            if showsCustomField || draft.isCustom {
                 
                 
                TextField(text: Binding(get: { draft.text }, set: { draft.text = $0; choosesCustom = false })) {
                    Text(clash: .copy("Value"))
                }
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .accessibilityIdentifier("configuration-editor.value.custom")
            }
        } footer: {
            ConfigurationFormatWarning(draft: draft)
            ConfigurationUnavailableReasons(reasons: draft.unavailableInUse)
        }
    }

     
     
    static func range(min: Double?, max: Double?) -> String? {
        func plain(_ number: Double) -> String {
            number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)
        }
        switch (min, max) {
        case let (min?, max?): return plain(min) + "–" + plain(max)
        case let (min?, nil) where min != 0: return "≥ " + plain(min)
        case let (nil, max?): return "≤ " + plain(max)
        default: return nil
        }
    }

    private var text: some View {
        Section {
            TextField(text: $draft.text) { Text(clash: .copy("Value")) }
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .accessibilityIdentifier("configuration-editor.value.text")
        } footer: {
            ConfigurationFormatWarning(draft: draft)
        }
    }

    private func list(_ suggestions: [String]) -> some View {
        ConfigurationListRows(items: $draft.items, newItem: $draft.pendingItem, field: field, format: draft.format,
                              ordered: draft.isOrdered, suggestions: suggestions)
    }

     
     
     
     
     
    @ViewBuilder
    private func choices(_ options: [String], ordered: Bool) -> some View {
        if ordered && draft.selection.count > 1 {
            Section {
                ForEach(Array(draft.selection.enumerated()), id: \.offset) { _, entry in
                    Text(verbatim: words(entry))
                }
                .onMove { draft.move(from: $0, to: $1) }
            } header: {
                HStack {
                    Text(clash: .copy("Selected"))
                    Spacer()
                    ConfigurationAmbientReorderButton(identifier: "configuration-editor.value.reorder")
                }
            }
        }
        Section {
            ForEach(options + draft.selection.filter { !options.contains($0) }, id: \.self) { entry in
                Toggle(isOn: Binding(get: { draft.isSelected(entry) }, set: { on in
                    if on != draft.isSelected(entry) { draft.toggle(entry) }
                })) {
                    if draft.unknown.contains(entry) {
                        Label { Text(verbatim: entry) } icon: { Image(systemName: ClashSymbol.exclamationmarkTriangle.name) }
                    } else {
                        Text(verbatim: words(entry))
                    }
                }
                .accessibilityIdentifier("configuration-editor.value.option.\(entry)")
            }
        } footer: {
            if draft.selection.contains(where: draft.unknown.contains) {
                Text(clash: .copy("Not among the choices; kept until you change it."))
            }
            ConfigurationUnavailableReasons(reasons: draft.unavailableInUse)
        }
    }
}

 
 
 
 
 
 
struct ConfigurationListRows: View {
    @Binding var items: [String]
     
     
    @Binding var newItem: String
    var field: ConfigurationField? = nil
    var format: ConfigurationFieldFormat? = nil
    var ordered = false
    var suggestions: [String] = []
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
     
    @Environment(\.editMode) private var editMode

    private var known: ConfigurationKnownValueSet? { ConfigurationFieldExamples.knownSet(for: field) }
    private var shape: ConfigurationFieldFormat? { format ?? field?.format }
    private var trimmedNew: String { newItem.trimmingCharacters(in: .whitespacesAndNewlines) }

     
     
     
     
     
    static func problem(_ item: String, among others: [String], field: ConfigurationField?,
                        format: ConfigurationFieldFormat?) -> ConfigurationFieldProblem? {
        ConfigurationFieldValidation.problem(item, format: format ?? field?.format, path: field?.path ?? "",
                                             allowed: field?.values ?? [], siblings: others)
    }

     
     
     
    static func misformatted(_ items: [String], field: ConfigurationField?, format: ConfigurationFieldFormat?) -> Set<Int> {
        guard let shape = format ?? field?.format else { return [] }
        let readsOthers = ConfigurationFieldValidation.readsSiblings(path: field?.path ?? "")
        return Set(items.indices.filter { index in
            let item = items[index]
             
             
            if shape == .domain || shape == .host, item.hasPrefix("geosite:") || item.hasPrefix("rule-set:") { return false }
            var others: [String] = []
            if readsOthers {
                others = items
                others.remove(at: index)
            }
            return problem(item, among: others, field: field, format: shape) != nil
        })
    }

     
     
    private var newItemProblem: ConfigurationFieldProblem? {
        trimmedNew.isEmpty ? nil : Self.problem(trimmedNew, among: items, field: field, format: shape)
    }

     
    private var commonValues: [ConfigurationFormatPreset] {
        shape == .dnsServer
            ? ConfigurationFormatPresets.dnsServers(path: field?.path ?? "", copy: fieldCopy, language: .init(locale: locale))
                .filter { !items.contains($0.value ?? "") }
            : []
    }

    private var keyboard: UIKeyboardType {
        switch shape {
        case .url?, .dnsServer?: return .URL
        case .ip?, .cidr?, .ipPort?, .portRange?: return .numbersAndPunctuation
        default: return .asciiCapable
        }
    }

     
     
    @Environment(\.configurationListHoldsRules) private var holdsRules
     
    @State private var openRule: RuleLineRoute?

    struct RuleLineRoute: Identifiable {
        let id = UUID()
        let index: Int?
        let raw: String
    }

    var body: some View {
        if holdsRules { ruleLines } else { textItems }
    }

     
     
     
    private var ruleLines: some View {
        Section {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button { openRule = RuleLineRoute(index: index, raw: item) } label: {
                    ConfigurationRuleRow(item, hasTarget: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("configuration-editor.value.list.rule")
            }
             
            .onDelete(perform: editMode?.wrappedValue.isEditing == true ? nil : { items.remove(atOffsets: $0) })
            .onMove(perform: ordered ? move : nil)
            Button { openRule = RuleLineRoute(index: nil, raw: "") } label: {
                Label { Text(clash: .copy("Add Rule")) } icon: { Image(systemName: ClashSymbol.plus.name) }
            }
            .accessibilityIdentifier("configuration-editor.value.list.rule.add")
            .clashProductModal(item: $openRule, role: .form) { route in
                RuleBuilderAdapter(raw: route.raw, showsPersonalMetadata: false, showsTarget: false) { line in
                    let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !line.isEmpty else { return }
                    if let index = route.index, items.indices.contains(index) {
                        items[index] = line
                    } else if !items.contains(line) {
                        items.append(line)
                    }
                }
                .clashModalPresentation(.page)
            }
        } footer: {
            Text(clash: ConfigurationFieldExamples.listFooter(for: field, format: shape, copy: fieldCopy, locale: locale))
                .accessibilityIdentifier("configuration-editor.value.list.footer")
        }
    }

    @ViewBuilder
    private var textItems: some View {
         
        let misformatted = Self.misformatted(items, field: field, format: shape)
        Section {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack {
                    Text(verbatim: item)
                    if misformatted.contains(index) {
                        Spacer()
                        Image(systemName: ClashSymbol.exclamationmarkTriangle.name).foregroundStyle(.orange)
                    }
                }
                .accessibilityIdentifier("configuration-editor.value.list.item.\(item)")
            }
            .onDelete(perform: editMode?.wrappedValue.isEditing == true ? nil : { items.remove(atOffsets: $0) })
            .onMove(perform: ordered ? move : nil)
            if let known {
                NavigationLink {
                     
                     
                    ConfigurationKnownValuesPage(set: known,
                                                 title: fieldCopy.title(for: field, key: field.map(ConfigurationSectionLayout.key(of:)) ?? "",
                                                                        locale: locale),
                                                 items: $items)
                } label: {
                    Text(clash: .copy("Choose from the List"))
                }
                .accessibilityIdentifier("configuration-editor.value.list.known")
            }
            HStack {
                TextField(text: $newItem, prompt: Text(clash: ConfigurationFieldExamples.prompt(for: field, format: shape,
                                                                                                copy: fieldCopy, locale: locale))) {
                    Text(clash: .copy("Add an Item"))
                }
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .keyboardType(keyboard)
                .submitLabel(.done)
                .onSubmit(add)
                .accessibilityIdentifier("configuration-editor.value.list.add")
                Button(action: add) { Text(clash: .copy("Add")) }
                    .disabled(trimmedNew.isEmpty || newItemProblem != nil)
                    .accessibilityIdentifier("configuration-editor.value.list.add-button")
            }
            if !commonValues.isEmpty {
                Menu {
                    ForEach(commonValues) { preset in
                        Button { items.append(preset.value ?? "") } label: {
                            Text(clash: preset.label)
                            Text(verbatim: preset.value ?? "")
                        }
                    }
                } label: {
                    Label { Text(clash: .copy("Add a Common Server")) } icon: { Image(systemName: ClashSymbol.plus.name) }
                }
                .accessibilityIdentifier("configuration-editor.value.list.common")
            }
            if known == nil, !suggestions.isEmpty {
                Menu {
                    ForEach(suggestions.filter { !items.contains($0) }, id: \.self) { value in
                        Button { items.append(value) } label: { Text(verbatim: value) }
                    }
                } label: {
                    Label { Text(clash: .copy("Add a Suggested Item")) } icon: { Image(systemName: ClashSymbol.plus.name) }
                }
                .accessibilityIdentifier("configuration-editor.value.list.suggestion")
            }
        } header: {
            if ordered && items.count > 1 {
                HStack {
                    Spacer()
                    ConfigurationAmbientReorderButton(identifier: "configuration-editor.value.list.reorder")
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(clash: ConfigurationFieldExamples.listFooter(for: field, format: shape, copy: fieldCopy, locale: locale))
                    .accessibilityIdentifier("configuration-editor.value.list.footer")
                if let note = ConfigurationFieldExamples.listOrderNote(for: field) { Text(clash: note) }
                if let newItemProblem {
                    ConfigurationProblemLine(problem: newItemProblem)
                }
                if !misformatted.isEmpty, let example = ConfigurationFieldExamples.example(for: shape) {
                    Text(clash: .format("Doesn’t look right. For example: %@", [example]))
                }
            }
        }
    }

    private func add() {
        let item = trimmedNew
         
         
        guard !item.isEmpty, !item.contains(where: \.isNewline),
              Self.problem(item, among: items, field: field, format: shape) == nil else { return }
        if !items.contains(item) { items.append(item) }
        newItem = ""
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        items.move(fromOffsets: offsets, toOffset: destination)
    }
}

 
 
struct ConfigurationKnownValuesPage: View {
    let set: ConfigurationKnownValueSet
    let title: String
    @Binding var items: [String]
    @State private var values: [String] = []
    @State private var loaded = false
    @State private var search = ""

    private var shown: [String] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let all = values + items.filter { item in !values.contains { $0.lowercased() == item.lowercased() } }
        return query.isEmpty ? all : all.filter { $0.lowercased().contains(query) }
    }

    private func contains(_ value: String) -> Bool { items.contains { $0.lowercased() == value.lowercased() } }

    var body: some View {
        List {
            if loaded && values.isEmpty {
                Text(clash: .copy("This device has no list for this yet. Update the geo data in Geo Resources."))
                    .foregroundStyle(.secondary)
            }
            ForEach(shown, id: \.self) { value in
                Toggle(isOn: Binding(get: { contains(value) }, set: { on in
                    if on, !contains(value) {
                        items.append(value)
                    } else if !on {
                        items.removeAll { $0.lowercased() == value.lowercased() }
                    }
                })) { Text(verbatim: value) }
                .accessibilityIdentifier("configuration-editor.value.known.\(value)")
            }
        }
        .searchable(text: $search)
        .navigationTitle(Text(verbatim: title))
        .task {
            values = await ConfigurationKnownValues.values(for: set)
            loaded = true
        }
    }
}

 
 
private struct ConfigurationListHoldsRulesKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var configurationListHoldsRules: Bool {
        get { self[ConfigurationListHoldsRulesKey.self] }
        set { self[ConfigurationListHoldsRulesKey.self] = newValue }
    }
}

 
 
private struct ConfigurationKnownValuesLoaderKey: EnvironmentKey {
    static let defaultValue: @Sendable (ConfigurationKnownValueSet) async -> [String] = { set in
        await ConfigurationKnownValues.values(for: set)
    }
}

extension EnvironmentValues {
    var configurationKnownValuesLoader: @Sendable (ConfigurationKnownValueSet) async -> [String] {
        get { self[ConfigurationKnownValuesLoaderKey.self] }
        set { self[ConfigurationKnownValuesLoaderKey.self] = newValue }
    }
}

 
 
 
 
 
 
 
 
struct ConfigurationKnownValueChoices: View {
    let set: ConfigurationKnownValueSet
    let title: String
    @Binding var text: String
     
    var search = ""
     
    var defaultValue: String? = nil
    @Environment(\.configurationKnownValuesLoader) private var load
    @StateObject private var list = ListLoad()
    @State private var custom = CatalogCustomEntry()
     
    @State private var beforeTyping: String?

     
     
     
     
     
     
    @MainActor
    final class ListLoad: ObservableObject {
        @Published private(set) var values: [String] = []
        @Published private(set) var loaded = false
        private var started = false

        func start(_ set: ConfigurationKnownValueSet, _ load: @escaping @Sendable (ConfigurationKnownValueSet) async -> [String]) {
            guard !started else { return }
            started = true
            Task {
                values = await load(set)
                loaded = true
            }
        }
    }

    private var shown: [String] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return query.isEmpty ? list.values : list.values.filter { $0.lowercased().contains(query) }
    }

     
     
     
     
    static func row(for value: String, in values: [String]) -> String? {
        ConfigurationChoiceMatch.choice(for: value, in: values, caseInsensitive: true)
    }

     
     
     
    static func customText(typed: CatalogCustomEntry, value: String, values: [String], loaded: Bool) -> String {
        if typed.isPending { return typed.text }
        guard loaded, row(for: value, in: values) == nil else { return "" }
        return value.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        Section {
            if list.loaded && list.values.isEmpty {
                Text(clash: .copy("This device has no list for this yet. Update the geo data in Geo Resources."))
                    .foregroundStyle(.secondary)
            }
            let defaultRow = defaultValue.flatMap { Self.row(for: $0, in: list.values) }
            Picker(selection: Binding(get: { Self.row(for: text, in: list.values) ?? "" }, set: pick)) {
                ForEach(shown, id: \.self) { value in
                    Text(clash: value == defaultRow ? .format("Default · %@", [value]) : .verbatim(value)).tag(value)
                }
            } label: { Text(verbatim: title) }
            .pickerStyle(.inline)
            .labelsHidden()
            .accessibilityIdentifier("configuration-editor.value.known.choice")
             
             
            .onAppear { list.start(set, load) }
        }
        Section {
            TextField(text: Binding(get: { Self.customText(typed: custom, value: text, values: list.values, loaded: list.loaded) },
                                    set: type),
                      prompt: Text(clash: .copy("Custom"))) {
                Text(clash: .copy("Custom"))
            }
            .textInputAutocapitalization(.characters)
            .disableAutocorrection(true)
            .submitLabel(.done)
            .accessibilityIdentifier("configuration-editor.value.known.custom")
            .onAppear { list.start(set, load) }
        } footer: {
            Text(clash: .copy("Only when the list doesn’t have it."))
        }
    }

    private func pick(_ value: String) {
        text = value
        custom = CatalogCustomEntry()
        beforeTyping = nil
    }

    private func type(_ typed: String) {
        let shown = Self.customText(typed: custom, value: text, values: list.values, loaded: list.loaded)
        guard typed != shown else { return }
         
        if !custom.isPending { custom = CatalogCustomEntry(text: shown) }
        custom.type(typed)
        if beforeTyping == nil { beforeTyping = text }
        let value = typed.trimmingCharacters(in: .whitespaces)
        text = value.isEmpty ? (beforeTyping ?? text) : value
    }
}

 
 
struct ConfigurationKnownValuePickPage: View {
    let set: ConfigurationKnownValueSet
    let title: String
    @Binding var text: String
    @State private var search = ""

    var body: some View {
        List {
            ConfigurationKnownValueChoices(set: set, title: title, text: $text, search: search)
        }
        .searchable(text: $search)
        .navigationTitle(Text(verbatim: title))
    }
}

 
 
private struct ConfigurationKnownValueSearchKey: EnvironmentKey {
    static let defaultValue = ""
}

 
 
 
private struct ConfigurationValueStartsOnCustomKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var configurationValueStartsOnCustom: Bool {
        get { self[ConfigurationValueStartsOnCustomKey.self] }
        set { self[ConfigurationValueStartsOnCustomKey.self] = newValue }
    }
}

extension EnvironmentValues {
    var configurationKnownValueSearch: String {
        get { self[ConfigurationKnownValueSearchKey.self] }
        set { self[ConfigurationKnownValueSearchKey.self] = newValue }
    }
}

 
 
 
struct ConfigurationKnownValueSearch: ViewModifier {
    let field: ConfigurationField?
    @State private var search = ""

    func body(content: Content) -> some View {
        if ConfigurationFieldEditor.picksOneKnownValue(field) {
            content
                .searchable(text: $search)
                .environment(\.configurationKnownValueSearch, search)
        } else {
            content
        }
    }
}

extension View {
     
    func configurationKnownValueSearch(for field: ConfigurationField?) -> some View {
        modifier(ConfigurationKnownValueSearch(field: field))
    }
}

 
 
 
struct ConfigurationInlineFieldRow: View {
    let title: String
    let draft: ConfigurationFieldDraft
    let identifier: String
    let save: (OrderedJSON) -> Void
     
    var isDefault = false
     
    var defaultText: String? = nil
     
     
    var useDefault: (() -> Void)? = nil
     
    var caption: ClashDisplayText? = nil
     
    var field: ConfigurationField? = nil
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

     
    private static let defaultTag = "\u{1F}default"

    init(title: String, draft: ConfigurationFieldDraft, identifier: String, save: @escaping (OrderedJSON) -> Void,
         isDefault: Bool = false, defaultText: String? = nil, useDefault: (() -> Void)? = nil,
         caption: ClashDisplayText? = nil, field: ConfigurationField? = nil) {
        self.title = title
        self.draft = draft
        self.identifier = identifier
        self.save = save
        self.isDefault = isDefault
        self.defaultText = defaultText
        self.useDefault = useDefault
        self.caption = caption
        self.field = field
    }

     
     
    private func words(_ value: String) -> String {
        fieldCopy.valueLabel(value, for: field, locale: locale) ?? value
    }

     
     
    static func draft(field: ConfigurationField, value: OrderedJSON, in document: OrderedJSON) -> ConfigurationFieldDraft? {
        guard ConfigurationSectionLayout.isInline(field, value: value, in: document) else { return nil }
        return ConfigurationFieldDraft(field: field, value: value, in: document)
    }

     
     
     
    static func saving(_ draft: ConfigurationFieldDraft, written: Bool = true,
                       _ change: (inout ConfigurationFieldDraft) -> Void) -> OrderedJSON? {
        var next = draft
        change(&next)
        return !written || next.isChanged ? next.value : nil
    }

     
     
    static func defaultEntry(_ defaultText: String?) -> ClashDisplayText {
         
         
        guard let defaultText, !defaultText.isEmpty else { return .copy("Not set") }
        return .format("Default (%@)", [defaultText])
    }

     
     
     
     
     
    static func menuDefault(field: ConfigurationField?, defaultText: String?, copy: ConfigurationFieldCopy,
                            locale: Locale) -> String? {
        if let field {
             
             
             
             
             
             
            if let unset = copy.entry(for: field, locale: locale)?.unset {
                return copy.valueLabel(unset, for: field, locale: locale) ?? unset
            }
            guard let prompt = ConfigurationValueWords.defaultPrompt(for: field, locale: locale, copy: copy) else { return nil }
            if case .value = field.defaultShape { return copy.valueLabel(prompt, for: field, locale: locale) ?? prompt }
            return prompt
        }
        guard case .value(let text) = ConfigurationField.defaultShape(of: defaultText) else { return nil }
        return text
    }

    var body: some View {
        switch draft.control {
        case .toggle:
            Toggle(isOn: Binding(get: { draft.flag }, set: { flag in
                if let value = Self.saving(draft, written: !isDefault, { $0.flag = flag }) { save(value) }
            })) { label }
            .accessibilityIdentifier(identifier)
        case .number, .text(.ipPort):
             
             
            ConfigurationPresetMenuRow(title: title, draft: draft, identifier: identifier, save: save,
                                       isDefault: isDefault,
                                       defaultText: Self.menuDefault(field: field, defaultText: defaultText, copy: fieldCopy, locale: locale),
                                       useDefault: useDefault, caption: caption)
        default:
            Picker(selection: Binding(get: { isDefault ? Self.defaultTag : draft.text }, set: { choice in
                if choice == Self.defaultTag {
                    if !isDefault { useDefault?() }
                } else if let value = Self.saving(draft, written: !isDefault, { $0.text = choice }) {
                    save(value)
                }
            })) {
                if isDefault || useDefault != nil {
                    Text(clash: Self.defaultEntry(Self.menuDefault(field: field, defaultText: defaultText,
                                                                  copy: fieldCopy, locale: locale)))
                        .tag(Self.defaultTag)
                }
                ForEach(draft.choices, id: \.self) { choice in
                    if draft.unknown.contains(choice) {
                        Label { Text(verbatim: choice) } icon: { Image(systemName: ClashSymbol.exclamationmarkTriangle.name) }
                            .tag(choice)
                    } else {
                        Text(verbatim: words(choice)).tag(choice)
                    }
                }
            } label: { label }
            .pickerStyle(.menu)
            .accessibilityIdentifier(identifier)
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
             
             
             
            if let caption {
                Text(clash: caption).font(.caption).foregroundStyle(.secondary)
            }
            if !isDefault { ConfigurationUnavailableReasons(reasons: draft.unavailableInUse) }
        }
    }
}

 
 
 
struct ConfigurationFormatWarning: View {
    let draft: ConfigurationFieldDraft

    var body: some View {
        if let problem = draft.problem {
            ConfigurationProblemLine(problem: problem)
        } else if !draft.misformatted.isEmpty, let example = draft.format?.example {
            VStack(alignment: .leading, spacing: 2) {
                Text(clash: .format("Doesn’t look right. For example: %@", [example]))
                if case .textList = draft.control {
                    Text(verbatim: draft.misformatted.joined(separator: ", ")).lineLimit(2)
                }
            }
        }
    }
}

struct ConfigurationNewKeyForm: View {
    let suggestions: [String]
    let taken: Set<String>
     
     
    var elsewhere: Set<String> = []
     
     
    var fields: [ConfigurationField] = []
     
    var document: OrderedJSON = .object([])
     
    var entryField: ConfigurationField? = nil
     
    var keyFormat: ConfigurationFieldFormat? = nil
     
     
     
     
    var policyKeys = false
    let save: (String, OrderedJSON) -> Void
    @State private var key = ""
    @State private var policyKind: ConfigurationPolicyKey.Kind = .domain
    @State private var policyValue = ""
    @State private var draft = ConfigurationValueDraft(kind: .text)
     
    @State private var fieldDraft: ConfigurationFieldDraft?
    @State private var fieldDraftKey = ""
    @State private var dismiss = ClashDismissHandle()

    private var name: String {
        guard policyKeys else { return key.trimmingCharacters(in: .whitespaces) }
        let value = policyValue.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? "" : ConfigurationPolicyKey.compose(policyKind, value)
    }

     
    private var ruleSets: [String] { ConfigurationReferenceNames.names([.ruleProvider], in: document) }

     
    @ViewBuilder
    private var policyKeySection: some View {
        Section {
            Picker(selection: $policyKind) {
                ForEach(ConfigurationPolicyKey.Kind.allCases) { Text(clash: $0.title).tag($0) }
            } label: { Text(clash: .copy("Applies To")) }
            .pickerStyle(.menu)
            .accessibilityIdentifier("configuration-editor.new-key.policy-kind")
            switch policyKind {
            case .domain:
                TextField(text: $policyValue, prompt: Text(clash: ConfigurationFieldExamples.prompt(for: .domain))) {
                    Text(clash: .copy("Domain Name"))
                }
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .keyboardType(.URL)
                .accessibilityIdentifier("configuration-editor.new-key.policy-domain")
            case .geosite:
                NavigationLink {
                    ConfigurationKnownValuePickPage(set: .geosite, title: "GEOSITE", text: $policyValue)
                } label: {
                    HStack {
                        Text(clash: .copy("GEOSITE Category"))
                        Spacer()
                        Text(verbatim: policyValue).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("configuration-editor.new-key.policy-geosite")
            case .ruleSet:
                Picker(selection: $policyValue) {
                    Text(verbatim: "").tag("")
                    ForEach(ruleSets, id: \.self) { Text(verbatim: $0).tag($0) }
                } label: { Text(clash: .copy("Rule Set")) }
                .pickerStyle(.menu)
                .accessibilityIdentifier("configuration-editor.new-key.policy-ruleset")
            }
        } footer: {
            if policyKind == .ruleSet && ruleSets.isEmpty {
                Text(clash: .copy("This configuration has no rule sets yet."))
            }
        }
    }

     
     
    private var field: ConfigurationField? { entryField ?? fields.first { Self.key(of: $0) == name } }

     
    static func key(of field: ConfigurationField) -> String { ConfigurationSectionLayout.key(of: field) }

     
    private var knownKeys: [String] {
        var seen = Set(suggestions)
        let catalogKeys = fields.map(Self.key(of:)).filter { seen.insert($0).inserted }
        return suggestions + catalogKeys
    }

     
     
     
    private var value: OrderedJSON {
        if let fieldDraft, fieldDraftKey == name, field != nil { return fieldDraft.value }
        if let kind = field?.kind, kind == .object || kind == .map { return .object([]) }
        return Self.inferredValue(draft.text)
    }

     
     
    static func inferredValue(_ text: String) -> OrderedJSON {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed == "true" || trimmed == "false" || Double(trimmed) != nil { return .scalar(trimmed) }
        return .string(text)
    }

    private var isValid: Bool {
        if let fieldDraft, fieldDraftKey == name, field != nil { return fieldDraft.isValid }
        return true
    }

    var body: some View {
        ClashFeatureNavigationContainer {
            Form {
                if policyKeys {
                    policyKeySection
                } else {
                    keySection
                }
                valueSection
            }
            .navigationTitle(Text(clash: .copy("Add")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(clash: .copy("Cancel")) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save(name, value)
                        dismiss()
                    } label: { Text(clash: .copy("Save")) }
                    .disabled(name.isEmpty || taken.contains(name) || elsewhere.contains(name) || !isValid)
                    .accessibilityIdentifier("configuration-editor.new-key.save")
                }
            }
        }
        .clashCapturesDismiss(dismiss)
        .onChange(of: name) { _ in startFieldDraft() }
        .onChange(of: policyKind) { _ in policyValue = "" }
        .onAppear { if entryField != nil { startFieldDraft() } }
    }

    private var keySection: some View {
        Section {
            TextField(text: $key, prompt: keyFormat.map { Text(clash: ConfigurationFieldExamples.prompt(for: $0)) }) {
                Text(clash: .copy("Key"))
            }
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .accessibilityIdentifier("configuration-editor.new-key.name")
            if !knownKeys.isEmpty {
                Picker(selection: $key) {
                    Text(verbatim: "").tag("")
                    ForEach(knownKeys, id: \.self) { Text(verbatim: $0).tag($0) }
                } label: { Text(clash: .copy("Known Keys")) }
                .accessibilityIdentifier("configuration-editor.new-key.known")
            }
        } footer: {
            if OverridePatch.listenerKeys.contains(name) {
                Text(clash: .copy("Change this in LAN Sharing."))
            } else if elsewhere.contains(name) {
                Text(clash: .copy("This key is changed on another page."))
            } else if let keyFormat, !name.isEmpty, !ConfigurationFieldCheck.check(name, keyFormat),
                      let example = keyFormat.example {
                Text(clash: .format("Doesn’t look right. For example: %@", [example]))
            }
        }
    }

    @ViewBuilder
    private var valueSection: some View {
        if let binding = Binding($fieldDraft), fieldDraftKey == name, field != nil {
            ConfigurationFieldEditor(draft: binding, field: field)
        } else if let kind = field?.kind, kind == .object || kind == .map {
             
        } else {
             
             
            Section {
                TextField(text: $draft.text) { Text(clash: .copy("Value")) }
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .accessibilityIdentifier("configuration-editor.new-key.value")
            }
        }
    }

     
     
    private func startFieldDraft() {
        defer { fieldDraftKey = name }
        if entryField != nil, fieldDraft != nil { return }
        fieldDraft = field.flatMap { ConfigurationFieldDraft(field: $0, value: nil, in: document) }
    }
}

 

 
 
struct ConfigurationReadOnlySectionView: View {
    @ObservedObject var session: ConfigurationEditorSession
    let section: ConfigurationOutlineSection
     
     
    var editSource: (() -> Void)? = nil
     
     
    var leading: AnyView? = nil

    private var entries: [(title: String, value: OrderedJSON)] {
        guard case .object(let items)? = session.page?.document else { return [] }
        let own = items.filter {
            section == .unknown ? ConfigurationOutline.section(forTopLevelKey: $0.key) == .unknown
                : ConfigurationOutline.section(forTopLevelKey: $0.key) == section
        }
         
         
        if own.count == 1, let only = own.first, [.proxies, .proxyProviders, .proxyGroups, .rules, .subRules,
                                                   .ruleProviders, .dns, .sniffer, .tunnels, .ntp,
                                                   .experimental].contains(section) {
            switch only.value {
            case .array(let list):
                return list.enumerated().map { (ConfigurationEditorCopy.entryTitle($0.element, index: $0.offset), $0.element) }
            case .object(let mapping):
                return mapping.map { ($0.key, $0.value) }
            default: break
            }
        }
        return own.map { ($0.key, $0.value) }
    }

     
    static func listKey(_ section: ConfigurationOutlineSection) -> String? {
        switch section {
        case .proxies: "proxies"
        case .proxyProviders: "proxy-providers"
        case .proxyGroups: "proxy-groups"
        case .rules: "rules"
        case .subRules: "sub-rules"
        case .ruleProviders: "rule-providers"
        case .tunnels: "tunnels"
        default: nil
        }
    }

    var body: some View {
        List {
            if let leading { leading }
             
             
             
            if entries.isEmpty, leading == nil {
                if let key = Self.listKey(section) {
                    Text(clash: ConfigurationEmptyList.sentence(for: key)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("configuration-editor.list.empty")
                } else if editSource == nil {
                    Text(clash: .copy("None"))
                        .foregroundStyle(.secondary)
                }
            }
            if let editSource {
                Section {
                    Button(action: editSource) {
                        Label { Text(clash: .copy("Edit Source")) } icon: { Image(systemName: ClashSymbol.curlybraces.name) }
                    }
                    .accessibilityIdentifier("configuration-editor.section.edit-source")
                } footer: {
                    Text(clash: .copy("Change this one in the source."))
                }
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                NavigationLink {
                    ScrollView {
                        Text(verbatim: entry.value.serialized())
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle(Text(verbatim: entry.title))
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: entry.title).lineLimit(1)
                        Spacer()
                        Text(clash: ConfigurationValueWords.words(entry.value, field: nil, locale: AppPreferences.language().locale))
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .navigationTitle(Text(clash: .copy(ConfigurationEditorCopy.title(of: section))))
    }
}

 

 
 
 
struct ConfigurationSchemeRulesLoader: View {
    @ObservedObject var model: ProfilesViewModel
    let profileID: String
    let schemeID: String
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
     
    var focus: ClashTowerRuleFocus = .all
     
    var pushed = false
     
    var savesEachChange = false
    @State private var loaded: Loaded?
    @State private var failure: String?

    struct Loaded {
        let library: ConfigurationLibrarySnapshot
        let scheme: ConfigurationRuleScheme
    }

    var body: some View {
        Group {
            if let loaded {
                ConfigurationTowerRuleCustomizationAdapter(model: model, scheme: loaded.scheme, library: loaded.library,
                                                           pushed: pushed, profileID: profileID, changed: changed, close: close,
                                                           focus: focus, savesEachChange: savesEachChange)
            } else if let failure {
                ClashStatusMessage(text: .copy(failure), kind: .error).padding()
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            do {
                guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                let library = try await Task.detached(priority: .userInitiated) { try store.snapshot() }.value
                 
                 
                guard let scheme = library.rules.first(where: { $0.id == schemeID })
                        ?? ConfigurationBuiltins.schemes.first(where: { $0.id == schemeID }) else {
                    throw ConfigurationLibraryError.missingDependency(schemeID)
                }
                loaded = Loaded(library: library, scheme: scheme)
            } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

 

 
 
 
 
struct ConfigurationOriginalEntriesView: View {
    @ObservedObject var session: ConfigurationEditorSession
    let section: ConfigurationOutlineSection
    @State private var search = ""
    @State private var adding = false
     
     
     
    @State private var editMode: EditMode = .inactive
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    private var isGroups: Bool { section == .proxyGroups }
    private var key: String { isGroups ? "proxy-groups" : "rule-providers" }

    private var entries: [OriginalEntry] { OriginalEntry.all(in: session.value(at: [key])) }

    private var shown: [OriginalEntry] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        let types = ConfigurationTypeWords.names(isGroups ? .proxyGroups : .ruleProviders, copy: fieldCopy, locale: locale)
        List {
            if entries.isEmpty {
                ConfigurationEmptyListRows(key: key) {
                    Button { adding = true } label: {
                        Label { Text(clash: .copy(isGroups ? "Add Policy Group" : "New Rule Set")) } icon: { Image(systemName: ClashSymbol.plus.name) }
                    }
                    .accessibilityIdentifier("configuration-editor.original.add-first")
                }
            }
            ForEach(shown) { entry in
                NavigationLink {
                    ConfigurationOriginalEntryView(session: session, section: section, name: entry.name)
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: entry.name).lineLimit(1)
                        Spacer()
                        Text(verbatim: ConfigurationTypeWords.word(entry.type, in: types)).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("configuration-editor.original.\(key).\(entry.name)")
            }
             
            .onDelete(perform: editMode.isEditing ? nil : delete)
             
            .onMove(perform: isGroups && search.isEmpty ? move : nil)
        }
        .searchable(text: $search)
        .navigationTitle(Text(clash: .copy(ConfigurationEditorCopy.title(of: section))))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isGroups, entries.count > 1 { ConfigurationReorderButton(editMode: $editMode, identifier: "configuration-editor.list.reorder") }
            }
             
            ToolbarItem(placement: .primaryAction) {
                ControlGroup {
                    Button { adding = true } label: { Image(systemName: ClashSymbol.plus.name) }
                        .accessibilityLabel(Text(clash: .copy("Add")))
                        .accessibilityIdentifier("configuration-editor.original.add")
                }
                .clashReaderControlGroupStyle()
            }
        }
        .environment(\.editMode, $editMode)
        .disabled(session.isSaving)
        .sheet(isPresented: $adding) {
            ConfigurationOriginalNewEntryForm(section: section, catalog: session.catalog,
                                              taken: Set(entries.map(\.name))) { name, json in
                let insertion = Self.insertion(of: json, named: name, groups: isGroups, into: session.value(at: [key]))
                Task { await session.editOriginal(insertion.path, insertion.edit) }
            }
            .clashModalPresentation(.form)
        }
    }

    private func delete(_ offsets: IndexSet) {
        let names = offsets.map { shown[$0].name }
        Task {
            for name in names {
                guard let step = OriginalEntry.step(of: name, in: session.value(at: [key])) else { continue }
                guard await session.editOriginal([.key(key), step], .delete) else { return }
            }
        }
    }

     
     
     
     
    static func insertion(of json: String, named name: String, groups: Bool, into section: OrderedJSON?)
        -> (path: [ConfigurationTextPathStep], edit: ConfigurationTextEdit) {
        let key = groups ? "proxy-groups" : "rule-providers"
        switch section {
        case .array(let items)? where groups && !items.isEmpty:
            return ([.key(key), .index(items.count)], .insert(json: json))
        case .object(let entries)? where !groups && !entries.isEmpty:
            return ([.key(key), .key(name)], .insert(json: json))
        default:
            let whole = groups ? "[\(json)]" : "{\(OrderedJSON.string(name).serialized()):\(json)}"
            return ([.key(key)], section == nil ? .insert(json: whole) : .set(json: whole))
        }
    }

    private func move(_ offsets: IndexSet, _ destination: Int) {
        guard let step = OriginalListEdits.moveSteps(offsets, to: destination, under: [.key(key)]).first else { return }
        Task { await session.editOriginal(step.path, step.edit) }
    }

     
     
     
    static func landing(from: Int, dropAt destination: Int) -> Int? {
        let to = destination > from ? destination - 1 : destination
        return to == from ? nil : to
    }
}

 
 
struct ConfigurationOriginalEntryView: View {
    @ObservedObject var session: ConfigurationEditorSession
    let section: ConfigurationOutlineSection
    @State var name: String
    @State private var renaming = false
     
    @State private var visitMembers: [String]?
    private var isGroups: Bool { section == .proxyGroups }
    private var key: String { isGroups ? "proxy-groups" : "rule-providers" }
    private var entryNode: OrderedJSON? {
        OriginalEntry.all(in: session.value(at: [key])).first { $0.name == name }?.value
    }
    private var path: [ConfigurationTextPathStep]? {
        OriginalEntry.step(of: name, in: session.value(at: [key])).map { [.key(key), $0] }
    }
     
    private var document: OrderedJSON { session.page?.document ?? .object([]) }

     
    private var documentSteps: [ConfigurationDocumentStep]? { path.map(Self.documentSteps) }

    static func documentSteps(_ path: [ConfigurationTextPathStep]) -> [ConfigurationDocumentStep] {
        path.map { step in
            switch step {
            case .key(let key): return .key(key)
            case .index(let index): return .index(index)
            }
        }
    }

    var body: some View {
        List {
            Section {
                Button { renaming = true } label: {
                    HStack {
                        Text(clash: .copy("Name"))
                        Spacer()
                        Text(verbatim: name).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("configuration-editor.original.rename")
            }
             
             
             
            ConfigurationEntryFieldRows(entry: entryNode, steps: documentSteps ?? [], document: document,
                                        catalog: session.catalog,
                                        identifiers: .init(inlineIdentifier: "configuration-editor.original.inline",
                                                           fieldIdentifier: "configuration-editor.original.field",
                                                           useDefaultIdentifier: "configuration-editor.original.use-default"),
                                        isSaving: session.isSaving,
                                        members: isGroups ? { value in AnyView(membersRow(value)) } : nil) { key, value, written in
                guard let path else { return }
                Task {
                    if let value {
                        let json = value.serialized()
                        await session.editOriginal(path + [.key(key)], written ? .set(json: json) : .insert(json: json))
                    } else {
                        await session.editOriginal(path + [.key(key)], .delete)
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: name))
        .disabled(session.isSaving)
        .sheet(isPresented: $renaming) {
            ConfigurationRenameSheet(current: name,
                                     taken: Set(OriginalEntry.all(in: session.value(at: [key])).map(\.name))) { newName in
                Task {
                    if await session.renameOriginal(isGroups ? .proxyGroup : .ruleProvider, from: name, to: newName) {
                        name = newName
                    }
                }
            }
            .clashModalPresentation(.form)
        }
    }

     
     
     
     
     
    private func membersRow(_ value: OrderedJSON?) -> some View {
        let members = value.flatMap(ConfigurationOriginalMembersView.names) ?? []
        let shown = ConfigurationMemberSwitches.shown(members: members, visit: visitMembers)
        return Group {
            ForEach(shown, id: \.self) { member in
                Toggle(isOn: Binding(get: { members.contains(member) }, set: { on in
                    setMember(member, on: on, members: members, shown: shown, written: value != nil)
                })) {
                    Text(verbatim: member)
                }
                .accessibilityIdentifier("configuration-editor.original.members.option.\(member)")
            }
            NavigationLink {
                ConfigurationOriginalMembersView(session: session, group: name, members: members) { chosen in
                    guard let path else { return false }
                    let json = OrderedJSON.array(chosen.map(OrderedJSON.string)).serialized()
                    return await session.editOriginal(path + [.key("proxies")], value == nil ? .insert(json: json) : .set(json: json))
                }
            } label: {
                Text(clash: .copy("Add Members…"))
            }
            .accessibilityIdentifier("configuration-editor.original.members")
        }
    }

     
     
     
    private func setMember(_ member: String, on: Bool, members: [String], shown: [String], written: Bool) {
        if visitMembers == nil { visitMembers = shown }
        let next = ConfigurationMemberSwitches.switching(member, on: on, members: members, shown: shown)
        guard next != members, !next.isEmpty, let path else { return }
        let json = OrderedJSON.array(next.map(OrderedJSON.string)).serialized()
        Task { await session.editOriginal(path + [.key("proxies")], written ? .set(json: json) : .insert(json: json)) }
    }

}

 
 
 
 
 
 
 
struct ConfigurationEntryFieldRows: View {
    struct Row: Identifiable, Equatable {
        let key: String
        let field: ConfigurationField?
         
        let value: OrderedJSON?
        let inline: Bool
        var id: String { key }
    }

    let entry: OrderedJSON?
     
    let steps: [ConfigurationDocumentStep]
     
     
    let document: OrderedJSON
    let catalog: ProfilesViewModel.SyntaxCatalog?
    var skip: Set<String> = ["name"]
     
     
    struct Identifiers {
         
        let inlineIdentifier: String
         
        let fieldIdentifier: String
        let useDefaultIdentifier: String
    }
    let identifiers: Identifiers
    var isSaving = false
     
    var members: ((OrderedJSON?) -> AnyView)? = nil
     
     
    var providers: ((OrderedJSON?) -> AnyView?)? = nil
    let write: (_ key: String, _ value: OrderedJSON?, _ written: Bool) -> Void

     
     
     
     
     
    enum Destination: Equatable { case valuePage, map, objectList }

    static func destination(for kind: ConfigurationFieldKind?) -> Destination {
        switch kind {
        case .map?: return .map
        case .objectList?: return .objectList
        default: return .valuePage
        }
    }

     
     
    static func isClassical(_ entry: OrderedJSON?) -> Bool {
        guard case .object(let items)? = entry, let behavior = items.last(where: { $0.key == "behavior" })?.value else { return false }
        switch behavior {
        case .string(let text), .scalar(let text): return text.lowercased() == "classical"
        default: return false
        }
    }

     
     
    static func rows(entry: OrderedJSON?, steps: [ConfigurationDocumentStep], document: OrderedJSON,
                     catalog: ProfilesViewModel.SyntaxCatalog?, skip: Set<String> = ["name"]) -> [Row] {
        var written: [(key: String, value: OrderedJSON)] = []
        if case .object(let items)? = entry { written = items }
        var keys: [(key: String, field: ConfigurationField?)] = catalog?.fieldCatalog.map { fieldCatalog in
            fieldCatalog.children(of: steps, in: document).map { (ConfigurationSectionLayout.key(of: $0), Optional($0)) }
        } ?? []
        var known = Set(keys.map(\.key))
        for item in written where known.insert(item.key).inserted { keys.append((item.key, nil)) }
        return keys.filter { !skip.contains($0.key) }.map { key, field in
            let value = written.last { $0.key == key }?.value
            let inline = field.map { ConfigurationSectionLayout.isInline($0, value: value, in: document) } ?? false
            return Row(key: key, field: field, value: value, inline: inline)
        }
    }

    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

     
     
    static func layoutPath(of rows: [Row]) -> String? {
        rows.compactMap(\.field?.path).first.map { path in
            path.lastIndex(of: ".").map { String(path[..<$0]) } ?? path
        }
    }

     
     
     
     
    var body: some View {
        let rows = Self.rows(entry: entry, steps: steps, document: document, catalog: catalog, skip: skip)
        let byKey = Dictionary(rows.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let layout = Self.layoutPath(of: rows).flatMap { fieldCopy.layout(forPath: $0, locale: locale) } ?? []
        ForEach(ConfigurationFieldCopy.arrange(rows.map(\.key), in: layout)) { section in
            Section {
                ForEach(section.keys.compactMap { byKey[$0] }) { row in rowView(row) }
            } header: {
                if let title = section.title { Text(clash: title) }
            } footer: {
                if let footer = section.footer { Text(verbatim: footer) }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        let title = fieldCopy.title(for: row.field, key: row.key, locale: locale)
        if row.key == "proxies", let members {
            members(row.value)
        } else if row.key == "use", let providers, let row = providers(row.value) {
            row
        } else if row.inline, let field = row.field,
                  let draft = ConfigurationFieldDraft(field: field, value: row.value, in: document) {
            ConfigurationInlineFieldRow(title: title, draft: draft, identifier: identifiers.inlineIdentifier + "." + row.key,
                                        save: { write(row.key, $0, row.value != nil) },
                                        isDefault: row.value == nil, defaultText: field.defaultText,
                                        useDefault: row.value != nil ? { write(row.key, nil, true) } : nil, field: field)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) { useDefault(row) }
        } else {
            NavigationLink {
                switch Self.destination(for: row.field?.kind) {
                case .map:
                    ConfigurationEntryMapPage(title: title, value: row.value, steps: steps + [.key(row.key)],
                                              document: document, catalog: catalog) { write(row.key, $0, row.value != nil) }
                case .objectList:
                    ConfigurationEntryObjectListPage(title: title, value: row.value, steps: steps + [.key(row.key)],
                                                     document: document, catalog: catalog) { write(row.key, $0, row.value != nil) }
                case .valuePage:
                    ConfigurationFieldValuePage(title: title, value: row.value, field: row.field, document: document,
                                                isSaving: isSaving) { write(row.key, $0, row.value != nil) }
                         
                         
                        .environment(\.configurationListHoldsRules, row.key == "payload" && Self.isClassical(entry))
                }
            } label: {
                ConfigurationRowLabel(title: .verbatim(title),
                                      value: ConfigurationValueWords.summary(row.value, field: row.field,
                                                                             locale: AppPreferences.language().locale,
                                                                             copy: fieldCopy),
                                      isDefault: row.value == nil)
            }
            .accessibilityIdentifier(identifiers.fieldIdentifier + "." + row.key)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) { useDefault(row) }
        }
    }

    @ViewBuilder
    private func useDefault(_ row: Row) -> some View {
        if row.value != nil {
            Button { write(row.key, nil, true) } label: { Text(clash: .copy("Use Default")) }
                .tint(.orange)
                .accessibilityIdentifier(identifiers.useDefaultIdentifier)
        }
    }
}

 
 
 
 
 
 
struct ConfigurationSchemeGroupPage: View {
    let catalog: ProfilesViewModel.SyntaxCatalog?
    @StateObject private var editor: ConfigurationSchemeGroupEditor
     
    @State private var visitMembers: [String]?
     
    @State private var visitProviders: [String]?

    init(request: ClashTowerGroupPageRequest, catalog: ProfilesViewModel.SyntaxCatalog?) {
        self.catalog = catalog
        _editor = StateObject(wrappedValue: ConfigurationSchemeGroupEditor(request: request))
    }

    private var request: ClashTowerGroupPageRequest { editor.request }

     
     
    private var context: OrderedJSON {
        var groups = request.all.map(\.document)
        if groups.indices.contains(request.index) { groups[request.index] = editor.document }
        return .object([("proxy-groups", .array(groups))])
    }

    var body: some View {
        List {
            Section {
                TextField("Group Name", text: $editor.name)
                    .onSubmit { Task { await editor.rename() } }
                    .accessibilityIdentifier("configuration.rules.group.name")
            }
             
            ConfigurationEntryFieldRows(entry: editor.document, steps: [.key("proxy-groups"), .index(request.index)],
                                        document: context, catalog: catalog,
                                        identifiers: .init(inlineIdentifier: "configuration.rules.group.inline",
                                                           fieldIdentifier: "configuration.rules.group.field",
                                                           useDefaultIdentifier: "configuration.rules.group.use-default"),
                                        members: { value in AnyView(membersRow(value)) },
                                        providers: { value in providersRow(value) }) { key, value, _ in
                Task { await editor.write(key, value) }
            }
        }
        .navigationTitle(Text(verbatim: editor.name.isEmpty ? request.group.name : editor.name))
        .onDisappear { Task { await editor.rename() } }
         
        .alert(Text(clash: .copy("Not Saved")),
               isPresented: Binding(get: { editor.refusal != nil }, set: { if !$0 { editor.refusal = nil } })) {
            Button(role: .cancel) { editor.refusal = nil } label: { Text(clash: .copy("OK")) }
        } message: {
            Text(verbatim: editor.refusal ?? "")
        }
    }

     
     
     
     
     
     
     
     
    private func membersRow(_ value: OrderedJSON?) -> some View {
        let members = value.flatMap(ConfigurationOriginalMembersView.names) ?? []
        let shown = ConfigurationMemberSwitches.shown(members: members, visit: visitMembers)
        return Group {
            ForEach(shown, id: \.self) { member in
                Toggle(isOn: Binding(get: { members.contains(member) }, set: { on in
                    setMember(member, on: on, members: members, shown: shown)
                })) {
                    Text(verbatim: member)
                }
                .accessibilityIdentifier("configuration.rules.group.members.option.\(member)")
            }
            NavigationLink {
                ConfigurationMembersChecklist(title: editor.name, members: members, options: memberOptions,
                                              allowsEmpty: ConfigurationMemberSwitches.drawsFromSomething(editor.document, proxies: [], use: writtenUses)) { chosen in
                    await editor.write("proxies", chosen.isEmpty ? nil : .array(chosen.map(OrderedJSON.string)))
                }
            } label: {
                Text(clash: .copy("Add Members…"))
            }
            .accessibilityIdentifier("configuration.rules.group.members")
        }
    }

     
     
    private func setMember(_ member: String, on: Bool, members: [String], shown: [String]) {
        if visitMembers == nil { visitMembers = shown }
        let next = ConfigurationMemberSwitches.switching(member, on: on, members: members, shown: shown)
        guard next != members, ConfigurationMemberSwitches.drawsFromSomething(editor.document, proxies: next, use: writtenUses) else { return }
        Task { await editor.write("proxies", next.isEmpty ? nil : .array(next.map(OrderedJSON.string))) }
    }

     
    private var writtenMembers: [String] { editor.document.topLevelValue("proxies").flatMap(ConfigurationOriginalMembersView.names) ?? [] }
    private var writtenUses: [String] { editor.document.topLevelValue("use").flatMap(ConfigurationOriginalMembersView.names) ?? [] }

     
     
     
     
     
     
     
    private func providersRow(_ value: OrderedJSON?) -> AnyView? {
        let uses = value.flatMap(ConfigurationOriginalMembersView.names) ?? []
        guard !uses.isEmpty || !providerOptions.isEmpty else { return nil }
        let shown = ConfigurationMemberSwitches.shown(members: uses, visit: visitProviders)
        return AnyView(Group {
            ForEach(shown, id: \.self) { provider in
                Toggle(isOn: Binding(get: { uses.contains(provider) }, set: { on in
                    setProvider(provider, on: on, uses: uses, shown: shown)
                })) {
                    Text(verbatim: provider)
                }
                .accessibilityIdentifier("configuration.rules.group.providers.option.\(provider)")
            }
            NavigationLink {
                ConfigurationMembersChecklist(title: editor.name, members: uses, options: providerOptions,
                                              allowsEmpty: ConfigurationMemberSwitches.drawsFromSomething(editor.document, proxies: writtenMembers, use: [])) { chosen in
                    await editor.write("use", chosen.isEmpty ? nil : .array(chosen.map(OrderedJSON.string)))
                }
            } label: {
                Text(clash: .copy("Add Proxy Providers…"))
            }
            .accessibilityIdentifier("configuration.rules.group.providers")
        })
    }

     
     
     
     
    private func setProvider(_ provider: String, on: Bool, uses: [String], shown: [String]) {
        if visitProviders == nil { visitProviders = shown }
        let next = ConfigurationMemberSwitches.switching(provider, on: on, members: uses, shown: shown)
        guard next != uses, ConfigurationMemberSwitches.drawsFromSomething(editor.document, proxies: writtenMembers, use: next) else { return }
        Task { await editor.write("use", next.isEmpty ? nil : .array(next.map(OrderedJSON.string))) }
    }

     
    private var providerOptions: [(title: ClashDisplayText, names: [String])] {
        request.nodeSections.filter { $0.kind == .providers }.map { (.verbatim($0.sourceLabel ?? $0.id), $0.names) }
    }

     
     
    private var memberOptions: [(title: ClashDisplayText, names: [String])] {
        let type: String? = { if case .string(let value)? = editor.document.topLevelValue("type") { return value }; return nil }()
        var options: [(title: ClashDisplayText, names: [String])] = [
            (.copy("Built-in"), ConfigurationMembersSources.builtins(catalog: catalog?.fieldCatalog, groupType: type)),
            (.copy("Policy Groups"), request.all.map(\.name).filter { $0 != request.group.name }),
        ]
        for section in request.nodeSections where section.kind == .source {
            options.append((.verbatim(section.sourceLabel ?? section.id), section.names))
        }
        return options
    }
}

 
 
 
 
@MainActor
final class ConfigurationSchemeGroupEditor: ObservableObject {
    let request: ClashTowerGroupPageRequest
    @Published private(set) var document: OrderedJSON
    @Published var name: String
     
    @Published var refusal: String?
     
    private var saved: OrderedJSON

    init(request: ClashTowerGroupPageRequest) {
        self.request = request
        document = request.group.document
        saved = request.group.document
        name = request.group.name
    }

     
     
    @discardableResult
    func write(_ key: String, _ value: OrderedJSON?) async -> Bool {
        await commit(value.map { saved.settingTopLevel(key, to: $0) } ?? saved.removingTopLevel(key))
    }

     
     
    @discardableResult
    func rename() async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, saved.topLevelValue("name") != .string(trimmed) else { return true }
        return await commit(saved.settingTopLevel("name", to: .string(trimmed)))
    }

    private func commit(_ next: OrderedJSON) async -> Bool {
        document = next
        do {
            try await request.save(next)
            saved = next
            refusal = nil
            return true
        } catch {
            document = saved
            if case .string(let current)? = saved.topLevelValue("name") { name = current }
            refusal = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}

 
 
 
 
 
enum ConfigurationMemberSwitches {
     
     
     
     
     
    static func drawsFromSomething(_ document: OrderedJSON, proxies: [String], use: [String]) -> Bool {
        guard proxies.isEmpty, use.isEmpty else { return true }
         
        return ["include-all", "include-all-proxies", "include-all-providers"].contains { key in
            document.topLevelValue(key) == .scalar("true")
        }
    }

     
     
     
    static func shown(members: [String], visit: [String]?) -> [String] {
        guard let visit else { return members }
        var rows = members
        for (index, name) in visit.enumerated() where !rows.contains(name) {
            rows.insert(name, at: slot(after: visit[..<index], in: rows))
        }
        return rows
    }

     
     
     
    static func switching(_ member: String, on: Bool, members: [String], shown: [String]) -> [String] {
        guard on else { return members.filter { $0 != member } }
        guard !members.contains(member) else { return members }
        guard let index = shown.firstIndex(of: member) else { return members + [member] }
        var next = members
        next.insert(member, at: slot(after: shown[..<index], in: members))
        return next
    }

     
     
    private static func slot(after before: ArraySlice<String>, in list: [String]) -> Int {
        before.reversed().first(where: list.contains).flatMap { list.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
    }
}

 
 
 
enum ConfigurationMembersSources {
    static func builtins(catalog: ConfigurationFieldCatalog?, groupType: String?) -> [String] {
        let path = "proxy-groups[" + (groupType ?? "select") + "].proxies"
        let sources = catalog?.field(atCatalogPath: path)?.refers
            ?? catalog?.field(atCatalogPath: "proxy-groups[].proxies")?.refers
        guard let sources, sources.contains(.builtin) || sources.contains(.policy) else {
            return ConfigurationReferenceNames.builtinPolicies
        }
        return ConfigurationReferenceNames.names([.builtin], in: .object([]))
    }
}

 
 
 
 
 
struct ConfigurationMembersChecklist: View {
    let title: String
    let options: [(title: ClashDisplayText, names: [String])]
     
     
    let allowsEmpty: Bool
    let save: ([String]) async -> Bool
    @State private var members: [String]
    @State private var editMode: EditMode = .inactive

    init(title: String, members: [String], options: [(title: ClashDisplayText, names: [String])],
         allowsEmpty: Bool = false, save: @escaping ([String]) async -> Bool) {
        self.title = title
        self.options = options
        self.allowsEmpty = allowsEmpty
        self.save = save
        _members = State(initialValue: members)
    }

    var body: some View {
        List {
            Section {
                ForEach(members, id: \.self) { name in Text(verbatim: name) }
                    .onDelete(perform: editMode.isEditing ? nil : { offsets in change { $0.remove(atOffsets: offsets) } })
                    .onMove { from, to in change { $0.move(fromOffsets: from, toOffset: to) } }
            } header: { Text("Selected (in priority order)") }
            ForEach(Array(sections.enumerated()), id: \.offset) { _, option in
                if !option.names.isEmpty {
                    Section {
                         
                         
                        ForEach(option.names, id: \.self) { name in
                            Toggle(isOn: Binding(get: { members.contains(name) }, set: { on in
                                change { list in
                                    if on, !list.contains(name) { list.append(name) }
                                    if !on { list.removeAll { $0 == name } }
                                }
                            })) {
                                Text(verbatim: name)
                            }
                            .accessibilityIdentifier("configuration-editor.members.option.\(name)")
                        }
                    } header: { Text(clash: option.title) }
                }
            }
        }
        .navigationTitle(Text(verbatim: title))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if members.count > 1 {
                    ConfigurationReorderButton(editMode: $editMode, identifier: "configuration-editor.members.reorder")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .accessibilityIdentifier("configuration-editor.members.list")
    }

     
     
     
    private var sections: [(title: ClashDisplayText, names: [String])] {
        let offered = Set(options.flatMap(\.names))
        let unknown = members.filter { !offered.contains($0) }
        return unknown.isEmpty ? options : options + [(.copy("Not Found"), unknown)]
    }

    private func change(_ edit: (inout [String]) -> Void) {
        let before = members
        var after = members
        edit(&after)
        guard after != before, allowsEmpty || !after.isEmpty else { return }
        members = after
        Task { if await !save(after) { members = before } }
    }
}

 
 
 
struct ConfigurationEntryMapPage: View {
    let title: String
    let value: OrderedJSON?
     
    let steps: [ConfigurationDocumentStep]
    let document: OrderedJSON
    let catalog: ProfilesViewModel.SyntaxCatalog?
    let save: (OrderedJSON?) -> Void
    @State private var entries: [(key: String, value: OrderedJSON)] = []
    @State private var adding = false
    @Environment(\.configurationFieldCopy) private var fieldCopy

    private var mapField: ConfigurationField? { catalog?.fieldCatalog?.field(at: steps, in: document) }
    private func entryField(_ key: String) -> ConfigurationField? {
        catalog?.fieldCatalog?.field(at: steps + [.key(key)], in: document)
    }

    var body: some View {
        List {
            Section {
                ForEach(entries.indices, id: \.self) { position in
                    let entry = entries[position]
                    NavigationLink {
                        ConfigurationFieldValuePage(title: entry.key, value: entry.value, field: entryField(entry.key),
                                                    document: document) { write(entry.key, $0) }
                    } label: {
                         
                         
                        ConfigurationRowLabel(title: .verbatim(entry.key),
                                              value: ConfigurationValueWords.summary(entry.value, field: entryField(entry.key),
                                                                                     locale: AppPreferences.language().locale,
                                                                                     copy: fieldCopy))
                    }
                    .accessibilityIdentifier("configuration-editor.entry-map.entry.\(entry.key)")
                }
                .onDelete { offsets in
                    let keys = offsets.map { entries[$0].key }
                    for key in keys { write(key, nil) }
                }
                if entries.isEmpty {
                     
                    Button { adding = true } label: {
                        Label { Text(clash: .copy("Add")) } icon: { Image(systemName: ClashSymbol.plus.name) }
                    }
                    .accessibilityIdentifier("configuration-editor.entry-map.add-first")
                }
            }
        }
        .navigationTitle(Text(verbatim: title))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ControlGroup {
                    Button { adding = true } label: { Image(systemName: ClashSymbol.plus.name) }
                        .accessibilityLabel(Text(clash: .copy("Add")))
                        .accessibilityIdentifier("configuration-editor.entry-map.add")
                }
                .clashReaderControlGroupStyle()
            }
        }
        .sheet(isPresented: $adding) {
            ConfigurationNewKeyForm(suggestions: mapField?.key?.values ?? [], taken: Set(entries.map(\.key)),
                                    document: document, entryField: entryField("\u{1F}"),
                                    keyFormat: mapField?.key?.format) { key, value in
                write(key, value)
            }
            .clashModalPresentation(.form)
        }
        .onAppear {
            if case .object(let items)? = value { entries = items }
        }
    }

     
    private func write(_ key: String, _ entryValue: OrderedJSON?) {
        var next = entries.filter { $0.key != key }
        if let entryValue {
            if let index = entries.firstIndex(where: { $0.key == key }) {
                next.insert((key, entryValue), at: min(index, next.count))
            } else {
                next.append((key, entryValue))
            }
        }
        entries = next
        save(next.isEmpty ? nil : .object(next))
    }
}

 
 
 
 
struct ConfigurationEntryObjectListPage: View {
    let title: String
    let value: OrderedJSON?
    let steps: [ConfigurationDocumentStep]
    let document: OrderedJSON
    let catalog: ProfilesViewModel.SyntaxCatalog?
    let save: (OrderedJSON?) -> Void
    @State private var items: [OrderedJSON] = []
    @State private var adding = false
    @State private var editMode: EditMode = .inactive
    @Environment(\.configurationFieldCopy) private var fieldCopy

    var body: some View {
        List {
            Section {
                if items.isEmpty {
                    ConfigurationEmptyListRows(key: "") {
                        Button { adding = true } label: {
                            Label { Text(clash: .copy("Add")) } icon: { Image(systemName: ClashSymbol.plus.name) }
                        }
                        .accessibilityIdentifier("configuration-editor.entry-list.add-first")
                    }
                }
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    NavigationLink {
                        List {
                            ConfigurationEntryFieldRows(entry: item, steps: steps + [.index(index)], document: document,
                                                        catalog: catalog, skip: [],
                                                        identifiers: .init(inlineIdentifier: "configuration-editor.entry-list.inline",
                                                                           fieldIdentifier: "configuration-editor.entry-list.field",
                                                                           useDefaultIdentifier: "configuration-editor.entry-list.use-default")) { key, fieldValue, _ in
                                writeItem(index, key, fieldValue)
                            }
                        }
                        .navigationTitle(Text(verbatim: ConfigurationObjectList.title(of: item, index: index)))
                    } label: {
                        ConfigurationRowLabel(title: .verbatim(ConfigurationObjectList.title(of: item, index: index)),
                                              value: ConfigurationValueWords.summary(item, field: catalog?.fieldCatalog?.field(
                                                  at: steps + [.index(index)], in: document), locale: AppPreferences.language().locale,
                                                  copy: fieldCopy))
                    }
                    .accessibilityIdentifier("configuration-editor.entry-list.item.\(index)")
                }
                 
                .onDelete(perform: editMode.isEditing ? nil : { offsets in
                    items.remove(atOffsets: offsets)
                    save(items.isEmpty ? nil : .array(items))
                })
                .onMove { from, to in
                    items.move(fromOffsets: from, toOffset: to)
                    save(.array(items))
                }
            }
        }
        .navigationTitle(Text(verbatim: title))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ControlGroup {
                    Button { adding = true } label: { Image(systemName: ClashSymbol.plus.name) }
                        .accessibilityLabel(Text(clash: .copy("Add")))
                        .accessibilityIdentifier("configuration-editor.entry-list.add")
                }
                .clashReaderControlGroupStyle()
            }
             
            ToolbarItem(placement: .navigationBarTrailing) {
                if items.count > 1 {
                    ConfigurationReorderButton(editMode: $editMode, identifier: "configuration-editor.entry-list.reorder")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .sheet(isPresented: $adding) {
            ConfigurationEntryNewItemForm(form: Self.newItem(fields: itemFields)) { item in
                items.append(item)
                save(.array(items))
            }
            .clashModalPresentation(.form)
        }
        .onAppear {
            if case .array(let written)? = value { items = written }
        }
    }

     
     
     
     
     
     
    static func newItem(fields: [ConfigurationField]) -> ConfigurationNewItem {
        ConfigurationNewItem(type: nil, asked: fields.filter { ![.object, .map, .objectList].contains($0.kind) }.map {
            ConfigurationNewItem.Asked(key: ConfigurationNewItem.key(of: $0), field: $0, isRequired: $0.isRequired, children: [])
        })
    }

     
    private var itemFields: [ConfigurationField] {
        catalog?.fieldCatalog?.children(of: steps + [.index(items.count)], in: document) ?? []
    }

    private func writeItem(_ index: Int, _ key: String, _ fieldValue: OrderedJSON?) {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        items[index] = fieldValue.map { item.settingTopLevel(key, to: $0) } ?? item.removingTopLevel(key)
        save(.array(items))
    }
}

 
 
 
 
 
 
struct ConfigurationEntryNewItemForm: View {
    let form: ConfigurationNewItem
    let add: (OrderedJSON) -> Void
    @State private var values: [String: ConfigurationNewItem.Value] = [:]
    @State private var dismiss = ClashDismissHandle()

    private var filled: [String: ConfigurationNewItem.Value] { ConfigurationNewItemFields.filled(form, values) }

    var body: some View {
        ClashFeatureNavigationContainer {
            Form {
                ConfigurationNewItemFields(form: form, values: $values,
                                           identifierPrefix: "configuration-editor.entry-list.new",
                                           addLineIdentifier: "configuration-editor.entry-list.new.add-line")
            }
            .navigationTitle(Text(clash: .copy("Add")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(clash: .copy("Cancel")) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        add(form.item(filled))
                        dismiss()
                    } label: { Text(clash: .copy("Add")) }
                    .disabled(!form.canAdd(filled))
                    .accessibilityIdentifier("configuration-editor.entry-list.new.add")
                }
            }
        }
        .clashCapturesDismiss(dismiss)
    }
}

 
 
 
 
struct ConfigurationFieldValuePage: View {
    let title: String
    let value: OrderedJSON?
    let field: ConfigurationField?
    let document: OrderedJSON
    var isSaving = false
    let save: (OrderedJSON) -> Void
    @State private var draft: ConfigurationDraft?
    @State private var opened: ConfigurationDraft?
     
    @State private var handed: OrderedJSON?
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    var body: some View {
        let words = fieldCopy.entry(for: field, locale: locale)
        Form {
            if let draft = Binding($draft) {
                if let presets = words?.presets, !presets.isEmpty, field?.format != .ipPort {
                    ConfigurationFieldPresets(draft: draft, presets: presets, defaultValue: field?.defaultText)
                }
                ConfigurationDraftEditor(draft: draft, choices: nil, field: field)
            } else if let value {
                Section {
                    Text(verbatim: value.serialized()).font(.footnote.monospaced()).textSelection(.enabled)
                } footer: {
                    Text(clash: .copy("Change this one in the source."))
                }
            }
             
             
            ConfigurationFieldAbout(summary: draft?.isList == true ? nil : words?.summary,
                                    key: field.map(ConfigurationSectionLayout.key(of:)))
        }
        .configurationKnownValueSearch(for: field)
        .navigationTitle(Text(verbatim: title))
        .disabled(isSaving)
        .onAppear {
            if draft == nil {
                draft = ConfigurationDraft.make(value, field: field, in: document)
                opened = draft
            }
        }
        .onDisappear { commit() }
    }

    private func commit() {
        guard let changed = ConfigurationDraft.handedOn(draft, since: &opened, expected: handed ?? value) else { return }
        handed = changed
        save(changed)
    }
}

 
struct OriginalEntry: Identifiable {
    let name: String
    let value: OrderedJSON
    var id: String { name }
    var type: String? {
        guard case .object(let items) = value, let type = items.first(where: { $0.key == "type" })?.value else { return nil }
        return ConfigurationEditorCopy.plain(type)
    }

     
    static func all(in node: OrderedJSON?) -> [OriginalEntry] {
        switch node {
        case .array(let items)?:
            return items.enumerated().map {
                OriginalEntry(name: ConfigurationEditorCopy.entryTitle($0.element, index: $0.offset), value: $0.element)
            }
        case .object(let pairs)?:
            return pairs.map { OriginalEntry(name: $0.key, value: $0.value) }
        default:
            return []
        }
    }

     
     
    static func step(of name: String, in node: OrderedJSON?) -> ConfigurationTextPathStep? {
        switch node {
        case .array?:
            return all(in: node).firstIndex { $0.name == name }.map { .index($0) }
        case .object(let pairs)?:
            return pairs.contains { $0.key == name } ? .key(name) : nil
        default:
            return nil
        }
    }
}

 
 
struct ConfigurationOriginalValueView: View {
    @ObservedObject var session: ConfigurationEditorSession
    let title: String
    let value: OrderedJSON
    let choices: [String]?
     
    var field: ConfigurationField? = nil
    let save: (String) async -> Void
    @State private var draft: ConfigurationDraft?
    @State private var dismiss = ClashDismissHandle()
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    var body: some View {
        let words = fieldCopy.entry(for: field, locale: locale)
        Form {
            if let draft = Binding($draft) {
                if let presets = words?.presets, !presets.isEmpty, field?.format != .ipPort {
                    ConfigurationFieldPresets(draft: draft, presets: presets, defaultValue: field?.defaultText)
                }
                ConfigurationDraftEditor(draft: draft, choices: choices, field: field)
            } else {
                Section {
                    Text(verbatim: value.serialized()).font(.footnote.monospaced()).textSelection(.enabled)
                } footer: {
                    Text(clash: .copy("Change this one in the source."))
                }
            }
             
             
            ConfigurationFieldAbout(summary: draft?.isList == true ? nil : words?.summary,
                                    key: field.map(ConfigurationSectionLayout.key(of:)))
        }
        .navigationTitle(Text(verbatim: title))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if let draft {
                    Button {
                        Task {
                            await save(draft.value.serialized())
                            dismiss()
                        }
                    } label: { Text(clash: .copy("Save")) }
                    .disabled(draft.value == value || !draft.isValid || session.isSaving)
                    .accessibilityIdentifier("configuration-editor.original.value.save")
                }
            }
        }
        .clashCapturesDismiss(dismiss)
        .onAppear {
            if draft == nil { draft = ConfigurationDraft.make(value, field: field, in: session.page?.document ?? .object([])) }
        }
    }
}

 
 
struct ConfigurationOriginalNewEntryForm: View {
    let section: ConfigurationOutlineSection
    let catalog: ProfilesViewModel.SyntaxCatalog?
    let taken: Set<String>
    let save: (String, String) -> Void
    @State private var name = ""
    @State private var type = ""
    @State private var behavior = ""
    @State private var format = ""
    @State private var location = ""
    @State private var dismiss = ClashDismissHandle()
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    private var isGroups: Bool { section == .proxyGroups }
    private var types: [String] {
        isGroups ? (catalog?.groupTypes.map(\.name) ?? []) : (catalog?.ruleProvider.types ?? [])
    }

     
     
     
    private func field(_ path: String) -> ConfigurationField? { catalog?.fieldCatalog?.field(atCatalogPath: path) }
    private var typeField: ConfigurationField? {
        isGroups ? catalog?.fieldCatalog?.fields.first { $0.path.hasPrefix("proxy-groups[") && $0.path.hasSuffix("].type") }
            : field("rule-providers.*.type")
    }
    private var behaviorField: ConfigurationField? { field("rule-providers.*.behavior") }
    private var formatField: ConfigurationField? { field("rule-providers.*.format") }
    private var locationField: ConfigurationField? { field(type == "http" ? "rule-providers.*.url" : "rule-providers.*.path") }
    private func label(_ field: ConfigurationField?, key: String) -> Text {
        Text(verbatim: fieldCopy.title(for: field, key: key, locale: locale))
    }
    private func name(_ value: String, _ field: ConfigurationField?) -> Text {
        Text(verbatim: fieldCopy.valueLabel(value, for: field, locale: locale) ?? value)
    }
    private var formatDefault: ClashDisplayText {
        let unset = fieldCopy.entry(for: formatField, locale: locale)?.unset
        if let named = unset.map({ fieldCopy.valueLabel($0, for: formatField, locale: locale) ?? $0 }) {
            return .format("Default: %@", [named])
        }
        return ConfigurationValueWords.summary(nil, field: formatField, locale: locale, copy: fieldCopy)
    }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var valid: Bool {
        !trimmedName.isEmpty && !taken.contains(trimmedName) && !type.isEmpty
            && (isGroups || (!behavior.isEmpty && (type == "inline" || !location.trimmingCharacters(in: .whitespaces).isEmpty)))
    }

     
    static func json(groups: Bool, name: String, type: String, behavior: String, format: String, location: String) -> String {
        var entries: [(key: String, value: OrderedJSON)] = []
        if groups {
            entries = [("name", .string(name)), ("type", .string(type)), ("proxies", .array([.string("DIRECT")]))]
        } else {
            entries = [("type", .string(type)), ("behavior", .string(behavior))]
            if !format.isEmpty { entries.append(("format", .string(format))) }
            if type == "http" { entries += [("url", .string(location)), ("interval", .scalar("86400"))] }
            if type == "file" { entries.append(("path", .string(location))) }
            if type == "inline" { entries.append(("payload", .array([]))) }
        }
        return OrderedJSON.object(entries).serialized()
    }

    var body: some View {
        ClashFeatureNavigationContainer {
            Form {
                Section {
                    TextField(text: $name) { Text(clash: .copy("Name")) }
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .accessibilityIdentifier("configuration-editor.original.new.name")
                    Picker(selection: $type) {
                        ForEach(types, id: \.self) { name($0, typeField).tag($0) }
                    } label: { label(typeField, key: "type") }
                    .accessibilityIdentifier("configuration-editor.original.new.type")
                    if !isGroups {
                        Picker(selection: $behavior) {
                            ForEach(catalog?.ruleProvider.behaviors ?? [], id: \.self) { name($0, behaviorField).tag($0) }
                        } label: { label(behaviorField, key: "behavior") }
                        .accessibilityIdentifier("configuration-editor.original.new.behavior")
                        Picker(selection: $format) {
                             
                             
                             
                            Text(clash: formatDefault).tag("")
                            ForEach(catalog?.ruleProvider.formats ?? [], id: \.self) { name($0, formatField).tag($0) }
                        } label: { label(formatField, key: "format") }
                        .accessibilityIdentifier("configuration-editor.original.new.format")
                        if type == "http" || type == "file" {
                            TextField(text: $location,
                                      prompt: fieldCopy.entry(for: locationField, locale: locale)?.example.map { Text(verbatim: $0) }) {
                                label(locationField, key: type == "http" ? "url" : "path")
                            }
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .keyboardType(type == "http" ? .URL : .default)
                                .accessibilityIdentifier("configuration-editor.original.new.location")
                        }
                    }
                }
            }
            .navigationTitle(Text(clash: .copy("Add")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(clash: .copy("Cancel")) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save(trimmedName, Self.json(groups: isGroups, name: trimmedName, type: type, behavior: behavior,
                                                    format: format, location: location.trimmingCharacters(in: .whitespaces)))
                        dismiss()
                    } label: { Text(clash: .copy("Save")) }
                    .disabled(!valid)
                    .accessibilityIdentifier("configuration-editor.original.new.save")
                }
            }
        }
        .clashCapturesDismiss(dismiss)
        .onAppear {
            if type.isEmpty { type = types.first ?? "" }
            if behavior.isEmpty { behavior = catalog?.ruleProvider.behaviors?.first ?? "" }
        }
    }
}

struct ConfigurationRenameSheet: View {
    let current: String
    let taken: Set<String>
    let save: (String) -> Void
    @State private var name = ""
    @State private var dismiss = ClashDismissHandle()

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ClashFeatureNavigationContainer {
            Form {
                Section {
                    TextField(text: $name) { Text(clash: .copy("Name")) }
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .accessibilityIdentifier("configuration-editor.rename.name")
                } footer: {
                    Text(clash: .copy("Every place that names it is renamed with it."))
                }
            }
            .navigationTitle(Text(clash: .copy("Rename")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(clash: .copy("Cancel")) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save(trimmed)
                        dismiss()
                    } label: { Text(clash: .copy("Save")) }
                    .disabled(trimmed.isEmpty || trimmed == current || taken.contains(trimmed))
                    .accessibilityIdentifier("configuration-editor.rename.save")
                }
            }
        }
        .clashCapturesDismiss(dismiss)
        .onAppear { if name.isEmpty { name = current } }
    }
}

 

enum ConfigurationEditorCopy {
     
     
     
     
    static func title(of section: ConfigurationOutlineSection) -> String {
        switch section {
        case .general: "General Configuration (Configuration Chapter)"
        case .dns: "DNS"
        case .sniffer: "Domain Sniffing (Configuration Chapter)"
        case .mitm: "MITM Interception (Configuration Chapter)"
        case .inbound: "Inbounds (Configuration Chapter)"
        case .proxies: "Proxies (Configuration Chapter)"
        case .proxyProviders: "Proxy Providers (Configuration Chapter)"
        case .proxyGroups: "Proxy Groups (Configuration Chapter)"
        case .rules: "Route Rules (Configuration Chapter)"
        case .ruleProviders: "Rule Providers (Configuration Chapter)"
        case .subRules: "Sub-rules"
        case .tunnels: "Tunnels (Configuration Chapter)"
        case .ntp: "NTP"
        case .experimental: "Experimental (Configuration Chapter)"
        case .unknown: "Unknown Keys"
        case .customRules: "Custom Rules"
        case .overrideScript: "Override Script"
        }
    }

     
    static func plain(_ value: OrderedJSON) -> String? {
        switch value {
        case .string(let text): return text
        case .scalar(let token): return token
        default: return nil
        }
    }

     
    static func key(of section: ConfigurationOutlineSection) -> String {
        switch section {
        case .dns: "dns"
        case .sniffer: "sniffer"
        case .mitm: "mitm"
        default: section.rawValue
        }
    }

     
     
     
     
     
     
     
    static func value(of row: ConfigurationOutlineRow, snifferEnabled: Bool? = nil,
                      mitmEnabled: Bool? = nil) -> ClashDisplayText? {
        switch row.section {
        case .sniffer:
            return snifferEnabled.map { .copy($0 ? "On" : "Off") }
        case .mitm:
            return mitmEnabled.map { .copy($0 ? "On" : "Off") }
        case .overrideScript:
            return nil
        default:
            if ConfigurationOutline.showsDefaults(row.section) { return nil }
            return row.count > 0 ? .verbatim(String(row.count)) : nil
        }
    }

     
     
    static func drawsRow(_ row: ConfigurationOutlineRow) -> Bool {
        row.section != .unknown || row.count > 0
    }

     
     
    @MainActor static func snifferEnabled(in session: ConfigurationEditorSession) -> Bool? {
        switch session.settingsValue(at: ["sniffer", "enable"]) {
        case .scalar(let token)?: return token == "true" ? true : token == "false" ? false : nil
        case .string(let text)?: return text == "true" ? true : text == "false" ? false : nil
        default: return nil
        }
    }

    @MainActor static func mitmEnabled(in session: ConfigurationEditorSession) -> Bool? {
        switch session.settingsValue(at: ["mitm", "enable"]) {
        case .scalar(let token)?: return token == "true" ? true : token == "false" ? false : nil
        case .string(let text)?: return text == "true" ? true : text == "false" ? false : nil
        default: return nil
        }
    }

     
    static func summary(of value: OrderedJSON) -> String {
        switch value {
        case .string(let text): return text
        case .scalar(let token): return token
        case .array(let items): return String(items.count)
        case .object(let items): return String(items.count)
        }
    }

     
     
    static func entryTitle(_ value: OrderedJSON, index: Int) -> String {
        if case .string(let text) = value { return text }
        if case .object(let items) = value, let name = items.first(where: { $0.key == "name" })?.value,
           case .string(let text) = name { return text }
        return "#\(index + 1)"
    }

     
    static func place(of item: ConfigurationCompileAnswer.Problem) -> String? {
        var parts: [String] = []
        if let section = item.section { parts.append(item.index.map { "\(section)[\($0)]" } ?? section) }
        if let line = item.line { parts.append("line \(line)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

#endif
