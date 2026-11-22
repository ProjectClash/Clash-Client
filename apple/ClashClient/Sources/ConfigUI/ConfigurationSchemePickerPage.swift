import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
struct ConfigurationSchemePickerSnapshot: Equatable {
    struct Row: Equatable, Identifiable {
         
        let id: String
         
         
         
        let detailID: String
        let name: String
         
        let detail: String
         
        let isCurrent: Bool
    }

     
     
    struct OriginalRow: Equatable {
        let isAvailable: Bool
        let isCurrent: Bool
        let reason: String?
    }

    let builtin: [Row]
    let mine: [Row]
    let linked: [Row]
    let files: [Row]
     
     
    let original: OriginalRow?

     
     
    var current: ConfigurationSchemeChooser.Choice? {
        if original?.isCurrent == true { return .original }
        return (builtin + mine + linked + files).first(where: \.isCurrent).map { .scheme($0.id) }
    }

     
    static let builtinHeader = "Built-in Rule Schemes"
    static let mineHeader = "My Rule Schemes"
    static let linkedHeader = "From Profile URLs"
    static let filesHeader = "From Files"
     
     
     
    static let originalTitle = "Original Configuration (Rule Scheme)"
     
    static let originalDetail = "Runs the imported file as it is"
     
    static let originalRefusal = "“%@” has %d node sources; this only works with one."
     
    static let changedFrom = "Changed from “%@”"
    static let linksOwnRules = "The link’s own rules"

    static func make(library: ConfigurationLibrarySnapshot, profileID: String, configurationName: String,
                     locale: Locale) -> Self {
        let recipe = library.recipes.first { $0.id == profileID }
         
         
        let running = recipe.flatMap { recipe -> ConfigurationRuleScheme? in
            guard recipe.preservesOriginal != true else { return nil }
            return library.rules.first { $0.id == recipe.ruleSchemeID }
                ?? ConfigurationBuiltins.schemes.first { $0.id == recipe.ruleSchemeID }
        }
        let choices = ProfilesViewModel.menuChoices(ProfilesViewModel.schemeChoices(library, for: recipe), running: running)
        var groups: [ClashConfigurationRuleLibrarySection: [Row]] = [:]
         
         
         
        for scheme in choices {
            guard let group = ClashConfigurationRuleLibrarySection.allCases.first(where: { $0.contains(scheme, library: library) })
            else { continue }
            groups[group, default: []].append(Row(id: scheme.id, detailID: scheme.ownViewBaseID ?? scheme.id,
                                                  name: scheme.displayLabel,
                                                  detail: detail(of: scheme, in: group, library: library, locale: locale),
                                                  isCurrent: scheme.id == running?.id))
        }
        return Self(builtin: groups[.builtin] ?? [], mine: groups[.custom] ?? [], linked: groups[.subscription] ?? [],
                    files: groups[.file] ?? [],
                    original: original(of: recipe, profileID: profileID, configurationName: configurationName, locale: locale))
    }

     
     
     
     
     
    static func added(before: ConfigurationLibrarySnapshot, after: ConfigurationLibrarySnapshot,
                      input: ProfileQuickAddInput, profileID: String) -> String? {
         
        let known = Set(before.rules.map(\.id) + ConfigurationBuiltins.schemes.map(\.id))
        let page = make(library: after, profileID: profileID, configurationName: "", locale: Locale(identifier: "en"))
        if let new = (page.builtin + page.mine + page.linked + page.files).first(where: { !known.contains($0.id) }) {
            return new.id
        }
         
         
         
         
        guard case .link(let typed, _) = input else { return nil }
        let link = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let addresses: Set<String> = [link, ConfigurationTowerRuleReader.normalizedURL(link)]
        let written = Set(after.sources.filter { source in
            guard case .subscription(let address) = source.origin else { return false }
            return addresses.contains(address)
        }.map(\.id))
        guard !written.isEmpty else { return nil }
         
         
         
         
        return (page.linked + page.files).first { row in
            guard let scheme = after.rules.first(where: { $0.id == row.id }) else { return false }
            let base = scheme.baseSchemeID.flatMap { id in after.rules.first { $0.id == id } }
            return written.contains(scheme.sourceID) || base.map { written.contains($0.sourceID) } == true
        }?.id
    }

     
     
     
    static func detail(of scheme: ConfigurationRuleScheme, in group: ClashConfigurationRuleLibrarySection,
                       library: ConfigurationLibrarySnapshot, locale: Locale) -> String {
        let counted = {
            ClashCopy.string(for: ClashConfigurationSourceCopy.ruleSummary(ConfigurationSchemeDetailSnapshot.record(of: scheme, in: library),
                                                                           locale: locale), locale: locale)
        }
        switch group {
        case .builtin:
             
             
            return ConfigurationSchemeDetailSnapshot.builtinNotes[scheme.plainViewBaseID ?? scheme.id]
                .map { ClashCopy.string($0, locale: locale) } ?? counted()
        case .custom:
            guard let builtin = builtinChangedFrom(scheme, in: library) else { return counted() }
            return ClashCopy.format(changedFrom, locale: locale, ClashTowerRulesLibraryView.displayLabel(builtin, locale: locale))
        case .subscription:
            return runsALinksOwnRules(scheme, in: library) ? ClashCopy.string(linksOwnRules, locale: locale) : counted()
        case .file:
            return counted()
        }
    }

     
     
     
     
    static func builtinChangedFrom(_ scheme: ConfigurationRuleScheme, in library: ConfigurationLibrarySnapshot) -> ConfigurationRuleScheme? {
        let builtin = { (id: String) in ConfigurationBuiltins.schemes.first { $0.id == id } }
        if let base = scheme.baseSchemeID { return builtin(base) }
        guard let base = scheme.ownViewBaseID else { return nil }
         
        if ConfigurationBuiltins.isNative(base) { return scheme.plainViewBaseID == nil ? builtin(base) : nil }
        return library.rules.first { $0.id == base && $0.ownViewBaseID == nil }?.baseSchemeID.flatMap(builtin)
    }

     
     
     
     
    static func runsALinksOwnRules(_ scheme: ConfigurationRuleScheme, in library: ConfigurationLibrarySnapshot) -> Bool {
        let rules = scheme.plainViewBaseID.flatMap { id in library.rules.first { $0.id == id } } ?? scheme
        return rules.baseSchemeID == nil && rules.ownViewBaseID == nil && (rules.kind == .supplied || rules.kind == .imported)
    }

     
     
     
     
     
    static func original(of recipe: ConfigurationRecipe?, profileID: String, configurationName: String,
                         locale: Locale) -> OriginalRow? {
        guard let recipe else {
            return profileID == LocalDefaultProfileProvisioner.profileID ? nil
                : OriginalRow(isAvailable: true, isCurrent: true, reason: nil)
        }
        let sources = recipe.sources.count
        return OriginalRow(isAvailable: sources == 1, isCurrent: recipe.preservesOriginal == true,
                           reason: sources == 1 ? nil : ClashCopy.format(originalRefusal, locale: locale, configurationName, sources))
    }
}

 
#if os(iOS)

 
 
 
 
 
 
 
 
 
struct ConfigurationSchemePickerPage: View {
    typealias Choice = ConfigurationSchemeChooser.Choice

    @ObservedObject var state: ConfigurationPageState
    @ObservedObject var session: ConfigurationEditorSession
     
     
    let setUsesOriginal: ((Bool) async throws -> Void)?
     
    var libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?
    @Environment(\.locale) private var locale
    @State private var library: ConfigurationLibrarySnapshot?
    @State private var loadFailure: String?
     
    @State private var picking: Choice?
    @State private var creating = false
     
    @State private var detail: String?
    @State private var showsDetail = false
    @StateObject private var quickAdd: ProfileQuickAddController

     
    static let title = "Rule Schemes of “%@”"
     
    static let changeNote = "Takes effect at once; custom rules and the override script are kept."
     
    static let addNote = "Added schemes are used for “%@” right away."

    init(state: ConfigurationPageState, session: ConfigurationEditorSession,
         setUsesOriginal: ((Bool) async throws -> Void)?,
         libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)? = nil) {
        _state = ObservedObject(wrappedValue: state)
        _session = ObservedObject(wrappedValue: session)
        self.setUsesOriginal = setUsesOriginal
        self.libraryChanged = libraryChanged
        _quickAdd = StateObject(wrappedValue: ProfileQuickAddController(model: state.model, target: .rules))
    }

     
    static func pick(_ choice: Choice, current: Choice?, choose: (Choice) -> Void) {
        guard choice != current else { return }
        choose(choice)
    }

     
     
     
     
    static func use(_ schemeID: String, current: Choice?, state: ConfigurationPageState,
                    setUsesOriginal: ((Bool) async throws -> Void)?,
                    libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?,
                    picking: (Choice) -> Void = { _ in }) {
        pick(.scheme(schemeID), current: current) { choice in
            picking(choice)
            state.choose(choice, setUsesOriginal: setUsesOriginal, libraryChanged: libraryChanged)
        }
    }

     
     
     
    static func newSchemeForm(state: ConfigurationPageState, library: ConfigurationLibrarySnapshot,
                              setUsesOriginal: ((Bool) async throws -> Void)?,
                              libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?,
                              changed: @escaping (ConfigurationLibrarySnapshot) -> Void,
                              picking: @escaping (Choice) -> Void,
                              close: @escaping () -> Void) -> ConfigurationNewRuleAdapter {
        ConfigurationNewRuleAdapter(model: state.model, library: library, title: "New Rule Scheme", changed: changed,
                                    made: { id in
                                        Self.use(id, current: nil, state: state, setUsesOriginal: setUsesOriginal,
                                                 libraryChanged: libraryChanged, picking: picking)
                                    }, close: close)
    }

     
     
     
    static func useAdded(before: ConfigurationLibrarySnapshot, after: ConfigurationLibrarySnapshot,
                         input: ProfileQuickAddInput, state: ConfigurationPageState,
                         setUsesOriginal: ((Bool) async throws -> Void)?,
                         libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?,
                         picking: (Choice) -> Void = { _ in }) {
        guard let id = ConfigurationSchemePickerSnapshot.added(before: before, after: after, input: input,
                                                               profileID: state.profileID)
        else { return }
        let current = ConfigurationSchemePickerSnapshot.make(library: after, profileID: state.profileID,
                                                             configurationName: "", locale: Locale(identifier: "en")).current
        Self.use(id, current: current, state: state, setUsesOriginal: setUsesOriginal, libraryChanged: libraryChanged,
                 picking: picking)
    }

     
    private var name: String {
        session.page?.label ?? state.model.profiles.first { $0.id == state.profileID }?.label ?? ""
    }

    private var isBusy: Bool { state.choosing || session.isSaving }

    var body: some View {
        Form {
            if let library {
                sections(ConfigurationSchemePickerSnapshot.make(library: library, profileID: state.profileID,
                                                                configurationName: name, locale: locale), library: library)
            } else if let loadFailure {
                Section { ClashStatusMessage(text: .verbatim(loadFailure), kind: .error) }
            } else {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .clashPageTitle(.format(Self.title, [name]), watchAs: "configuration.scheme-picker")
         
         
         
         
        .background(ClashRoutedViewDestination(isPresented: $showsDetail) { [detail, library] in
            if let detail, let library { detailPage(detail, library: library) }
        })
         
         
        .task(id: state.libraryRevision) { await read() }
        .onAppear { quickAdd.onRulesAdded = { added($0, input: $1) } }
        .profileQuickAddPresenters(quickAdd)
        .clashProductModal(isPresented: $creating, role: .form) { [library] in
            Self.newSchemeForm(state: state, library: library ?? ConfigurationLibrarySnapshot(),
                               setUsesOriginal: setUsesOriginal, libraryChanged: libraryChanged, changed: apply,
                               picking: { picking = $0 }, close: { creating = false })
        }
         
        .configurationPushedAlertHost(session)
    }

    @ViewBuilder
    private func sections(_ page: ConfigurationSchemePickerSnapshot, library: ConfigurationLibrarySnapshot) -> some View {
        let groups = [(ConfigurationSchemePickerSnapshot.builtinHeader, page.builtin),
                      (ConfigurationSchemePickerSnapshot.mineHeader, page.mine),
                      (ConfigurationSchemePickerSnapshot.linkedHeader, page.linked),
                      (ConfigurationSchemePickerSnapshot.filesHeader, page.files)].filter { !$0.1.isEmpty }
        let current = page.current
        ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
            Section {
                ForEach(group.1) { row in schemeRow(row, current: current) }
            } header: {
                Text(clash: .copy(group.0))
            } footer: {
                 
                if page.original == nil, index == groups.count - 1 { changeNote }
            }
        }
         
        if let original = page.original {
            Section {
                originalRow(original, current: current)
            } footer: {
                changeNote
            }
        }
        ProfileQuickAddCard(controller: quickAdd,
                            identifiers: .init(linkIdentifier: "configuration.scheme-picker.add.link",
                                               scanIdentifier: "configuration.scheme-picker.add.scan",
                                               fileIdentifier: "configuration.scheme-picker.add.file",
                                               manualIdentifier: "configuration.scheme-picker.add.new",
                                               statusIdentifier: "configuration.scheme-picker.add.status"),
                            manual: { creating = true },
                            header: "Add Rule Scheme", manualKey: "New Rule Scheme",
                            footerView: AnyView(Text(clash: .format(Self.addNote, [name]))
                                .accessibilityIdentifier("configuration.scheme-picker.add-note")))
             
            .disabled(isBusy || state.model.isNodeLibraryHeld)
        Section {
            ClashNativeNavigationLink {
                ConfigurationRuleLibraryAdapter(model: state.model, library: library, changed: apply, close: {},
                                                embedded: true, showsClose: false)
                     
                    .clashPageTitle(.copy("Rule Library"))
                    .environment(\.clashProductModalDismiss, nil)
            } label: {
                Text(clash: .copy("Manage Rule Schemes"))
            }
            .accessibilityIdentifier("configuration.scheme-picker.manage")
        }
    }

    private var changeNote: some View {
        Text(clash: .copy(Self.changeNote)).accessibilityIdentifier("configuration.scheme-picker.change-note")
    }

     
     
    private func schemeRow(_ row: ConfigurationSchemePickerSnapshot.Row, current: Choice?) -> some View {
        HStack(spacing: ClashTheme.Spacing.row) {
            Button { pick(.scheme(row.id), current: current) } label: {
                choiceLabel(isCurrent: row.isCurrent, choice: .scheme(row.id), title: .verbatim(row.name), detail: row.detail)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityAddTraits(row.isCurrent ? .isSelected : [])
            .accessibilityIdentifier("configuration.scheme-picker.row.\(row.id)")
            Button { detail = row.detailID; showsDetail = true } label: {
                Image(systemName: ClashSymbol.infoCircle.name)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: ClashClientUI.ClashTheme.Control.minimumHitTarget,
                           height: ClashClientUI.ClashTheme.Control.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(clash: .copy("Details")))
            .accessibilityIdentifier("configuration.scheme-picker.info.\(row.id)")
        }
         
         
        .accessibilityElement(children: .contain)
    }

     
     
    private func originalRow(_ original: ConfigurationSchemePickerSnapshot.OriginalRow, current: Choice?) -> some View {
        Button { pick(.original, current: current) } label: {
            choiceLabel(isCurrent: original.isCurrent, choice: .original,
                        title: .copy(ConfigurationSchemePickerSnapshot.originalTitle),
                        detail: original.reason ?? ClashCopy.string(ConfigurationSchemePickerSnapshot.originalDetail, locale: locale),
                        greyed: !original.isAvailable)
        }
        .buttonStyle(.plain)
        .disabled(!original.isAvailable || setUsesOriginal == nil || isBusy)
        .accessibilityAddTraits(original.isCurrent ? .isSelected : [])
        .accessibilityIdentifier("configuration.scheme-picker.original")
    }

    private func choiceLabel(isCurrent: Bool, choice: Choice, title: ClashDisplayText, detail: String,
                             greyed: Bool = false) -> some View {
        HStack(spacing: ClashTheme.Spacing.row) {
            Group {
                if state.choosing, picking == choice {
                    ProgressView().controlSize(.small)
                } else {
                    ClashSelectionMark(isSelected: isCurrent)
                }
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                Text(clash: title).foregroundStyle(greyed ? .secondary : .primary)
                Text(verbatim: detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

     
     
     
    private func detailPage(_ schemeID: String, library: ConfigurationLibrarySnapshot) -> some View {
        ConfigurationSchemeDetailPage(model: state.model, schemeID: schemeID, library: library, changed: apply, profileID: nil)
            .environment(\.clashProductModalDismiss, nil)
    }

    private func pick(_ choice: Choice, current: Choice?) {
        Self.pick(choice, current: current) { choice in
            picking = choice
            state.choose(choice, setUsesOriginal: setUsesOriginal, libraryChanged: libraryChanged)
        }
    }

     
    private func read() async {
        do {
            guard let store = state.model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let fresh = try await Task.detached(priority: .userInitiated) { try store.snapshot() }.value
            if library.map({ fresh.generation >= $0.generation }) ?? true { library = fresh }
            loadFailure = nil
        } catch {
            loadFailure = ClashErrorCopy.message(error, locale: locale)
        }
    }

     
     
    private func apply(_ snapshot: ConfigurationLibrarySnapshot) {
        if library.map({ snapshot.generation >= $0.generation }) ?? true { library = snapshot }
        state.noting(libraryChanged)(snapshot)
    }

     
     
    private func added(_ snapshot: ConfigurationLibrarySnapshot, input: ProfileQuickAddInput) {
        let before = library
        apply(snapshot)
        guard let before else { return }
        Self.useAdded(before: before, after: snapshot, input: input, state: state, setUsesOriginal: setUsesOriginal,
                      libraryChanged: libraryChanged, picking: { picking = $0 })
    }
}
#endif
