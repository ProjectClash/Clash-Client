#if os(iOS)
import ClashClientKit
import Combine
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 

 
 
struct ConfigurationRulesPageSnapshot: Equatable {
     
    let title: ClashDisplayText
     
     
    let scheme: ClashDisplayText?
     
     
     
     
    let rulesGroupTitle: ClashDisplayText?
     
    let customRules: [CustomRule]
    let prependsCustomRules: Bool
     
    let customRulesNote: ClashDisplayText
     
     
     
    let chapters: [Chapter]

    struct CustomRule: Equatable, Identifiable {
        let index: Int
        let raw: String
         
        let isEnabled: Bool
        var id: Int { index }
    }

     
     
     
     
    enum Running: Equatable {
        case scheme(ConfigurationRuleScheme)
        case original

        static func of(_ profileID: String, in library: ConfigurationLibrarySnapshot) -> Running {
            guard let recipe = library.recipes.first(where: { $0.id == profileID }), recipe.preservesOriginal != true,
                  let scheme = library.rules.first(where: { $0.id == recipe.ruleSchemeID })
                    ?? ConfigurationBuiltins.schemes.first(where: { $0.id == recipe.ruleSchemeID })
            else { return .original }
            return .scheme(scheme)
        }

         
         
        static func form(_ running: Running, profileID: String,
                         in library: ConfigurationLibrarySnapshot) -> ProfilesViewModel.ConfigurationEditorPage.Form {
            switch running {
            case .scheme(let scheme): .composed(scheme: scheme, ownership: library.schemePageOwnership(profileID: profileID))
            case .original: .original
            }
        }
    }

    struct Chapter: Equatable, Identifiable {
        let section: ConfigurationOutlineSection
        let value: ClashDisplayText?
        var id: String { section.rawValue }
    }

     
     
     
    static func addToRulesTitle(running: Running?) -> String? {
        switch running {
        case .scheme?: return "Add to Rule Scheme"
        case .original?: return "Add to the File’s Rules"
        case nil: return nil
        }
    }

     
    static let titleKey = "Rules of “%@”"
    static let customRulesNoteKey = "Only for “%@”; kept when you change the rule scheme."
    static let originalRulesTitle = "Rules in the Configuration File"
     
     
    static let chapterSections: [ConfigurationOutlineSection] = [.ruleProviders, .subRules]

     
     
     
    static let keptRulesTitle = ConfigurationEditorCopy.title(of: .rules)

     
     
     
    static func chapterTitle(_ section: ConfigurationOutlineSection) -> ClashDisplayText {
        switch section {
        case .ruleProviders: .copy("Rule Sets")
        default: .copy(ConfigurationEditorCopy.title(of: section))
        }
    }

     
     
    static func chapterValues(of page: ProfilesViewModel.ConfigurationEditorPage?)
        -> [ConfigurationOutlineSection: ClashDisplayText] {
        var values: [ConfigurationOutlineSection: ClashDisplayText] = [:]
        for section in chapterSections {
            values[section] = page?.rows.first { $0.section == section }.flatMap { ConfigurationEditorCopy.value(of: $0) }
        }
        return values
    }

     
     
    static func chapters(running: Running?, values: [ConfigurationOutlineSection: ClashDisplayText]) -> [Chapter] {
        running == nil ? [] : chapterSections.map { Chapter(section: $0, value: values[$0]) }
    }

    static func make(profile: Profile, running: Running?, page: ProfilesViewModel.ConfigurationEditorPage?) -> Self {
        var scheme: ClashDisplayText?
        var rulesGroupTitle: ClashDisplayText?
        switch running {
        case .scheme(let running)?:
             
            scheme = .verbatim(running.displayLabel)
            rulesGroupTitle = .verbatim(running.displayLabel)
        case .original?:
            scheme = .copy(ConfigurationSchemePickerSnapshot.originalTitle)
            rulesGroupTitle = .copy(originalRulesTitle)
        case nil:
            break
        }
        let disabled = Set(profile.override.disabledAppendRules ?? [])
        let rules = profile.override.appendRules.enumerated().map { index, raw in
            CustomRule(index: index, raw: raw, isEnabled: !disabled.contains(raw))
        }
        let chapters = chapters(running: running, values: chapterValues(of: page))
        return Self(title: .format(titleKey, [profile.label]), scheme: scheme, rulesGroupTitle: rulesGroupTitle,
                    customRules: rules, prependsCustomRules: profile.override.prependRules,
                    customRulesNote: .format(customRulesNoteKey, [profile.label]), chapters: chapters)
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class ConfigurationRulesPageContext: ObservableObject {
    let model: ProfilesViewModel
    let profileID: String
     
    let state: ConfigurationPageState
    var session: ConfigurationEditorSession { state.session }
     
    @Published private(set) var running: ConfigurationRulesPageSnapshot.Running?
     
     
     
    @Published private(set) var form: ProfilesViewModel.ConfigurationEditorPage.Form?
     
    @Published private(set) var preparedRules: ConfigurationSchemeRulesPushed.Prepared?
     
    private var preparedAt: Int?

     
     
     
     
     
    var freshPreparedRules: ConfigurationSchemeRulesPushed.Prepared? {
        guard let preparedRules, preparedAt == revision, case .scheme(let scheme)? = running,
              scheme.id == preparedRules.scheme.id else { return nil }
        return preparedRules
    }
     
     
    @Published private(set) var editReady = false
     
     
    @Published private(set) var revision = 0
     
     
    @Published var addingRule = false
     
     
    @Published var addingToRules = false
     
     
     
    @Published private(set) var keepsRulesInFile = false
     
     
     
    @Published private(set) var chapterValues: [ConfigurationOutlineSection: ClashDisplayText] = [:]
     
     
    @Published private(set) var busy = false
     
     
    private var lastRead: String?
    private var watchingBusy: AnyCancellable?

    init(model: ProfilesViewModel, profileID: String, session: ConfigurationEditorSession?,
         selections: GroupSelectionCarrying?) {
        self.model = model
        self.profileID = profileID
        state = session.map { ConfigurationPageState(model: model, session: $0) }
            ?? ConfigurationPageState(model: model, profileID: profileID, selections: selections)
        chapterValues = ConfigurationRulesPageSnapshot.chapterValues(of: state.session.page)
        busy = state.session.isSaving || state.choosing
         
        watchingBusy = state.session.objectWillChange.merge(with: state.objectWillChange)
            .sink { [weak self] _ in Task { @MainActor in self?.noteBusy() } }
    }

    private func noteBusy() {
        let now = session.isSaving || state.choosing
        if busy != now { busy = now }
    }

     
    private func takeChapterValues() {
        let now = ConfigurationRulesPageSnapshot.chapterValues(of: session.page)
        if chapterValues != now { chapterValues = now }
    }

     
    func noting(_ forward: ((ConfigurationLibrarySnapshot) -> Void)?) -> (ConfigurationLibrarySnapshot) -> Void {
        state.noting { [weak self] snapshot in
            Task { @MainActor in self?.revision &+= 1 }
            forward?(snapshot)
        }
    }

     
     
    private func readKey(editsRules: Bool, largeSource: Bool) -> String {
        let revisionOfProfile = model.profiles.first { $0.id == profileID }?.activeRevision ?? ""
        return "\(revisionOfProfile)#\(model.publishedGeneration(of: profileID))#\(revision)#\(editsRules)#\(largeSource)"
    }

     
     
     
     
     
    func read(editsRules: Bool, largeSource: Bool) async {
        takeChapterValues()
        let key = readKey(editsRules: editsRules, largeSource: largeSource)
        guard key != lastRead else { return }
        let revisionAtRead = revision
        if let store = model.configurationLibraryStore {
            let profileID = profileID
            do {
                let library = try await Task.detached(priority: .userInitiated) { try store.snapshot() }.value
                guard !Task.isCancelled else { return }
                let now = ConfigurationRulesPageSnapshot.Running.of(profileID, in: library)
                if running != now { running = now }
                let keeps = RulesOverviewHost.keepsRulesInFile(of: profileID, in: library)
                if keepsRulesInFile != keeps { keepsRulesInFile = keeps }
                let page = ConfigurationRulesPageSnapshot.Running.form(now, profileID: profileID, in: library)
                if form != page { form = page }
            } catch {
                 
            }
        }
        guard !Task.isCancelled else { return }
        var prepared: ConfigurationSchemeRulesPushed.Prepared?
        if editsRules {
            switch form {
            case .composed(let scheme, _)?:
                 
                 
                do {
                    prepared = try await ConfigurationSchemeRulesPushed.prepare(model: model, schemeID: scheme.id,
                                                                                catalog: session.catalog)
                } catch {
                     
                     
                    prepared = nil
                }
            case .original?:
                 
                 
                 
                 
                if !largeSource, session.page == nil || lastRead != nil { _ = await session.reload() }
            case nil:
                break
            }
        }
        guard !Task.isCancelled else { return }
        preparedRules = prepared
        preparedAt = revisionAtRead
        editReady = editsRules
        lastRead = key
        takeChapterValues()
    }
}

 
 
 
 
 
 
struct ConfigurationRulesPageRead<Content: View>: View {
    @ObservedObject var session: ConfigurationEditorSession
     
    let form: ProfilesViewModel.ConfigurationEditorPage.Form?
    @ViewBuilder let content: (ProfilesViewModel.ConfigurationEditorPage.Form) -> Content

     
    private var composed: ProfilesViewModel.ConfigurationEditorPage.Form? {
        if case .composed? = form { return form }
        return nil
    }

    var body: some View {
        if let composed {
            content(composed)
        } else if let page = session.page {
            content(page.form)
        } else if let reason = session.loadFailure {
             
             
            List { Section { ConfigurationPageLoadFailure(session: session, reason: reason) } }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { _ = await session.reload() }
        }
    }
}

 
 
 
struct ConfigurationRulesPageContextHost<Content: View>: View {
     
    let model: ProfilesViewModel
    let profile: Profile
     
     
    let editsRules: Bool?
    let drawsSections: Bool
    let libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?
     
     
     
     
    let editingInPlace: Binding<Bool>
    let content: (RulesOverviewPageParts) -> Content
    @StateObject private var context: ConfigurationRulesPageContext

    init(model: ProfilesViewModel, profile: Profile, session: ConfigurationEditorSession?,
         selections: GroupSelectionCarrying?, editsRules: Bool?, drawsSections: Bool,
         libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?,
         editingInPlace: Binding<Bool> = .constant(false),
         @ViewBuilder content: @escaping (RulesOverviewPageParts) -> Content) {
        self.model = model
        self.profile = profile
        self.editsRules = editsRules
        self.drawsSections = drawsSections
        self.libraryChanged = libraryChanged
        self.editingInPlace = editingInPlace
        self.content = content
        _context = StateObject(wrappedValue: ConfigurationRulesPageContext(model: model, profileID: profile.id,
                                                                           session: session, selections: selections))
    }

    var body: some View {
         
         
        content(parts)
             
             
             
             
            .task(id: "\(profile.id)#\(profile.activeRevision ?? "")#\(model.publishedGeneration(of: profile.id))#\(String(describing: editsRules))#\(context.revision)#\(editingInPlace.wrappedValue)") {
                 
                 
                 
                 
                guard let editsRules, !editingInPlace.wrappedValue else { return }
                await context.read(editsRules: editsRules, largeSource: model.hasLargeSource(profile))
            }
             
             
            .configurationPushedAlertHost(context.session)
             
             
            .clashProductModal(isPresented: $context.addingRule, role: .form) {
                ConfigurationCustomRuleAddForm(model: model, profileID: profile.id,
                                               failed: { [session = context.session] in session.failure = $0 })
            }
             
             
            .clashProductModal(isPresented: $context.addingToRules, role: .form) {
                ConfigurationRulesAddToRulesForm(model: model, profileID: profile.id, session: context.session,
                                                 running: context.running, prepared: context.freshPreparedRules,
                                                 libraryChanged: context.noting(libraryChanged))
            }
    }

    private var parts: RulesOverviewPageParts {
         
        guard drawsSections else { return RulesOverviewPageParts(inPlaceEditing: inPlaceEditing) }
        let snapshot = ConfigurationRulesPageSnapshot.make(profile: profile, running: context.running, page: nil)
        let context = context, model = model, libraryChanged = libraryChanged
         
         
        return RulesOverviewPageParts(
            title: snapshot.title,
            leadingSections: {
                AnyView(ConfigurationRulesPageSections(context: context, session: context.session, model: model,
                                                       libraryChanged: libraryChanged))
            },
            rowsBeforeActiveRules: {
                AnyView(ConfigurationRulesPageChapterRows(context: context, session: context.session,
                                                          libraryChanged: libraryChanged))
            },
            inPlaceEditing: inPlaceEditing,
             
             
            addRule: { context.addingRule = true },
            addToRules: addToRules,
             
             
            pushesWithPageLinks: true,
             
             
            editRulesDisabled: editsRules != true || !context.editReady,
             
            showsActiveRules: model.activeProfileID == profile.id)
    }

     
     
     
     
    private var addToRules: RulesOverviewPageParts.Addition? {
        guard editsRules == true, let title = ConfigurationRulesPageSnapshot.addToRulesTitle(running: context.running)
        else { return nil }
        let context = context
        return .init(title: .copy(title)) { context.addingToRules = true }
    }

     
     
     
     
     
     
     
     
    private var inPlaceEditing: (() -> AnyView)? {
        if drawsSections {
            guard editsRules != false else { return nil }
        } else {
            guard editsRules == true, context.editReady else { return nil }
        }
        let context = context, model = model, libraryChanged = libraryChanged, editing = editingInPlace
        return {
            AnyView(
                ConfigurationRulesEditList(model: model, profileID: context.profileID, session: context.session,
                                           running: context.running, prepared: context.freshPreparedRules,
                                           libraryChanged: context.noting(libraryChanged))
                    .environmentObject(context.state)
                    .environmentObject(context.session)
                     
                    .clashOnScreen { onScreen in editing.wrappedValue = onScreen }
                     
                     
                    .environment(\.clashProductModalDismiss, nil)
            )
        }
    }
}

 
 
 
 
 
struct ConfigurationRulesPageSections: View {
    @Environment(\.locale) private var locale
    @ObservedObject var context: ConfigurationRulesPageContext
     
     
     
    let session: ConfigurationEditorSession
     
    @ObservedObject var model: ProfilesViewModel
    let libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?
    @Environment(\.clashFeedback) private var feedback

    private var profile: Profile? { model.profiles.first { $0.id == context.profileID } }

    var body: some View {
        if let profile {
            let snapshot = ConfigurationRulesPageSnapshot.make(profile: profile, running: context.running, page: nil)
             
             
            Section {
                schemeRow(snapshot.scheme ?? .verbatim(""))
                    .disabled(snapshot.scheme == nil)
            }
            Section {
                if snapshot.customRules.isEmpty {
                     
                     
                    ClashNativeNavigationLink {
                        customRulesPage
                    } label: {
                        Text(clash: .copy("No Custom Rules")).foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("configuration.rules-page.custom-rules.empty")
                }
                ForEach(snapshot.customRules) { rule in
                    ClashNativeNavigationLink {
                        customRulesPage
                    } label: {
                        ConfigurationRuleRow(rule.raw, showsChevron: false)
                            .opacity(rule.isEnabled ? 1 : 0.5)
                    }
                    .accessibilityIdentifier("configuration.rules-page.custom-rule")
                }
                 
                 
                 
                Button { context.addingRule = true } label: {
                    Label { Text(clash: .copy("Add Rule")) } icon: { Image(systemName: ClashSymbol.plus.rawValue) }
                }
                .accessibilityIdentifier("configuration.rules-page.custom-rules.add")
                Toggle(isOn: Binding(get: { snapshot.prependsCustomRules }, set: { setPrepends($0) })) {
                    Text(clash: .copy("Apply before profile rules"))
                }
                .accessibilityIdentifier("configuration.rules-page.custom-rules.prepend")
            } header: {
                Text(clash: .copy(ConfigurationEditorCopy.title(of: .customRules)))
            } footer: {
                Text(clash: snapshot.customRulesNote)
            }
             
             
             
            if let notice = refusalNotice {
                Section {
                    VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                        ClashStatusMessage(text: notice[0], kind: .error)
                        ForEach(Array(notice.dropFirst().enumerated()), id: \.offset) { _, line in
                            Text(clash: line).foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("configuration.rules-page.refused")
            }
        }
    }

    private var refusalNotice: [ClashDisplayText]? {
         
         
        guard let refused = model.refusedActivation, refused.profileID == context.profileID,
              refused.profileID == model.activeProfileID, model.failureCameFromASourceRefresh,
              case .scheme(let scheme)? = context.running else { return nil }
        return RuleSchemeRefusalNotice.lines(for: refused.failure,
                                             schemeName: ClashTowerRulesLibraryView.displayLabel(scheme, locale: locale),
                                             fromLink: scheme.kind == .imported)
    }

     
     
    private func schemeRow(_ scheme: ClashDisplayText) -> some View {
        let model = model, profileID = context.profileID
        let context = context, session = session, libraryChanged = libraryChanged
        return ClashNativeNavigationLink {
             
            ConfigurationSchemePickerPage(state: context.state, session: session,
                                          setUsesOriginal: { enabled in
                                              try await model.setUsesOriginalConfiguration(profileID, enabled: enabled)
                                          },
                                          libraryChanged: context.noting(libraryChanged))
                 
                .environment(\.clashProductModalDismiss, nil)
                 
                .configurationPushedAlertHost(session)
        } label: {
            ConfigurationRowLabel(title: .copy("Rule Scheme"), value: scheme)
        }
        .disabled(context.busy)
        .accessibilityIdentifier("configuration.rules-page.scheme")
    }

     
     
     
    private var customRulesPage: some View {
        ConfigurationCustomRulesPage(model: model, profileID: context.profileID)
            .environment(\.clashProductModalDismiss, nil)
    }

     
     
    private func setPrepends(_ prepends: Bool) {
        guard let latest = model.profiles.first(where: { $0.id == context.profileID }) else { return }
        var draft = ProfileRulesDraft(profile: latest)
        guard draft.prependRules != prepends else { return }
        draft.prependRules = prepends
        do {
            try model.updateRules(draft)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if let feedback {
                feedback.show(.error(title: ClashFeedbackCopy.couldNotSave, message: .copy(message),
                                     accessibilityIdentifier: "feedback.rules.custom.prepend"),
                              operation: "rules.custom.prepend")
            } else {
                session.failure = message
            }
        }
    }
}

 
 
 
struct ConfigurationRulesPageChapterRows: View {
    @ObservedObject var context: ConfigurationRulesPageContext
     
     
    let session: ConfigurationEditorSession
    let libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?

    var body: some View {
        if context.model.profiles.contains(where: { $0.id == context.profileID }) {
             
             
             
             
            if context.keepsRulesInFile {
                ClashNativeNavigationLink {
                    ConfigurationRulesPageRead(session: session, form: context.form) { _ in
                        if let kept = session.page?.keptRules {
                            ConfigurationKeptRulesView(kept: kept, title: .copy(ConfigurationRulesPageSnapshot.keptRulesTitle))
                        }
                    }
                    .environmentObject(context.state)
                    .environmentObject(session)
                     
                    .environment(\.clashProductModalDismiss, nil)
                    .configurationPushedAlertHost(session)
                } label: {
                    Text(clash: .copy(ConfigurationRulesPageSnapshot.keptRulesTitle))
                }
                .accessibilityIdentifier("configuration.rules-page.kept-rules")
            }
            ForEach(ConfigurationRulesPageSnapshot.chapters(running: context.running, values: context.chapterValues)) { chapter in
                ClashNativeNavigationLink {
                    ConfigurationRulesPageRead(session: session, form: context.form) { form in
                        ConfigurationSectionDestination(model: context.model, profileID: context.profileID, session: session,
                                                        section: chapter.section, form: form, alertHosts: session.alertHosts,
                                                        libraryChanged: context.noting(libraryChanged))
                            .equatable()
                    }
                    .environmentObject(context.state)
                    .environmentObject(session)
                     
                    .environment(\.clashProductModalDismiss, nil)
                } label: {
                    if let value = chapter.value {
                        ConfigurationRowLabel(title: ConfigurationRulesPageSnapshot.chapterTitle(chapter.section), value: value)
                    } else {
                        Text(clash: ConfigurationRulesPageSnapshot.chapterTitle(chapter.section))
                    }
                }
                .accessibilityIdentifier("configuration.rules-page.chapter.\(chapter.section.rawValue)")
            }
        }
    }
}

 
 
 
 
 
 
struct ConfigurationCustomRuleAddForm: View {
     
    let model: ProfilesViewModel
    let profileID: String
     
     
    let failed: (String) -> Void
    @State private var options: RulePolicyOptions?
    @Environment(\.clashFeedback) private var feedback

    var body: some View {
        Group {
            if let options {
                RuleBuilderAdapter(raw: "", options: options, pageTitle: "Add Rule",
                                   saveDetails: { raw, enabled, comment in add(raw, enabled: enabled, comment: comment) },
                                   save: { add($0, enabled: true, comment: "") })
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clashModalPresentation(.page)
        .task {
            guard options == nil, let profile = model.profiles.first(where: { $0.id == profileID }) else { return }
             
            let projected = await model.loadUIProjectedYAML(for: profile)
            let shared = await Task.detached(priority: .userInitiated) {
                ProfileRulesAdapter.buildPolicyOptions(sourceYAML: projected, profile: profile)
            }.value
            options = RulePolicyOptions(shared: shared)
        }
    }

    private func add(_ raw: String, enabled: Bool, comment: String) {
        let rule = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rule.isEmpty, let latest = model.profiles.first(where: { $0.id == profileID }) else { return }
        var draft = ProfileRulesDraft(profile: latest)
        draft.rules.append(rule)
        if !enabled { draft.disabledRules.insert(rule) }
        if !comment.isEmpty { draft.comments[rule] = comment }
        do {
            try model.updateRules(draft)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if let feedback {
                feedback.show(.error(title: ClashFeedbackCopy.couldNotSave, message: .copy(message),
                                     accessibilityIdentifier: "feedback.rules.custom.add"),
                              operation: "rules.custom.add")
            } else {
                failed(message)
            }
        }
    }
}

 
 
 
struct ConfigurationCustomRulesPage: View {
     
    @ObservedObject var model: ProfilesViewModel
    let profileID: String

    var body: some View {
        if let profile = model.profiles.first(where: { $0.id == profileID }) {
            ProfileProjectionLoader(profile: profile, model: model) { projected in
                ProfileRulesAdapter(profile: profile, sourceYAML: projected, ownsNavigationContainer: false) { draft in
                    try model.updateRules(draft)
                }
            }
        }
    }
}

 
 
 
struct ConfigurationRulesPage: View {
     
    let model: ProfilesViewModel
    let profileID: String
    let session: ConfigurationEditorSession
    var libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?
     
     
    @State private var connected: Bool?

    var body: some View {
        if let profile = model.profiles.first(where: { $0.id == profileID }) {
             
             
             
             
            let command = (session.selections as? ClashCommandClient) ?? AppGroupDirectFetch.session
            RulesOverviewHost(command: command,
                              canInspectActiveRules: connected ?? command?.isConnected == true,
                              profiles: model, profile: profile, openProxiesGroup: nil, ownsNavigationContainer: false,
                              profileID: profileID, pageSession: session, libraryChanged: libraryChanged)
                .onReceive(Self.connection(of: command)) { connected = $0 }
        }
    }

     
     
    static func connection(of command: ClashCommandClient?) -> AnyPublisher<Bool, Never> {
        command.map { $0.$isConnected.removeDuplicates().eraseToAnyPublisher() } ?? Empty().eraseToAnyPublisher()
    }
}
#endif
