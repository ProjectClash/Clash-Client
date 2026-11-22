import ClashClientKit
import ClashClientUI
import Combine
import SwiftUI

 
 
 
 
 
 
 
 
public struct ClashMacOverrideLibraryRow: Identifiable, Equatable, Sendable {
    public let id: String
     
    public let name: String
     
    public let usage: ClashDisplayText
     
    public let isLinked: Bool

    public init(id: String, name: String, usage: ClashDisplayText, isLinked: Bool) {
        self.id = id
        self.name = name
        self.usage = usage
        self.isLinked = isLinked
    }

     
    public func subtitle(locale: Locale) -> String {
        ClashCopy.string(for: usage, locale: locale)
    }
}

 
 
 
public struct ClashMacOverrideLibraryActions {
     
     
    public var load: @MainActor () async -> [ClashMacOverrideLibraryRow]
     
     
    public var reloadOn: [Notification.Name] = []
     
    public var edit: @MainActor (String) -> Void
     
    public var update: @MainActor (String) -> Void
     
     
    public var updating: AnyPublisher<Bool, Never> = Just(false).eraseToAnyPublisher()
     
     
    public var delete: @MainActor (String) -> Void
     
    public var testRun: @MainActor (String) async -> ClashMacScriptTestRun = { _ in .passed }
     
     
    public var addLink: @MainActor (String) async throws -> Void
    public var addManual: @MainActor (String, String) async throws -> Void

    public init(
        load: @escaping @MainActor () async -> [ClashMacOverrideLibraryRow],
        edit: @escaping @MainActor (String) -> Void,
        update: @escaping @MainActor (String) -> Void,
        delete: @escaping @MainActor (String) -> Void,
        addLink: @escaping @MainActor (String) async throws -> Void,
        addManual: @escaping @MainActor (String, String) async throws -> Void
    ) {
        self.load = load
        self.edit = edit
        self.update = update
        self.delete = delete
        self.addLink = addLink
        self.addManual = addManual
    }

    public static var unavailable: Self {
        Self(load: { [] }, edit: { _ in }, update: { _ in }, delete: { _ in },
             addLink: { _ in throw ConfigurationLibraryError.unreadable },
             addManual: { _, _ in throw ConfigurationLibraryError.unreadable })
    }
}

 
 
 
 
 
enum ClashMacLibraryChanges {
    static func publisher(_ names: [Notification.Name]) -> AnyPublisher<Void, Never> {
        Publishers.MergeMany(names.map { NotificationCenter.default.publisher(for: $0) })
            .map { _ in () }
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

 
 
 
 
 
 
 
 
 
 
public struct ClashMacOverrideLibraryPage<Detail: View>: View {
    private let actions: ClashMacOverrideLibraryActions
     
    private let quickAdd: AnyView?
    private let detail: (String) -> Detail
    @State private var rows: [ClashMacOverrideLibraryRow] = []
     
     
     
    @State private var changes: AnyPublisher<Void, Never>
    @State private var updating = false
    @State private var updatingChanges: AnyPublisher<Bool, Never>
     
     
    @State private var reloads = 0
     
    @State private var loaded = false
     
    @State private var testResult: ClashMacScriptTestRun?

    public init(
        actions: ClashMacOverrideLibraryActions,
        quickAdd: AnyView? = nil,
        @ViewBuilder detail: @escaping (String) -> Detail
    ) {
        self.actions = actions
        self.quickAdd = quickAdd
        self.detail = detail
        _changes = State(initialValue: ClashMacLibraryChanges.publisher(actions.reloadOn))
        _updatingChanges = State(initialValue: actions.updating)
    }

    public var body: some View {
        List {
            Color.clear
                .frame(height: ClashTheme.Spacing.standard)
                .clashMacPlainRow()
            Text(clash: .copy("Override Scripts"))
                .clashMacGroupHeader(first: true, margin: 0)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                ClashMacOverrideLibraryRowView(row: row, actions: actions, updating: updating,
                                               testRun: { id in Task { testResult = await actions.testRun(id) } }, detail: detail)
                    .clashMacGroupRow(first: index == 0, last: index == rows.count - 1, margin: 0)
            }
             
            if loaded && rows.isEmpty {
                Text(clash: .copy("None")).foregroundStyle(.secondary)
                    .clashMacGroupRow(first: true, last: true, margin: 0)
            }
            if let quickAdd { quickAdd }
            Color.clear
                .frame(height: ClashTheme.Spacing.section)
                .clashMacPlainRow()
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .environment(\.clashMacGroupedList, true)
        .modifier(ClashMacHardTopEdge())
        .clashListRetainsRowSelection()
        .accessibilityIdentifier("configuration-center.override-library")
         
         
        .task(id: reloads) {
            let fresh = await actions.load()
            guard !Task.isCancelled else { return }
            rows = fresh
            loaded = true
        }
        .onReceive(changes) { reloads &+= 1 }
        .onReceive(updatingChanges) { updating = $0 }
        .modifier(ClashMacScriptTestRunAlert(result: $testResult, okIdentifier: "configuration-center.override-library.test-run.ok"))
    }
}

 
 
 
 
 
 
public struct ClashMacOverrideLibraryAddSheet: View {
    private let actions: ClashMacOverrideLibraryActions
    private let close: () -> Void

    public init(actions: ClashMacOverrideLibraryActions, close: @escaping () -> Void) {
        self.actions = actions
        self.close = close
    }

    public var body: some View {
        ClashMacScriptAddSheet(
            addLink: { link in try await actions.addLink(link); close() },
            addManual: { name, body in try await actions.addManual(name, body); close() },
            close: close
        )
    }
}

 
 
enum ClashMacOverrideLibraryRowMenu {
    enum Item: Hashable { case edit, update, testRun, delete }

    static func items(isLinked: Bool) -> [Item] {
        isLinked ? [.edit, .update, .testRun, .delete] : [.edit, .testRun, .delete]
    }
}

 
 
struct ClashMacOverrideLibraryRowView<Detail: View>: View {
    let row: ClashMacOverrideLibraryRow
    let actions: ClashMacOverrideLibraryActions
     
    let updating: Bool
     
    let testRun: (String) -> Void
    let detail: (String) -> Detail
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: ClashTheme.Spacing.compact) {
            ClashRoutedViewLink {
                detail(row.id)
            } label: {
                ClashMacLibraryRowLabel(
                    title: .verbatim(row.name),
                    subtitle: .verbatim(row.subtitle(locale: locale))
                )
            }
            .accessibilityIdentifier("configuration-center.override-library.row.\(row.id)")
            Menu { menu } label: {
                ClashSymbolImage(symbol: .ellipsisCircle)
                    .foregroundStyle(.secondary)
                    .frame(width: ClashTheme.Control.pointerRowTarget)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(Text(clash: .copy("More")))
            .accessibilityLabel(Text(clash: .copy("More")))
            .accessibilityIdentifier("configuration-center.override-library.menu.\(row.id)")
        }
        .contextMenu { menu }
        .accessibilityElement(children: .contain)
    }

     
     
    @ViewBuilder
    private var menu: some View {
        ForEach(ClashMacOverrideLibraryRowMenu.items(isLinked: row.isLinked), id: \.self) { item in menuItem(item) }
    }

    @ViewBuilder
    private func menuItem(_ item: ClashMacOverrideLibraryRowMenu.Item) -> some View {
        switch item {
        case .edit:
            Button { actions.edit(row.id) } label: { Text(clash: .copy("Edit…")) }
                .accessibilityIdentifier("configuration-center.override-library.row.edit")
        case .update:
            Button { actions.update(row.id) } label: { Text(clash: .copy("Update")) }
                .disabled(updating)
                .accessibilityIdentifier("configuration-center.override-library.row.update")
        case .testRun:
            Button { testRun(row.id) } label: { Text(clash: .copy("Test Run")) }
                .accessibilityIdentifier("configuration-center.override-library.row.test-run")
        case .delete:
            Divider()
            Button(role: .destructive) { actions.delete(row.id) } label: { Text(clash: .copy("Delete")) }
                .accessibilityIdentifier("configuration-center.override-library.row.delete")
        }
    }
}
