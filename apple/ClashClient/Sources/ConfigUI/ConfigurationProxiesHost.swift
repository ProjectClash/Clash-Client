import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 

 
 
 
 
struct ProxiesPageConfiguration: Equatable {
    let profileID: String
     
    let name: String
     
     
     
    let isCurrent: Bool
     
     
     
     
    let isComposed: Bool
     
     
    let sourceNames: [String]?
     
     
    var updatableSourceIDs: [String] = []

    static func make(profileID: String, name: String, workingProfileID: String?,
                     library: ConfigurationLibrarySnapshot?, locale: Locale) -> Self {
        let recipe = library?.recipes.first { $0.id == profileID }
        let records = recipe?.sources.compactMap { pin in library?.sources.first { $0.id == pin.id } } ?? []
        return ProxiesPageConfiguration(
            profileID: profileID,
            name: name,
            isCurrent: workingProfileID == profileID,
            isComposed: recipe.map { $0.preservesOriginal != true } ?? false,
            sourceNames: recipe.map { recipe in
                recipe.sources.map { pin in
                    library?.sources.first { $0.id == pin.id }?.displayLabel(locale: locale) ?? pin.id
                }
            },
            updatableSourceIDs: records
                .filter { ClashConfigurationSourceLibraryView.rowActions($0).contains(.update) }
                .map(\.id)
        )
    }

     
     
     
    func page() -> ClashProxiesConfigurationPage {
        ClashProxiesConfigurationPage(
            configurationName: name,
            nodeSourceNames: sourceNames,
            isCurrentConfiguration: isCurrent
        )
    }
}

 
 
enum ProxiesOverviewPreparation {
     
     
     
     
     
    @MainActor
    static func model(for profile: Profile, profiles: ProfilesViewModel, command: ClashCommandClient) async -> ProxiesOverviewModel {
        let sourceYAML = await profiles.loadPagesYAML(for: profile)
        let selectedMap = profile.selectedMap
        let profileID = profile.id
         
         
        let container = profiles.appGroupContainer
         
         
         
        let isActive = profiles.activeProfileID == profileID
        let asksKernel = Self.asksKernel(isCurrent: ProxiesOverviewHost.isCurrent(profileID: profileID, in: profiles),
                                    isConnected: command.isConnected, tunnelIsUp: command.tunnelIsUp)
        return await Task.detached(priority: .userInitiated) {
            var providerNodes: [String: [ProxiesOverviewModel.Proxy]] = [:]
            var catalog: ProviderCatalog?
            var notes: [String: ProviderNote] = [:]
            if isActive,
               let container,
               let store = try? ConfigResourceStore(containerURL: container),
               let directory = try? store.activeProvidersDirectory() {
                providerNodes = ProviderNodesLoader.load(providersDir: directory)
                catalog = ProviderCatalog.load(providersDir: directory)
                 
                notes = catalog?.proxyProviderNotes(
                    state: ProviderRefreshState.read(workingDirectory: container.appendingPathComponent("working")),
                    written: ProviderCatalog.writtenAt(providersDir: directory)) ?? [:]
            }
             
             
             
             
             
            let projected = ProxiesOverviewModel.make(
                sourceYAML: sourceYAML,
                selectedMap: selectedMap,
                providerNodes: providerNodes,
                notes: notes
            )
            let resolved = asksKernel
                ? projected.resolvedWithKernelCatalog(
                    input: OfflineProxyCatalogLoader.input(containerURL: container, preferredProfileID: profileID))
                : projected
            return resolved.explainingEmptyProviders(sourceYAML: sourceYAML, catalog: catalog)
        }.value
    }

     
     
     
     
     
     
     
     
    static func asksKernel(isCurrent: Bool, isConnected: Bool, tunnelIsUp: Bool) -> Bool {
        !isCurrent || (!isConnected && !tunnelIsUp)
    }
}

 
 
 
 
 
struct ConfigurationProxiesHost: View {
    @ObservedObject var vpn: VPNController
     
     
    @ObservedObject var command: ClashCommandClient
    let nodes: NodesModel
    @ObservedObject var profiles: ProfilesViewModel
    let profileID: String
     
     
     
    var macNodeSourcesPage: ((String) -> AnyView)? = nil
    var macGroupPages: ProxiesMacGroupPages? = nil
     
     
    var openingGroup: String? = nil
     
     
     
    var refreshes = 0

    @State private var prepared: Prepared?
    @State private var generation: UInt64 = 0
     
     
    @State private var downloadRedraw = ProxiesPageDownloadRedraw()

    private struct Prepared {
        let profileID: String
        let model: ProxiesOverviewModel
    }

     
     
    private struct PreparationKey: Hashable {
        let generation: UInt64
        let revision: String?
        let overrides: ProxyNodeOverrideSpec?
        let libraryEpoch: UInt64
         
         
         
         
        let published: UInt64
    }

     
    @MainActor
    static func page(profileID: String, vpn: VPNController, command: ClashCommandClient,
                     nodes: NodesModel, profiles: ProfilesViewModel) -> AnyView {
        AnyView(ConfigurationProxiesHost(vpn: vpn, command: command, nodes: nodes, profiles: profiles, profileID: profileID))
    }

    var body: some View {
        if let live = profiles.profiles.first(where: { $0.id == profileID }) {
            content(live)
                .task(id: PreparationKey(generation: generation, revision: live.activeRevision,
                                         overrides: live.proxyNodeOverrides, libraryEpoch: profiles.libraryContentEpoch,
                                         published: profiles.publishedGeneration(of: live.id))) {
                    let model = await ProxiesOverviewPreparation.model(for: live, profiles: profiles, command: command)
                    guard !Task.isCancelled else { return }
                    prepared = Prepared(profileID: live.id, model: model)
                }
                 
                 
                 
                 
                 
                .onChange(of: refreshes) { _ in generation &+= 1 }
                .onReceive(NotificationCenter.default.publisher(for: ProviderDownloadActivity.didChangeNotification)) { note in
                    downloadRedraw.note(addresses: ProviderDownloadActivity.addresses(in: note),
                                        pageAddresses: prepared.map { Set($0.model.providers.compactMap(\.url)) }) {
                        generation &+= 1
                    }
                }
        } else {
            ClashEmptyState(title: "No Profile", message: "Add a profile before browsing its proxies.",
                            symbol: .exclamationmarkTriangle)
        }
    }

    @ViewBuilder
    private func content(_ live: Profile) -> some View {
        if let prepared, prepared.profileID == live.id {
            let isCurrent = ProxiesOverviewHost.isCurrent(profileID: live.id, in: profiles)
            ProxiesOverviewHost(
                vpn: vpn,
                command: command,
                nodes: nodes,
                profiles: profiles,
                isConnected: command.isConnected,
                mode: command.mode,
                profile: live,
                 
                sourceModel: prepared.model.applying(selectedMap: live.selectedMap),
                 
                 
                 
                initiallyExpandedGroup: openingGroup ?? (isCurrent
                    ? HomeProxiesEntryPolicy.homeEntry(
                        pending: nil,
                        lastOpened: nodes.currentGroupName,
                        groups: prepared.model.groups,
                        name: \.name,
                        isHidden: \.hidden,
                        coreMode: command.mode,
                        liveCatalog: command.isConnected && nodes.isRuntimeAvailable,
                        readerFoldedAll: nodes.readerFoldedAllGroups
                    )
                    : nil),
                 
                ownsNavigationContainer: false,
                reprepare: { generation &+= 1 },
                macNodeSourcesPage: macNodeSourcesPage,
                macGroupPages: macGroupPages,
                 
                 
                isConfigurationsPage: true
            )
        } else {
            ClashPageLoadingPlaceholder(title: .copy("Loading"))
                .accessibilityIdentifier("proxies.preparing")
        }
    }
}

#if os(iOS)
 
 
 
 
struct ProxiesAddNodesSheet: View {
    @ObservedObject var model: ProfilesViewModel
    let profileID: String
    let configurationName: String
     
    let added: () -> Void
    let close: () -> Void
    @StateObject private var quickAdd: ProfileQuickAddController
    @State private var showsNewNode = false
    @State private var showsNewChain = false
    @State private var failure: String?
    @Environment(\.locale) private var locale

    init(model: ProfilesViewModel, profileID: String, configurationName: String,
         added: @escaping () -> Void, close: @escaping () -> Void) {
        self.model = model
        self.profileID = profileID
        self.configurationName = configurationName
        self.added = added
        self.close = close
        _quickAdd = StateObject(wrappedValue: ProfileQuickAddController(model: model, target: .source))
    }

    var body: some View {
        ClashFeatureNavigationContainer {
            List {
                if let failure {
                    Section { Text(verbatim: failure).foregroundStyle(.red) }
                        .accessibilityIdentifier("proxies.add.failure")
                }
                ProfileQuickAddCard(
                    controller: quickAdd,
                    identifiers: .init(linkIdentifier: "proxies.add.link",
                                       scanIdentifier: "proxies.add.scan",
                                       fileIdentifier: "proxies.add.file",
                                       manualIdentifier: "proxies.add.manual",
                                       statusIdentifier: "proxies.add.status"),
                    manual: { showsNewNode = true },
                    footer: .format("Node sources you add are used for “%@”.", [configurationName]),
                     
                    moreRows: AnyView(
                        Button { showsNewChain = true } label: {
                            Label(ClashCopy.key("New Proxy Chain"), systemImage: ClashSymbol.link.name)
                        }
                        .accessibilityIdentifier("proxies.add.chain")
                    )
                )
            }
            .clashPageTitle("Add Nodes")
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) {
                    ClashSheetCloseButton { close() }
                }
            }
        }
        .profileQuickAddPresenters(quickAdd)
        .onAppear { quickAdd.onNodeSourceAdded = { switchOn($0) } }
        .clashProductModal(isPresented: $showsNewNode, role: .page) {
             
             
            ConfigurationNewNodeAdapter(model: model, library: nil,
                                        changed: { _ in }, close: { showsNewNode = false }, added: { switchOn($0) })
        }
        .clashProductModal(isPresented: $showsNewChain, role: .page) {
            ConfigurationChainEditor(model: model, existing: nil, accept: { payload in
                guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                let generation = try await Task.detached { try store.snapshot().generation }.value
                let updated = try await model.addConfigurationSource(payload, generation: generation)
                switchOn(AddedNodeSource(id: payload.record.id, library: updated))
            }, close: { showsNewChain = false })
        }
    }

     
     
    private func switchOn(_ made: AddedNodeSource) {
        failure = nil
        Task { @MainActor in
            if let said = await Self.use(made, model: model, profileID: profileID, locale: locale) {
                failure = said
            } else {
                added()
            }
        }
    }

     
     
     
     
     
     
    @MainActor
    static func use(_ made: AddedNodeSource, model: ProfilesViewModel, profileID: String, locale: Locale) async -> String? {
        let sources = ConfigurationNodeSourcesModel(model: model, profileID: profileID)
        await sources.set(made.id, on: true)
        if let refused = sources.failure { return refused }
        if sources.isOn(made.id) { return nil }
        let name = made.library.sources.first { $0.id == made.id }?.displayLabel(locale: locale) ?? made.id
        return ClashCopy.string(for: .format("“%@” was added to the Node Library.", [name]), locale: locale)
    }
}
#endif

 
 
 
 
 
 
@MainActor
final class ProxiesPageDownloadRedraw {
     
     
    static let windowNanoseconds: UInt64 = 300_000_000

    private let settler: TrailingEdgeSettler

    init(windowNanoseconds: UInt64 = ProxiesPageDownloadRedraw.windowNanoseconds) {
        settler = TrailingEdgeSettler(windowNanoseconds: windowNanoseconds)
    }

    func note(addresses: Set<String>?, pageAddresses: Set<String>?, redraw: @escaping @MainActor () -> Void) {
        if let addresses, let pageAddresses, addresses.isDisjoint(with: pageAddresses) { return }
        settler.submit(redraw)
    }
}
