#if os(iOS)
import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 

 
 
 
 
 
struct OriginalNodeSourcesSections: View {
    @ObservedObject var session: ConfigurationEditorSession
    let configurationName: String
    let rows: [ConfigurationNodeSourcesModel.SourceRow]
     
     
     
     
     
     
    let picks: [ConfigurationLibraryPicks.Source]?
     
     
    @Binding var door: OriginalAddNodesDoor?
    let inspect: (String) -> Void

    var body: some View {
        let document = session.shownDocument ?? .object([])
        let kinds = ConfigurationNodeSourcesModel.Kind.allCases.filter { kind in rows.contains { $0.kind == kind } }
        ForEach(kinds, id: \.self) { kind in
            Section {
                ForEach(rows.filter { $0.kind == kind }) { row in
                    HStack(spacing: ClashClientUI.ClashTheme.Spacing.row) {
                        if row.switchable, let source = picks?.first(where: { $0.id == row.id }) {
                            linkSwitch(row, source: source, document: document)
                        } else {
                            NodeSourceRowLabel(row: row)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("configuration-editor.sources.source.\(row.id)")
                        }
                        if row.hasPage { NodeSourceInfoButton(id: row.id) { inspect(row.id) } }
                    }
                    .accessibilityElement(children: .contain)
                }
            } header: {
                Text(clash: .copy(kind.title))
            } footer: {
                if kind == .profileURL, session.page?.followsSubscription == true,
                   rows.contains(where: { $0.kind == .profileURL && $0.switchable }) {
                    Text(clash: ConfigurationNodeSourcesCopy.turningOnStopsFollowing(configurationName))
                        .accessibilityIdentifier("configuration-editor.sources.original-links-note")
                }
            }
        }
        OriginalAddNodesRows(session: session, configurationName: configurationName, door: $door)
    }

     
     
    private func linkSwitch(_ row: ConfigurationNodeSourcesModel.SourceRow, source: ConfigurationLibraryPicks.Source,
                            document: OrderedJSON) -> some View {
        let key = "library-link." + source.id
        return Toggle(isOn: Binding(get: { session.shownSwitch(key, else: ConfigurationLibraryPicks.addedSetName(source, in: document) != nil) },
                                    set: { on in
             
            if !on, session.refusesSwitchingOff(source) { return }
            session.pressSwitch(key, on) { await session.setLibraryLink(source, on: on) }
        })) {
            NodeSourceRowLabel(row: row)
        }
         
         
         
         
        .disabled(session.page == nil)
        .accessibilityIdentifier("configuration-editor.sources.source.\(row.id)")
    }
}

 
 
 
 
struct OriginalAddNodesRows: View {
    @ObservedObject var session: ConfigurationEditorSession
    let configurationName: String
     
     
     
     
     
    @Binding var door: OriginalAddNodesDoor?

    var body: some View {
        Section {
            if Self.nodeCount(in: session.shownDocument) == 0 {
                Text(clash: ConfigurationEmptyList.sentence(for: "proxies")).foregroundStyle(.secondary)
                    .accessibilityIdentifier("configuration-editor.original-nodes.empty")
            }
            Button { door = .newNode } label: {
                Label(ClashCopy.key("quick-add.new.node"), systemImage: ClashSymbol.docBadgePlus.name)
            }
            .disabled(session.isSaving || session.page == nil)
            .accessibilityIdentifier("configuration-editor.original-nodes.new")
            Button { door = .library } label: {
                Label(ClashCopy.key("Choose from the Node Library…"), systemImage: ClashSymbol.rectangleStack.name)
            }
            .disabled(session.isSaving || session.page == nil)
            .accessibilityIdentifier("configuration-editor.original-nodes.library")
            if let notice = session.notice {
                Text(clash: notice).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("configuration-editor.original-nodes.notice")
            }
        } header: {
            ClashConfigurationLibraryHeader(title: .copy("Add Nodes"))
        } footer: {
            if session.page?.followsSubscription == true {
                Text(clash: OriginalNodeAdding.addingStopsFollowing(configurationName))
                    .accessibilityIdentifier("configuration-editor.original-nodes.note")
            }
        }
    }

    static func nodeCount(in document: OrderedJSON?) -> Int {
        guard case .array(let nodes)? = document?.topLevelValue("proxies") else { return 0 }
        return nodes.count
    }
}

 
enum OriginalAddNodesDoor: Identifiable {
    case newNode, library
    var id: Self { self }
}

extension View {
     
     
    func originalAddNodesPages(_ door: Binding<OriginalAddNodesDoor?>, session: ConfigurationEditorSession) -> some View {
        clashSheet(item: door) { opened in
            switch opened {
            case .newNode:
                 
                 
                ClashFeatureNavigationContainer {
                    ProxyNodeDetailsView(record: CustomNodesView.newNodeTemplate, retest: {},
                                         saveNode: { _, edited in try await OriginalNodeAdding.add(edited, session: session) },
                                         showsTesting: false, isNew: true, dialerRouting: .payloadField,
                                         dialerCandidates: { ConfigurationOriginalNodePage.candidates(excluding: "", in: session) },
                                         onDone: { door.wrappedValue = nil })
                }
                .clashModalPresentation(.page)
            case .library:
                ConfigurationLibraryNodePicker(store: session.model.configurationLibraryStore, profileID: session.profileID,
                                               document: session.page?.document ?? .object([])) { picked, sources in
                    Task { await session.addLibraryNodes(picked, from: sources) }
                }
                .clashModalPresentation(.page)
            }
        }
    }
}

 
enum OriginalNodeAdding {
     
    static func addingStopsFollowing(_ configuration: String) -> ClashDisplayText {
        .format("Once added, “%@” no longer follows its link.", [configuration])
    }

     
     
    @MainActor
    static func add(_ edited: String, session: ConfigurationEditorSession) async throws {
        let node = OriginalListEdits.handWrittenOrder(try OrderedJSON.parse(edited))
        guard case .string(let name)? = node.node(at: ["name"]), !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw OriginalListError.unnamed
        }
        var count: Int?
        if case .array(let items)? = session.value(at: ["proxies"]) {
            count = items.count
            let names = items.enumerated().map { ConfigurationEditorCopy.entryTitle($1, index: $0) }
            guard !names.contains(name) else { throw OriginalListError.taken(name) }
        }
        try await ConfigurationOriginalNodePage.saveFromForm([OriginalListEdits.appending(node, toListOf: count, at: "proxies")],
                                                             session: session)
    }
}

 
 
 
 
struct OriginalConfigurationSession<Content: View>: View {
    @ObservedObject var model: ProfilesViewModel
    let content: (ConfigurationEditorSession) -> Content
    @StateObject private var session: ConfigurationEditorSession

    init(model: ProfilesViewModel, profileID: String, @ViewBuilder content: @escaping (ConfigurationEditorSession) -> Content) {
        _model = ObservedObject(wrappedValue: model)
        self.content = content
        _session = StateObject(wrappedValue: ConfigurationEditorSession(profileID: profileID, model: model))
    }

    private var revision: String { model.profiles.first { $0.id == session.profileID }?.activeRevision ?? "" }

    var body: some View {
        content(session)
            .configurationPushedAlertHost(session)
            .task(id: revision) { await session.reload() }
    }
}

 
 
 
struct OriginalAddNodesSheet: View {
    @ObservedObject var model: ProfilesViewModel
    let profileID: String
    let configurationName: String
    let close: () -> Void
    @State private var door: OriginalAddNodesDoor?

    var body: some View {
        ClashFeatureNavigationContainer {
            OriginalConfigurationSession(model: model, profileID: profileID) { session in
                List {
                    OriginalAddNodesRows(session: session, configurationName: configurationName, door: $door)
                }
                .clashPageTitle("Add Nodes")
                 
                .originalAddNodesPages($door, session: session)
            }
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) { ClashSheetCloseButton { close() } }
            }
        }
    }
}

 
 
 
 
struct OriginalNodeEditorPage: View {
    @ObservedObject var model: ProfilesViewModel
    let profileID: String
    let name: String
    let saved: () -> Void
    let close: () -> Void

    var body: some View {
        ClashFeatureNavigationContainer {
            OriginalConfigurationSession(model: model, profileID: profileID) { session in
                if session.page == nil {
                    ClashPageLoadingPlaceholder(title: .copy("Loading"))
                } else {
                    ConfigurationOriginalNodePage(session: session, name: name, saved: saved, onDone: close)
                }
            }
        }
        .clashModalPresentation(.page)
    }
}
#endif
