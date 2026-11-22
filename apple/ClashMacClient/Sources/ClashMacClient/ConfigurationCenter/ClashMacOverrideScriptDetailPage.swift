import ClashClientKit
import ClashClientUI
import Combine
import SwiftUI

 
 
 
public struct ClashMacOverrideScriptDetail: Equatable, Sendable {
    public let id: String
     
    public let name: String
     
     
    public let link: String?
     
    public let usedBy: [LibraryUsage.Configuration]
     
     
    public let deletionNote: ClashDisplayText?

    public init(id: String, name: String, link: String?, usedBy: [LibraryUsage.Configuration], deletionNote: ClashDisplayText?) {
        self.id = id
        self.name = name
        self.link = link
        self.usedBy = usedBy
        self.deletionNote = deletionNote
    }

    public var isLinked: Bool { Self.isLinked(link) }

     
     
     
     
    public static func isLinked(_ link: String?) -> Bool {
        !(link ?? "").isEmpty
    }
}

 
 
 
enum ClashMacScriptNameCommit: Equatable {
    case nothing, restore, send(String)

     
     
     
    static func decide(typed: String, stored: String, lastSent: String?, refused: Bool, focused: Bool) -> Self {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != stored else { return .nothing }
         
         
         
        guard trimmed != lastSent else { return refused && !focused ? .restore : .nothing }
        return .send(trimmed)
    }
}

 
 
 
enum ClashMacOverrideScriptDeletion {
    static func note(_ consequence: ClashDisplayText?, locale: Locale) -> ClashDisplayText {
        guard let consequence else { return .copy("You can undo this.") }
         
        let between = ConfigurationFieldCopy.Language(locale: locale) == .en ? " " : ""
        return .verbatim(ClashCopy.string(for: consequence, locale: locale) + between
                         + ClashCopy.string(for: .copy("You can undo this."), locale: locale))
    }
}

 
 
struct ClashMacScriptTestRunAlert: ViewModifier {
    @Binding var result: ClashMacScriptTestRun?
    let okIdentifier: String

    func body(content: Content) -> some View {
        content.alert(
            Text(clash: .copy("Test Run")),
            isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } }),
            presenting: result
        ) { _ in
            Button(role: .cancel) {} label: { Text(clash: .copy("OK")) }
                .accessibilityIdentifier(okIdentifier)
        } message: { result in
            switch result {
            case .passed: Text(clash: .copy("OK — script returned a valid config object."))
             
            case .failed(let message): Text(verbatim: message)
            }
        }
    }
}

 
public enum ClashMacScriptTestRun: Equatable, Sendable {
    case passed
     
    case failed(String)
}

 
public struct ClashMacOverrideScriptDetailActions {
     
     
    public var load: @MainActor (String) async -> ClashMacOverrideScriptDetail?
     
    public var reloadOn: [Notification.Name] = []
     
    public var edit: @MainActor (String) -> Void
     
    public var update: @MainActor (String) -> Void
     
    public var updating: AnyPublisher<Bool, Never> = Just(false).eraseToAnyPublisher()
     
     
    public var testRun: @MainActor (String) async -> ClashMacScriptTestRun
     
    public var rename: @MainActor (String, String) throws -> Void
     
    public var delete: @MainActor (String) -> Void

    public init(
        load: @escaping @MainActor (String) async -> ClashMacOverrideScriptDetail?,
        edit: @escaping @MainActor (String) -> Void,
        update: @escaping @MainActor (String) -> Void,
        testRun: @escaping @MainActor (String) async -> ClashMacScriptTestRun,
        rename: @escaping @MainActor (String, String) throws -> Void,
        delete: @escaping @MainActor (String) -> Void
    ) {
        self.load = load
        self.edit = edit
        self.update = update
        self.testRun = testRun
        self.rename = rename
        self.delete = delete
    }

    public static var unavailable: Self {
        Self(load: { _ in nil }, edit: { _ in }, update: { _ in }, testRun: { _ in .passed },
             rename: { _, _ in throw ConfigurationLibraryError.unreadable }, delete: { _ in })
    }
}

 
 
 
 
 
 
 
 
public struct ClashMacOverrideScriptDetailPage<ConfigurationPage: View>: View {
    private let id: String
    private let actions: ClashMacOverrideScriptDetailActions
    private let configurationPage: (String) -> ConfigurationPage
    @State private var detail: ClashMacOverrideScriptDetail?
    @State private var loaded = false
    @State private var name = ""
     
    @State private var sentName: String?
    @State private var renameFailure: String?
    @State private var testResult: ClashMacScriptTestRun?
     
     
     
     
    @State private var changes: AnyPublisher<Void, Never>
    @State private var updating = false
    @State private var updatingChanges: AnyPublisher<Bool, Never>
     
     
    @State private var reloads = 0
    @FocusState private var nameIsFocused: Bool
    @Environment(\.locale) private var locale

    public init(
        id: String,
        actions: ClashMacOverrideScriptDetailActions,
        @ViewBuilder configurationPage: @escaping (String) -> ConfigurationPage
    ) {
        self.id = id
        self.actions = actions
        self.configurationPage = configurationPage
        _changes = State(initialValue: ClashMacLibraryChanges.publisher(actions.reloadOn))
        _updatingChanges = State(initialValue: actions.updating)
    }

    public var body: some View {
        List {
            if let detail {
                 
                 
                 
                actionsSection(detail)
                facts(detail)
                readers(detail)
                deletion(detail)
            }
        }
        .listStyle(.inset)
        .clashListRetainsRowSelection()
        .accessibilityIdentifier("configuration-center.override-script")
        .navigationTitle(Text(verbatim: detail?.name ?? ""))
        .clashMacPopsWhenGone(loaded && detail == nil)
         
         
        .task(id: reloads) { await reload() }
        .onReceive(changes) { reloads &+= 1 }
        .onReceive(updatingChanges) { updating = $0 }
        .modifier(ClashMacScriptTestRunAlert(result: $testResult, okIdentifier: "configuration-center.override-script.test-run.ok"))
    }

     
    private func actionsSection(_ detail: ClashMacOverrideScriptDetail) -> some View {
        Section {
            HStack(spacing: ClashTheme.Spacing.compact) {
                Button { actions.edit(detail.id) } label: { Text(clash: .copy("Edit…")) }
                    .accessibilityIdentifier("configuration-center.override-script.edit")
                if detail.isLinked {
                    Button { actions.update(detail.id) } label: { Text(clash: .copy("Update")) }
                        .disabled(updating)
                        .accessibilityIdentifier("configuration-center.override-script.update")
                }
                Button { Task { testResult = await actions.testRun(detail.id) } } label: { Text(clash: .copy("Test Run")) }
                    .accessibilityIdentifier("configuration-center.override-script.test-run")
                Spacer()
            }
        }
    }

    private func facts(_ detail: ClashMacOverrideScriptDetail) -> some View {
        Section {
            TextField(text: $name) { Text(clash: .copy("Name")) }
                .accessibilityIdentifier("configuration-center.override-script.name")
                .focused($nameIsFocused)
                 
                 
                .onSubmit { commitName() }
                .onChange(of: nameIsFocused) { focused in
                    if !focused { commitName() }
                    if focused { sentName = nil }
                }
                .onDisappear { commitName() }
            if let renameFailure {
                Text(verbatim: renameFailure)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("configuration-center.override-script.name-error")
            }
            if detail.isLinked, let link = detail.link {
                LabeledContent {
                     
                    Text(verbatim: link)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } label: {
                    Text(clash: .copy("Link"))
                }
                .accessibilityIdentifier("configuration-center.override-script.link")
            }
        }
    }

     
    private func readers(_ detail: ClashMacOverrideScriptDetail) -> some View {
        Section {
            if detail.usedBy.isEmpty {
                Text(clash: ClashLibraryUsageCopy.text(.none)).foregroundStyle(.secondary)
            } else {
                ForEach(detail.usedBy, id: \.id) { configuration in
                    ClashRoutedViewLink {
                        configurationPage(configuration.id)
                    } label: {
                         
                        Text(verbatim: configuration.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier("configuration-center.override-script.used-by.\(configuration.id)")
                }
            }
        } header: {
            Text(clash: .copy("Configurations Using It"))
        }
    }

     
    private func deletion(_ detail: ClashMacOverrideScriptDetail) -> some View {
        Section {
            Button(role: .destructive) { actions.delete(detail.id) } label: {
                 
                Text(clash: .copy("Delete Override Script")).clashMacDestructiveLabel()
            }
            .accessibilityIdentifier("configuration-center.override-script.delete")
        } footer: {
            Text(clash: ClashMacOverrideScriptDeletion.note(detail.deletionNote, locale: locale))
                .accessibilityIdentifier("configuration-center.override-script.delete-note")
        }
    }

    private func reload() async {
        let fresh = await actions.load(id)
        guard !Task.isCancelled else { return }
        loaded = true
        detail = fresh
         
        if let fresh, !nameIsFocused {
            name = fresh.name
            sentName = nil
        }
    }

    private func commitName() {
        guard let detail else { return }
        switch ClashMacScriptNameCommit.decide(typed: name, stored: detail.name, lastSent: sentName,
                                               refused: renameFailure != nil, focused: nameIsFocused) {
        case .nothing: break
        case .restore: name = detail.name
        case .send(let typed):
            sentName = typed
            do {
                try actions.rename(detail.id, typed)
                renameFailure = nil
            } catch {
                 
                renameFailure = ClashErrorCopy.message(error, locale: locale)
                if !nameIsFocused { name = detail.name }
            }
        }
    }
}
