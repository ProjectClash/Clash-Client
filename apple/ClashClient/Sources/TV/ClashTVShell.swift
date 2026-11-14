import SwiftUI

 
 
 
 
 
 
 
struct ClashTVShell: View {
     
     
     
    enum Tab: Hashable { case home, utilities, more }

    var stage: ClashTVTestStage?
     
     
    let matrix: ClashTVLaunchOverrides?
     
     
     
    var connectsOnLaunch = false
     
     
    var updatesOnLaunch = false

    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: Tab = .home
     
     
    @State private var fixture: ClashTVProductState
     
     
    @StateObject private var tunnel: ClashTVTunnelController
     
     
     
    @State private var store: ClashTVSubscriptionStore
     
     
     
     
     
     
     
     
     
     
    enum HomeDoor: Hashable {
         
        case outboundMode
         
         
        case nodes
         
        case subscriptions
         
         
        case iCloudRestore
         
         
        case addSubscription
         
        case subscription(ClashTVSubscription.ID)
         
        case edit(ClashTVSubscription.ID)
         
        case rules(ClashTVSubscription.ID)
         
        case autoUpdate(ClashTVSubscription.ID)
         
        case script(ClashTVSubscription.ID)
    }
    @State private var homePath: [HomeDoor] = []
     
     
    @State private var globalQuestion: ClashTunnelOutboundMode.GlobalExit?
     
     
    @State private var nodesOpening: String?
     
    @State private var opensNodesAfterQuestion = false
     
     
    @State private var nodesOpeningState = ClashTVNodesScreen.OpeningGroup.listed
     
     
    @State private var nodesOpeningRead: UInt64 = 0
     
    @State private var nodesOpeningTask: Task<Void, Never>?
     
     
    @State private var globalTicket: ClashTVTunnelController.GlobalQuestionTicket?

    private func homeDoorOpen(_ door: HomeDoor) -> Bool { homePath.contains(door) }

     
     
     
    private func dropTicketAfterTheButtons() {
        DispatchQueue.main.async { if globalQuestion == nil { globalTicket = nil } }
    }

     
    private var globalQuestionWatch: some View {
        Color.clear
             
             
             
            .onChange(of: homePath) { _, path in
                if !path.contains(.nodes) {
                    nodesOpening = nil
                    nodesOpeningState = .listed
                    nodesOpeningRead &+= 1
                    nodesOpeningTask?.cancel()
                    nodesOpeningTask = nil
                }
                if !path.contains(.outboundMode) {
                    globalQuestion = nil
                    globalTicket = nil
                    opensNodesAfterQuestion = false
                    tunnel.dropGlobalQuestion()
                }
            }
             
             
            .onChange(of: globalQuestion) { _, question in
                if question == nil, opensNodesAfterQuestion { openNodesForGlobal() }
            }
             
             
             
            .onChange(of: tunnel.state.isConnected) { _, _ in globalQuestion = nil; globalTicket = nil; tunnel.dropGlobalQuestion() }
            .onChange(of: store.current?.id) { _, _ in globalQuestion = nil; globalTicket = nil; tunnel.dropGlobalQuestion() }
            .accessibilityHidden(true)
    }

     
     
     
    private func openNodesForGlobal() {
        guard opensNodesAfterQuestion else { return }
        opensNodesAfterQuestion = false
        let group = ClashTVGlobalModeQuestion.groupName
        nodesOpening = group
        setHomeDoor(.nodes, open: true)
         
         
         
        nodesOpeningState = .listed
        nodesOpeningRead &+= 1
        nodesOpeningTask?.cancel()
        nodesOpeningTask = nil
        let listed = tunnel.state.proxyGroups.contains { $0.name == group }
            || tunnel.state.hiddenProxyGroups.contains { $0.name == group }
        if live, !listed {
            let read = nodesOpeningRead
            nodesOpeningState = .reading
            nodesOpeningTask = Task {
                let found = await tunnel.readGroupsUntilListed(group)
                 
                guard !Task.isCancelled, read == nodesOpeningRead, nodesOpening == group else { return }
                nodesOpeningState = found ? .listed : .missing
            }
        }
    }

     
     
    private func setHomeDoor(_ door: HomeDoor, open: Bool) {
        if open {
            if !homePath.contains(door) { homePath.append(door) }
        } else if let index = homePath.firstIndex(of: door) {
            homePath.removeSubrange(index...)
        }
    }

    private func homeDoorBinding(_ door: HomeDoor) -> Binding<Bool> {
        Binding(get: { homeDoorOpen(door) }, set: { setHomeDoor(door, open: $0) })
    }

     
     
    private func homeDoorID(_ kind: (ClashTVSubscription.ID) -> HomeDoor, _ matches: (HomeDoor) -> ClashTVSubscription.ID?) -> ClashTVSubscription.ID? {
        for door in homePath { if let id = matches(door) { return id } }
        return nil
    }

    private func setHomeDoorID(_ id: ClashTVSubscription.ID?, kind: (ClashTVSubscription.ID) -> HomeDoor, matches: (HomeDoor) -> ClashTVSubscription.ID?) {
        if let index = homePath.firstIndex(where: { matches($0) != nil }) {
            homePath.removeSubrange(index...)
        }
        if let id { homePath.append(kind(id)) }
    }

    private var showsAddSubscription: Bool {
        get { homeDoorOpen(.addSubscription) }
        nonmutating set { setHomeDoor(.addSubscription, open: newValue) }
    }
    private var showsOutboundMode: Bool {
        get { homeDoorOpen(.outboundMode) }
        nonmutating set { setHomeDoor(.outboundMode, open: newValue) }
    }
    private var showsSubscriptions: Bool {
        get { homeDoorOpen(.subscriptions) }
        nonmutating set { setHomeDoor(.subscriptions, open: newValue) }
    }
    private var showsNodes: Bool {
        get { homeDoorOpen(.nodes) }
        nonmutating set { setHomeDoor(.nodes, open: newValue) }
    }
    private var showsICloudRestore: Bool {
        get { homeDoorOpen(.iCloudRestore) }
        nonmutating set { setHomeDoor(.iCloudRestore, open: newValue) }
    }
    private var subscriptionDoor: ClashTVSubscription.ID? {
        get { homeDoorID(HomeDoor.subscription) { if case .subscription(let id) = $0 { return id }; return nil } }
        nonmutating set { setHomeDoorID(newValue, kind: HomeDoor.subscription) { if case .subscription(let id) = $0 { return id }; return nil } }
    }
    private var editDoor: ClashTVSubscription.ID? {
        get { homeDoorID(HomeDoor.edit) { if case .edit(let id) = $0 { return id }; return nil } }
        nonmutating set { setHomeDoorID(newValue, kind: HomeDoor.edit) { if case .edit(let id) = $0 { return id }; return nil } }
    }
    private var rulesDoor: ClashTVSubscription.ID? {
        get { homeDoorID(HomeDoor.rules) { if case .rules(let id) = $0 { return id }; return nil } }
        nonmutating set { setHomeDoorID(newValue, kind: HomeDoor.rules) { if case .rules(let id) = $0 { return id }; return nil } }
    }
    private var autoUpdateDoor: ClashTVSubscription.ID? {
        get { homeDoorID(HomeDoor.autoUpdate) { if case .autoUpdate(let id) = $0 { return id }; return nil } }
        nonmutating set { setHomeDoorID(newValue, kind: HomeDoor.autoUpdate) { if case .autoUpdate(let id) = $0 { return id }; return nil } }
    }
    private var scriptDoor: ClashTVSubscription.ID? {
        get { homeDoorID(HomeDoor.script) { if case .script(let id) = $0 { return id }; return nil } }
        nonmutating set { setHomeDoorID(newValue, kind: HomeDoor.script) { if case .script(let id) = $0 { return id }; return nil } }
    }
     
     
    @State private var utilitiesDoor: ClashTVUtilitiesHub.Door?
     
    @State private var moreDoor: ClashTVMoreHub.Door?
     
     
     
     
     
    @State private var throughputUnit = ClashThroughputUnit.stored(in: UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite))
     
     
    @State private var iCloudRestoreFromList = false
     
     
     
     
    @State private var connectionDoor: ClashTVConnectionsScreen.Door?
     
     
     
     
     
     
     
    @State private var showsProviders = false
     
     
     
     
    @State private var wasInBackground = false
     
    @State private var lastAnnouncedFeedback = 0

    init(stage: ClashTVTestStage?, connectsOnLaunch: Bool = false, updatesOnLaunch: Bool = false, matrix: ClashTVLaunchOverrides? = nil, store: ClashTVSubscriptionStore = ClashTVSubscriptionStore()) {
        self.stage = stage
        self.connectsOnLaunch = connectsOnLaunch
        self.updatesOnLaunch = updatesOnLaunch
        self.matrix = matrix
        let fixture: ClashTVProductState.Fixture = switch stage {
        case .nodesMany: .manyGroups
        case .nodesManyTen: .manyGroupsTenNodes
        case .nodesLongNames: .longNames
        default: .prototype
        }
        var fixtureState = ClashTVProductState(fixture: fixture)
         
         
        if stage == .welcome { fixtureState.iCloudRestoreLine = String(localized: "Restore from iCloud") }


        _fixture = State(initialValue: fixtureState)

        _tunnel = StateObject(wrappedValue: ClashTVTunnelController())

         
         
         
        var store = stage == .subscriptions || stage == .subscriptionDetail || stage == .editSubscription || stage == .addSubscription || stage == .profileRules
            ? ClashTVSubscriptionStore.stageFixture()
            : store


        _store = State(initialValue: store)
    }

     
     
    private var iCloudRestoreScreen: some View {
        ClashTVICloudRestoreScreen(
            state: state,
            service: live ? tunnel.iCloudRestore : nil,
            store: $store,
            onDone: closeICloudRestore
        )
    }

    private func closeICloudRestore() {
        var restoreOpen = showsICloudRestore
        var subscriptionsOpen = showsSubscriptions
        Self.finishICloudRestore(fromList: iCloudRestoreFromList,
                                 restoreOpen: &restoreOpen,
                                 subscriptionsOpen: &subscriptionsOpen)
        showsICloudRestore = restoreOpen
        showsSubscriptions = subscriptionsOpen
    }

     
     
    static func finishICloudRestore(fromList: Bool, restoreOpen: inout Bool,
                                   subscriptionsOpen: inout Bool) {
        restoreOpen = false
        if fromList { subscriptionsOpen = true }
    }

     
    @ViewBuilder
    private func homeScreen(for door: HomeDoor) -> some View {
        switch door {
        case .iCloudRestore:
            iCloudRestoreScreen
        case .outboundMode:
            ClashTVOutboundModeScreen(
                state: state,
                 
                 
                onSelect: live ? { mode in Task {
                     
                    if case .ask(let exit) = await tunnel.requestMode(mode), homePath.last == .outboundMode {
                        globalTicket = tunnel.globalQuestionTicket()
                        globalQuestion = exit
                    }
                } } : nil
            )
            .alert(ClashTVGlobalModeQuestion.title.localizedForTelevision,
                    
                    
                   isPresented: Binding(get: { globalQuestion != nil },
                                        set: { if !$0 { globalQuestion = nil; tunnel.dropGlobalQuestion(); dropTicketAfterTheButtons() } }),
                   presenting: globalQuestion) { _ in
                Button("Choose Node") {
                    tunnel.dropGlobalQuestion()
                    opensNodesAfterQuestion = true
                     
                    if globalQuestion == nil { openNodesForGlobal() }
                }
                 
                 
                 
                 
                Button("Switch Anyway") {
                    let ticket = globalTicket
                    globalTicket = nil
                    Task { await tunnel.switchGlobalAnyway(ticket) }
                }
                Button("Cancel", role: .cancel) { tunnel.dropGlobalQuestion() }
            } message: { exit in
                Text(ClashTVGlobalModeQuestion.message(exit).localizedForTelevision)
            }
        case .nodes:
            ClashTVNodesScreen(
                state: state,
                onPin: live ? { member, group in Task { await tunnel.pin(member: member, group: group) } } : nil,
                onUnpin: live ? { group in Task { await tunnel.unpin(group: group.name) } } : nil,
                onTestAll: live ? { group in Task { await tunnel.testAll(group: group) } } : nil,
                onTest: live ? { member, group in Task { await tunnel.testOne(member: member, in: group) } } : nil,
                onNeedMoreMembers: live ? { group in Task { await tunnel.loadMoreMembers(of: group) } } : nil,
                opening: nodesOpening,
                openingState: nodesOpeningState
            )
        case .subscriptions:
            ClashTVSubscriptionsScreen(
                store: $store,
                onOpen: { subscriptionDoor = $0 },
                onAdd: { showsAddSubscription = true },
                onRestore: {
                    iCloudRestoreFromList = true
                    showsICloudRestore = true
                }
            )
        case .subscription(let id):
            ClashTVSubscriptionDetailScreen(
                store: $store,
                id: id,
                refresh: live ? tunnel.state.refresh : nil,
                onDone: {
                     
                     
                     
                     
                    state.wrappedValue.beginOperation()
                     
                     
                     
                     
                     
                    subscriptionDoor = nil
                },
                onUpdate: live ? {
                    if let subscription = store.subscriptions.first(where: { $0.id == id }) {
                        Task { await tunnel.refresh(subscription: subscription) }
                    }
                } : nil,
                onEdit: { editDoor = id },
                onRules: { rulesDoor = id },
                onAutoUpdate: { autoUpdateDoor = id },
                onScript: { scriptDoor = id },
                feedback: state.wrappedValue.feedback(for: [.update(id), .script(id)])
            )
        case .script(let id):
            ClashTVProfileScriptScreen(
                store: $store,
                id: id,
                onUpdateScript: live ? {
                    if let subscription = store.subscriptions.first(where: { $0.id == id }) {
                        Task { await tunnel.updateScript(subscription: subscription, isCurrent: store.current?.id == id) }
                    }
                } : nil,
                refresh: live ? tunnel.state.refresh : nil,
                feedback: state.wrappedValue.feedback(for: [.script(id), .update(id)])
            ) { changedID in
                 
                 
                 
                 
                scriptDoor = nil
                guard live, let subscription = Self.refreshAfterDoor(changed: changedID != nil, id: id, in: store) else { return }
                Task { await tunnel.refresh(subscription: subscription) }
            }
        case .autoUpdate(let id):
            ClashTVAutoUpdateScreen(store: $store, id: id) { _ in
                autoUpdateDoor = nil
                scheduleBackgroundRefresh()
            }
        case .rules(let id):
            ClashTVProfileRulesScreen(store: $store, id: id) { row, changed in
                 
                rulesDoor = nil
                 
                 
                 
                 
                guard live, let subscription = Self.refreshAfterDoor(changed: changed, id: row.id, in: store) else { return }
                Task { await tunnel.refresh(subscription: subscription) }
            }
        case .edit(let id):
            ClashTVEditSubscriptionScreen(store: $store, id: id) { newAddress in
                 
                 
                editDoor = nil
                 
                 
                 
                 
                 
                 
                guard live,
                      let subscription = ClashTVEditSubscriptionScreen.refreshTarget(
                          newAddress: newAddress, in: store
                      )
                else { return }
                Task { await tunnel.refresh(subscription: subscription) }
            }
        case .addSubscription:
            ClashTVAddSubscriptionScreen(store: $store, onAdding: {
                state.wrappedValue.beginOperation()
            }, onAdded: {
                 
                 
                showsAddSubscription = false
            }, onAlreadyListed: { title in
                state.wrappedValue.post(ClashTVFeedback.alreadyAdded(title), for: .add)
            })
        }
    }

     
     
     
     
    static func refreshAfterDoor(changed: Bool, id: ClashTVSubscription.ID, in store: ClashTVSubscriptionStore) -> ClashTVSubscription? {
        guard changed, store.current?.id == id else { return nil }
        return store.subscriptions.first { $0.id == id }
    }

    private var hasConfiguration: Bool {
        !store.subscriptions.isEmpty
    }

     
     
     
    private var live: Bool { stage == nil }

    private var state: Binding<ClashTVProductState> {
        live ? $tunnel.state : $fixture
    }

     
     
     
    private func primaryAction() {
         
         
        tunnel.state.beginOperation()
        let presentation = ClashTVHomePresentation.make(state: tunnel.state)
        Task {
            if tunnel.state.isConnected || presentation.cancels {
                await tunnel.disconnect()
                return
            }
             
             
            if presentation.reinstallsVPNProfile {
                await tunnel.reinstallVPNProfile()
                return
            }
             
             
            if let refreshed = await tunnel.refreshRestoredProfilesIfNewer(store: store) { store = refreshed }
            guard let current = store.current else { return }


            await tunnel.connect(subscription: current)
        }
    }

    var body: some View {
        TabView(selection: $tab) {
             
             
             
             
             
            NavigationStack(path: $homePath) {
                Group {
                    if hasConfiguration || stage == .home || stage == .connected || stage == .outboundMode
                        || stage == .globalQuestion || stage == .chooseNodeGlobal {
                        ClashTVHomeView(
                            state: state,
                            showsOutboundMode: homeDoorBinding(.outboundMode),
                            showsSubscriptions: homeDoorBinding(.subscriptions),
                            showsNodes: homeDoorBinding(.nodes),
                            onPrimaryAction: live ? primaryAction : nil
                        )
                    } else {
                        ClashTVWelcomeView(
                            onAddSubscription: { showsAddSubscription = true },
                            restoreLine: state.wrappedValue.iCloudRestoreLine,
                            onRestore: {
                                iCloudRestoreFromList = false
                                showsICloudRestore = true
                            }
                        )
                    }
                }
                .navigationDestination(for: HomeDoor.self) { door in
                    homeScreen(for: door)
                }
            }
             
             
             
             
            .clashTVTitleSafe()
            .tabItem { Text("Home") }
            .tag(Tab.home)

            utilitiesTab
                .clashTVTitleSafe()
                .tabItem { Text("Utilities") }
                .tag(Tab.utilities)

             
             
            NavigationStack {
                ClashTVMoreHub(state: state, opened: $moreDoor, onAutoConnect: { wanted in
                     
                     
                     
                     
                     
                    Task { await tunnel.setAutoConnect(wanted) }
                })
                    .navigationDestination(item: $moreDoor) { door in
                        switch door {
                        case .ipStack:
                            ClashTVIPStackScreen(tunnel: tunnel)
                        case .dns:
                            ClashTVDNSScreen(state: state)
                        case .userAgent:
                            ClashTVUserAgentScreen()
                        case .proxyShare:
                            ClashTVProxyShareScreen(state: state, tunnel: tunnel)
                        case .externalController:
                            ClashTVExternalControllerScreen(state: state, core: .live(tunnel))
                        case .diagnostics:
                            ClashTVDiagnosticsScreen(
                                state: state,
                                openDNS: { moreDoor = .dns },
                                openProviders: { showsProviders = true }
                            )
                        case .logs:
                             
                             
                            ClashTVLogsScreen(reader: ClashTVLogsScreen.reader(live: live))
                        }
                    }
                    .navigationDestination(isPresented: $showsProviders) {
                        ClashTVProvidersScreen(state: state)
                    }
            }
            .clashTVTitleSafe()
            .tabItem { Text("More") }
            .tag(Tab.more)
        }
         
         
        .background(globalQuestionWatch)
         
         
         
         
         
        .onChange(of: scenePhase) { _, phase in
            if live, phase == .active { Task { await scanForDueUpdate() } }
             
             
             
            switch phase {
            case .active:
                if wasInBackground { state.wrappedValue.feedback.dropTransient() }
                wasInBackground = false
                state.wrappedValue.feedback.resume(now: Date())
            case .background:
                wasInBackground = true
                state.wrappedValue.feedback.pause(now: Date())
                 
                if live { Task { await tunnel.endSweep() } }
            default:
                state.wrappedValue.feedback.pause(now: Date())
            }
        }


        .onChange(of: tunnel.lastActivation) { _, activation in
             
             
             
            guard let activation else { return }
            store.markUpdated(activation.subscriptionID, at: activation.at)
             
             
            store.adoptPanelName(activation.subscriptionID, activation.panelName)
        }
        .onChange(of: store.current, initial: true) { previous, current in
             
             
             
             
             
             
            let row = Self.homeProfileRow(for: current, fixture: ClashTVProductState())
            state.wrappedValue.profileName = row.name
            state.wrappedValue.profileAge = row.age
            state.wrappedValue.profileUpdatedAt = current?.updatedAt
             
             
             
             
             
             
            guard live, previous?.id != current?.id else { return }
            if let current {
                Task { await tunnel.subscriptionChanged(to: current) }
            } else {
                Task { await tunnel.disconnect() }
            }
        }
        .task(id: stage) {
            if live {


                await tunnel.probeICloudForWelcome()
                if let refreshed = await tunnel.refreshRestoredProfilesIfNewer(store: store) { store = refreshed }
            }
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            guard stage == .connectionsLive || stage == .connectionDetail else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                ClashTVConnectionsScreen.liveTick(&fixture, at: Date())
            }
        }
        .environment(\.clashTVPollingPresentation, pollingPresentation)
        .environment(\.clashThroughputUnit, throughputUnit)
        .onReceive(NotificationCenter.default.publisher(for: ClashThroughputUnit.didChangeNotification)) { _ in
            throughputUnit = ClashThroughputUnit.stored(in: UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite))
        }
        .onChange(of: pollingPresentation, initial: true) { _, value in
            if live { tunnel.updatePresentation(value) }
        }
        .onDisappear {
            if live { tunnel.updatePresentation(.init(page: .configuration, active: false)) }
        }
        .onExitCommand(perform: currentTabDoor == nil ? nil : closeTopmostDoor)
         
         
         
        .overlay(alignment: .topTrailing) { feedbackBanner }
        .onChange(of: feedbackScreen, initial: true) { previous, current in
             
             
             
            state.wrappedValue.enterFeedbackScreen(current, from: previous)
        }
        .onChange(of: state.wrappedValue.feedback.current?.id) { _, id in
             
             
            guard let id, id > lastAnnouncedFeedback,
                  let presentation = state.wrappedValue.feedback.current?.presentation else { return }
            lastAnnouncedFeedback = id
            AccessibilityNotification.Announcement(ClashTVFeedback.spoken(presentation)).post()
        }
        .task(id: state.wrappedValue.feedback.current?.deadline) {
            guard let deadline = state.wrappedValue.feedback.current?.deadline else { return }
            let wait = deadline.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
             
             
             
            state.wrappedValue.feedback.expire(now: max(Date(), deadline))
        }

        .task {
             
             
            if live {
                await runMatrixPreparation()
                if connectsOnLaunch { primaryAction() }
                await scanForDueUpdate()
                await runMatrixProbes()
                if updatesOnLaunch, let current = store.current {
                    showsSubscriptions = true
                    try? await Task.sleep(for: .milliseconds(400))
                    subscriptionDoor = current.id
                    Task { await tunnel.refresh(subscription: current) }
                }


            }
             
             
            if stage == .connected { fixture.stage = .connected }
            if stage == .outboundMode { showsOutboundMode = true }
            if stage == .globalQuestion {
                showsOutboundMode = true
                 
                try? await Task.sleep(for: .milliseconds(800))
                globalQuestion = .direct
            }
            if stage == .chooseNodeGlobal {
                nodesOpening = ClashTVGlobalModeQuestion.groupName
                homePath = [.outboundMode, .nodes]
            }
            if let mode = stage?.outboundModeOverride { fixture.outboundMode = mode }
            if stage?.opensNodes == true {
                tab = .utilities
                utilitiesDoor = .nodes
            }
            if stage == .rules {
                tab = .utilities
                utilitiesDoor = .rules
            }
            if stage == .connections || stage == .connectionsLive || stage == .connectionDetail {
                 
                 
                 
                fixture.stage = .connected
                tab = .utilities
                utilitiesDoor = .connections
                 
                 
                if ProcessInfo.processInfo.environment["CLASH_TV_CONNECTIONS_EMPTY"] == "1" { fixture.connections = [] }
            }
            if stage == .connectionDetail, let first = ClashTVConnectionsScreen.rows(fixture.connections, kind: .all).first {
                 
                 
                 
                try? await Task.sleep(for: .milliseconds(400))
                connectionDoor = ClashTVConnectionsScreen.Door(connection: first)
            }
            if stage == .subscriptions { showsSubscriptions = true }
            if stage == .subscriptionDetail {
                 
                 
                 
                showsSubscriptions = true
                try? await Task.sleep(for: .milliseconds(400))
                subscriptionDoor = store.subscriptions.first { $0.id != store.current?.id }?.id
            }
            if stage == .editSubscription, let current = store.current {
                 
                showsSubscriptions = true
                try? await Task.sleep(for: .milliseconds(400))
                subscriptionDoor = current.id
                try? await Task.sleep(for: .milliseconds(400))
                editDoor = current.id
            }
            if stage == .profileRules, let current = store.current {
                 
                showsSubscriptions = true
                try? await Task.sleep(for: .milliseconds(400))
                subscriptionDoor = current.id
                try? await Task.sleep(for: .milliseconds(400))
                rulesDoor = current.id
            }
            if stage == .addSubscription { showsAddSubscription = true }
            if stage == .more {
                tab = .more
                 
                 
                if ProcessInfo.processInfo.environment["CLASH_TV_MORE_DOOR"] == "ipStack" { moreDoor = .ipStack }
            }
            if stage == .diagnostics {
                tab = .more
                moreDoor = .diagnostics
                 
                 
                if ProcessInfo.processInfo.environment["CLASH_TV_LAST_PROBLEM"] == "externalController" {
                    fixture.note(problem: ClashTVExternalControllerScreen.lastProblemLine("listen tcp :9090: bind: address already in use"))
                }
            }
            if stage == .logs { tab = .more; moreDoor = .logs }
            if stage == .dns { tab = .more; moreDoor = .dns }
            if stage == .userAgent { tab = .more; moreDoor = .userAgent }
            if stage == .proxyShare { tab = .more; moreDoor = .proxyShare }
            if stage == .providers {
                 
                 
                 
                tab = .more
                moreDoor = .diagnostics
                try? await Task.sleep(for: .milliseconds(400))
                showsProviders = true
            }


        }
    }

     
     
     
     
     
     
     
     
    @ViewBuilder
    private var utilitiesTab: some View {
        NavigationStack {
            ClashTVUtilitiesHub(opened: $utilitiesDoor)
                .navigationDestination(item: $utilitiesDoor) { door in
                    switch door {
                    case .nodes:
                        ClashTVNodesScreen(
                            state: state,
                            onPin: live ? { member, group in Task { await tunnel.pin(member: member, group: group) } } : nil,
                            onUnpin: live ? { group in Task { await tunnel.unpin(group: group.name) } } : nil,
                            onTestAll: live ? { group in Task { await tunnel.testAll(group: group) } } : nil,
                            onTest: live ? { member, group in Task { await tunnel.testOne(member: member, in: group) } } : nil,
                            onNeedMoreMembers: live ? { group in Task { await tunnel.loadMoreMembers(of: group) } } : nil
                        )
                    case .rules:
                        ClashTVRulesScreen(state: state,
                                           onNeedMoreRules: { category in Task { await tunnel.loadMoreRules(in: category) } })
                    case .connections:
                        ClashTVConnectionsScreen(state: state, opened: $connectionDoor)
                    }
                }
                 
                 
                 
                .navigationDestination(item: $connectionDoor) { door in
                    ClashTVConnectionDetailScreen(state: state, seed: door.connection,
                                                 observedAt: door.observedAt, generation: door.generation)
                }
        }
    }

     
    enum DoorPop: Equatable {
        case edit, subscriptionDetail, addSubscription, iCloudRestore, subscriptions, nodes, outboundMode
        case utilities, connectionDetail, more, providers
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func doorToClose(
        tab: Tab,
        editOpen: Bool, detailOpen: Bool, addOpen: Bool,
        subscriptionsOpen: Bool, nodesOpen: Bool, outboundOpen: Bool,
        utilitiesOpen: Bool, connectionOpen: Bool, moreOpen: Bool, providersOpen: Bool,
        restoreOpen: Bool = false
    ) -> DoorPop? {
        switch tab {
        case .home:
             
             
            if editOpen { return .edit }
            if detailOpen { return .subscriptionDetail }
            if addOpen { return .addSubscription }
            if restoreOpen { return .iCloudRestore }
            if subscriptionsOpen { return .subscriptions }
            if nodesOpen { return .nodes }
            if outboundOpen { return .outboundMode }
            return nil
        case .utilities:
             
             
            if connectionOpen { return .connectionDetail }
            return utilitiesOpen ? .utilities : nil
        case .more:
             
             
            if providersOpen { return .providers }
            return moreOpen ? .more : nil
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    enum DoorUnder: Equatable {
        case more(ClashTVMoreHub.Door)
        case utilities(ClashTVUtilitiesHub.Door)
    }

    static func doorUnder(_ door: DoorPop) -> DoorUnder? {
        switch door {
        case .providers: .more(.diagnostics)
        case .connectionDetail: .utilities(.connections)
        default: nil
        }
    }

     
     
    private func scanForDueUpdate() async {
        if let outcome = ClashTVAutoUpdate.takeBackgroundOutcome() {
            await tunnel.take(outcome, row: store.subscriptions.first { $0.id == outcome.subscriptionID },
                              current: store.current)
        }
        await ClashTVAutoUpdate.scanOnForegroundIfDue(store: store) { row in
             
             
            await tunnel.refresh(subscription: row, announces: false)
        }
        scheduleBackgroundRefresh()
    }

    private func scheduleBackgroundRefresh() {
        ClashTVAutoUpdate.schedule(earliest: ClashTVAutoUpdate.nextEligibility(rows: store.subscriptions, now: Date()))
    }

    private var pollingPresentation: ClashTVPollingPresentation {
        .init(page: Self.pollingPage(tab: tab, top: currentTabDoor,
                                    utilities: utilitiesDoor, more: moreDoor),
              active: scenePhase == .active)
    }

    static func pollingPage(tab: Tab, top: DoorPop?, utilities: ClashTVUtilitiesHub.Door?,
                            more: ClashTVMoreHub.Door?) -> ClashTVPollingPage {
        switch top {
        case .nodes: return .nodes
        case .outboundMode: return .outboundMode
        case .providers: return .providers
        case .connectionDetail: return .connectionDetail
        case .utilities:
            switch utilities {
            case .nodes: return .nodes
            case .connections: return .connections
            default: return .configuration
            }
        case .more: return more == .diagnostics ? .diagnostics : .configuration
        case nil: return tab == .home ? .home : .configuration
        default: return .configuration
        }
    }

     
     
    @ViewBuilder
    private var feedbackBanner: some View {
        if let entry = state.wrappedValue.feedback.current, entry.presentation.kind != .loading,
           !feedbackScreen.claims(entry.operation ?? "") {
             
             
             
             
             
            ClashTVFeedbackBanner(presentation: entry.presentation)
                .padding(.top, 60)
                .padding(.trailing, 90)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .ignoresSafeArea()
                .transition(.opacity)
                .id(entry.id)
        }
    }

    private var feedbackScreen: ClashTVFeedback.Screen {
        Self.feedbackScreen(tab: tab, homeTop: homePath.last, hasConfiguration: hasConfiguration,
                            utilities: utilitiesDoor, connectionOpen: connectionDoor != nil,
                            more: moreDoor, providersOpen: showsProviders)
    }

     
     
    static func feedbackScreen(tab: Tab, homeTop: HomeDoor?, hasConfiguration: Bool,
                               utilities: ClashTVUtilitiesHub.Door?, connectionOpen: Bool,
                               more: ClashTVMoreHub.Door?, providersOpen: Bool) -> ClashTVFeedback.Screen {
        switch tab {
        case .home:
            guard let homeTop else { return hasConfiguration ? .home : .welcome }
            switch homeTop {
            case .outboundMode: return .outboundMode
            case .nodes: return .nodes
            case .subscriptions: return .subscriptions
            case .iCloudRestore: return .iCloudRestore
            case .addSubscription: return .add
            case .subscription(let id): return .subscription(id)
            case .edit(let id): return .edit(id)
            case .rules(let id): return .rules(id)
            case .autoUpdate(let id): return .autoUpdate(id)
            case .script(let id): return .script(id)
            }
        case .utilities:
            if connectionOpen { return .connectionDetail }
            switch utilities {
            case .nodes: return .nodes
            case .connections: return .connections
            case let door?: return .utilitiesDoor(door)
            case nil: return .utilities
            }
        case .more:
            if providersOpen { return .providers }
            return more.map { .moreDoor($0) } ?? .more
        }
    }

    private var currentTabDoor: DoorPop? {
        Self.doorToClose(tab: tab,
                         editOpen: editDoor != nil, detailOpen: subscriptionDoor != nil,
                         addOpen: showsAddSubscription, subscriptionsOpen: showsSubscriptions,
                         nodesOpen: showsNodes, outboundOpen: showsOutboundMode,
                         utilitiesOpen: utilitiesDoor != nil, connectionOpen: connectionDoor != nil,
                         moreOpen: moreDoor != nil, providersOpen: showsProviders,
                         restoreOpen: showsICloudRestore)
    }

    private func closeTopmostDoor() {


        let closing = currentTabDoor
        switch closing {
        case .edit: editDoor = nil
        case .subscriptionDetail: subscriptionDoor = nil
        case .addSubscription: showsAddSubscription = false
        case .iCloudRestore: closeICloudRestore()
        case .subscriptions: showsSubscriptions = false
        case .nodes: showsNodes = false
        case .outboundMode: showsOutboundMode = false
        case .utilities: utilitiesDoor = nil
        case .connectionDetail: connectionDoor = nil
        case .providers: showsProviders = false
        case .more: moreDoor = nil
        case nil: break
        }
         
         
         
        if let top = closing, let under = Self.doorUnder(top) {
            switch under {
            case .more(let door): moreDoor = door
            case .utilities(let door): utilitiesDoor = door
            }
        }


    }

     
     
     
     
     
    private func runMatrixPreparation() async {


        await tunnel.prepare(subscription: store.current)


    }

     
     
    private func runMatrixProbes() async {


    }

}

extension ClashTVShell {
     

     
     
     
    static func homeProfileRow(
        for current: ClashTVSubscription?,
        fixture: ClashTVProductState
    ) -> (name: String, age: String) {
        guard let current else { return (fixture.profileName, fixture.profileAge) }
        return (current.title, ClashTVSubscriptionUpdatedWords.text(updatedAt: current.updatedAt))
    }
}

extension View {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func clashTVTitleSafe() -> some View {
        safeAreaPadding(EdgeInsets(top: 60, leading: 90, bottom: 60, trailing: 90))
    }


}
