import AppKit
import Combine
import ClashClientKit
import ClashClientUI
import ClashMacClient
import SwiftUI
import WidgetKit
import os

@MainActor
private final class ClashMacApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
         
         
        ClashNotificationCenterDelegate.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
         
         
         
         
        ClashMacLaunchGate.shared.applicationDidFinishLaunching()
         
         
        ClashMacDockIcon.apply(
            hidesIcon: UserDefaults.standard.bool(forKey: ClashMacDockIcon.key)
        )
         
        ModuleCertificateStore.followTheLanguage()
         
         
         
        let atLogin = ClashMacLoginItem.launchedAsLoginItem(NSAppleEventManager.shared().currentAppleEvent)
        if atLogin {
            ClashMacSceneModel.current?.comeUpQuietlyAtLogin()
        }
         
         
         
        DispatchQueue.main.async {
            guard !atLogin else { return }
            guard NSApplication.shared.windows.allSatisfy({
                $0.level != .normal || !$0.canBecomeKey
            }) else { return }
            ClashMacSceneModel.current?.openMainWindow(from: "launch")
        }


    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

     
     
     
     
     
    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard let vpn = ClashMacSceneModel.current?.vpn else { return .terminateNow }
        let quit = ClashMacQuit(
            isTunnelUp: { [weak vpn] in
                guard let vpn else { return false }
                return ClashMacQuit.tunnelIsUp(status: vpn.status)
            },
             
             
             
             
             
             
            stop: { [weak vpn] in
                vpn?.recordReaderWord(.stop)
                await vpn?.stop()
            },
            allowTermination: { sender.reply(toApplicationShouldTerminate: true) }
        )
        pendingQuit = quit
         
         
        let reason = ClashMacQuit.quitReason(
            NSAppleEventManager.shared().currentAppleEvent?
                .attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))
        )
        let occasion = ClashMacQuit.occasion(
            quitReason: reason, requested: ClashMacQuit.nextTermination
        )
         
        if occasion == .systemEndingSession { vpn.sessionIsEnding() }
        return quit.reply(for: occasion)
    }

     
    private var pendingQuit: ClashMacQuit?

     
     
     
     
     
     
     
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        guard !hasVisibleWindows else { return true }
        ClashMacSceneModel.current?.openMainWindow(from: "dock-reopen")
        return true
    }

     
     
     
     
     
    func applicationDidUpdate(_ notification: Notification) {
        ClashMacDockIcon.apply(
            hidesIcon: UserDefaults.standard.bool(forKey: ClashMacDockIcon.key)
        )
    }

     
     
     
     
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let model = ClashMacSceneModel.current else { return nil }
        let locale = model.preferences.language.locale
        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(
                title: ClashCopy.string(
                    model.latestSnapshot.connection.phase.statusTitle,
                    locale: locale
                ),
                action: nil,
                keyEquivalent: ""
            )
        )
        if let intent = model.latestSnapshot.connection.primaryIntent {
            let action = NSMenuItem(
                title: ClashCopy.string(intent.toolbarTitle, locale: locale),
                action: #selector(performDockPrimaryAction),
                keyEquivalent: ""
            )
            action.target = self
            menu.addItem(action)
        }
        return menu
    }

    @objc private func performDockPrimaryAction() {
        ClashMacSceneModel.current?.performPrimaryActionFromMenu()
    }
}

private struct ClashMacUIReviewEnvironment: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {

        content

    }
}

@main
struct ClashMacApp: App {
    @NSApplicationDelegateAdaptor(ClashMacApplicationDelegate.self)
    private var applicationDelegate
    @StateObject private var model = ClashMacSceneModel()
     
     
     
     
     
    @State private var throughputUnit = ClashThroughputUnit.stored(in: GlobalConfig.appGroupDefaults)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase

    init() {
         
         
         
         
        ClashMacExceptionRecorder.install()
         
         
        ClashPerfBootstrap.install()


         
         
         
         
         
        ClashClientUI.ClashSymbol.platformName = { $0.name }
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        DispatchQueue.global(qos: .utility).async {
            _ = ThirdPartyLicenseInventory.shared.modules.count
        }
         
         
         
         
         
        ProxyNodeEditorMacOverrides.entryPage = { draft, path, field, title in
            AnyView(ProxyNodeMacEntryPage(draft: draft, path: path, field: field, title: title))
        }
        ProxyNodeEditorMacOverrides.proxyTypeRow = { draft, hidesNonServerTypes, catalog, pendingType in
            AnyView(
                ProxyTypeMacRow(
                    draft: draft,
                    hidesNonServerTypes: hidesNonServerTypes,
                    catalog: catalog,
                    pendingType: pendingType
                )
            )
        }
         
         
         
         
        ProxyNodeEditorMacOverrides.editorContainer = { content in
            AnyView(ProxyNodeMacEditorContainer(content: content))
        }
    }

    var body: some Scene {
         
         
         
         
         
         
         
         
         
         
         
         
        let _: Void = model.rememberWindowOpener(openWindow)
        Window("Clash", id: "main") {
            ClashMacRootView(
                snapshot: model.snapshot,
                actions: model.actions,
                navigationRequest: $model.navigationRequest,
                secondaryContent: { destination in
                     
                     
                     
                     
                     
                     
                     
                     
                    AnyView(
                        ClashDeferredPageContent {
                            model.secondaryContent(destination)
                        } placeholder: {
                            ClashMacPlatformPresentation.palette.canvas
                                .ignoresSafeArea()
                        }
                        .id(destination)
                    )
                },
                detailOverlay: { root in
                    model.pooledDetailOverlay(for: root)
                },
                moreAttentionAction: { actionID in
                    model.performLegacySettingsAttention(actionID: actionID)
                }
            )
             
             
             
             
            .modifier(ClashMacCentreWindowSheets(model: model))
            .environment(\.clashShellLayout, .regularSidebar)
            .environment(\.clashThroughputUnit, throughputUnit)
            .environment(\.clashFeedback, model.feedback)
             
             
             
             
             
             
            .environment(\.clashMacEditorSyntax, model.editorSyntax)
            .environment(\.externalControllerCore, ExternalControllerCore.mac(vpn: model.vpn, profiles: model.profiles))
             
             
             
            .environment(\.clashDetailTopAccessory, AnyView(ClashMacFeedbackBar(center: model.feedback)))
            .onReceive(NotificationCenter.default.publisher(for: ClashThroughputUnit.didChangeNotification)) { _ in
                throughputUnit = ClashThroughputUnit.stored(in: GlobalConfig.appGroupDefaults)
            }
             
             
            .modifier(ClashMacLiveResizeReporting())
            .background(
                ClashMacWindowReader { model.mainWindowDidAttach($0) }
                    .frame(width: 0, height: 0)
            )
             
             
             
            .environment(\.clashBackupDataScope, model.backupScope)
            .environment(\.clashTrafficFeed, model.trafficFeed)
            .modifier(ClashMacUIReviewEnvironment())
            .clashMacWindowChrome()
            .onAppear {
                model.mainWindowContentDidAppear()
            }
            .task {
                await model.prepare()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task {
                    await model.refreshVPNInstallation()
                     
                     
                     
                    await model.takeModesChosenOnCardsNow()
                     
                     
                     
                    model.handlePendingSystemAction()
                }
            }
             
             
            .onReceive(NotificationCenter.default.publisher(for: .clashSystemActionQueued)) { _ in
                model.handlePendingSystemAction()
            }
            .onOpenURL { url in


                model.open(url)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: ProviderFirstLoadRetry.didRefreshNotification
                )
            ) { _ in
                model.applyFirstLoadRefreshes()
            }
             
             
            .onReceive(
                NotificationCenter.default.publisher(
                    for: ProviderDownloadActivity.didChangeNotification
                )
            ) { _ in
                model.providerDownloadActivityChanged()
            }
            .alert(
                Text(clash: .copy(
                    model.profileImports.pendingConfirmation
                        .map { ClashMacInstallLinkPrompt(pending: $0).title }
                        ?? "Add this profile URL?"
                )),
                isPresented: Binding(
                     
                     
                     
                     
                     
                    get: {
                        model.profileImports.pendingConfirmation != nil
                            && scenePhase == .active
                    },
                     
                     
                     
                     
                     
                     
                    set: { presented in
                        if !presented,
                           let pending = model.profileImports.pendingConfirmation {
                            ClashLogStore.shared.append(
                                "install link alert torn down (state kept)  \(pending)",
                                stream: .app, level: .warning)
                        }
                    }
                )
            ) {
                Button("Add") {
                    model.profileImports.acceptPendingConfirmation()
                    model.navigationRequest = .profiles
                }
                Button("Don't Add", role: .cancel) {
                    model.profileImports.declinePendingConfirmation()
                }
            } message: {
                if let pending = model.profileImports.pendingConfirmation {
                    let prompt = ClashMacInstallLinkPrompt(pending: pending, rules: model.profileImports.pendingRules)
                     
                     
                     
                     
                    if let line = prompt.ruleLine {
                        Text(clash: .copy(prompt.lead)) + Text(clash: line) + Text(verbatim: "\n\n")
                            + Text(clash: .verbatim(prompt.link))
                    } else {
                        Text(clash: .copy(prompt.lead)) + Text(clash: .verbatim(prompt.link))
                    }
                }
            }
             
             
             
             
            .modifier(ProfileHandoffRefusalAlert(router: model.profileImports, host: nil, waits: false))
            .modifier(
                ClashMacPreferencesEnvironment(
                    preferences: model.preferences,
                    presentsRestartPrompt: true
                )
            )
        }
        .defaultSize(width: 1040, height: 720)
         
         
         
        WindowGroup("Runtime Configuration", id: "runtime-preview", for: ClashMacRuntimePreviewRequest.self) { $request in
            if let request, let profile = model.profiles.profiles.first(where: { $0.id == request.profileID }) {
                 
                 
                 
                 
                 
                ClashMacRuntimePreviewHost(profiles: model.profiles, profileID: profile.id, label: profile.label)
                    .frame(minWidth: 640, minHeight: 480)
            }
        }
        .defaultSize(width: 920, height: 720)
        .commandsRemoved()
        WindowGroup("Script", id: "script-editor", for: ClashMacScriptEditorRequest.self) { $request in
            if let request, let script = ScriptLibrary.load().first(where: { $0.id == request.scriptID }) {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                ClashWindowDepartureHost {
                    ClashMacWindowFeedbackHost {
                        ScriptEditorView(script: script, rename: { name in
                            try ScriptLibrary.rename(id: script.id, to: name)
                        }) { ScriptLibrary.upsert($0) }
                    }
                } windowGuard: { controller in
                    ClashMacWindowCloseGuard(controller: controller)
                }
                .frame(minWidth: 640, minHeight: 480)
            }
        }
        .defaultSize(width: 920, height: 720)
        .commandsRemoved()
        WindowGroup("Edit Source", id: "source-editor", for: ClashMacSourceEditorRequest.self) { $request in
            if let request {
                ClashMacSourceEditorWindow(request: request, profiles: model.profiles)
            }
        }
        .defaultSize(width: 920, height: 720)
         
         
        .commandsRemoved()
        .windowResizability(.contentMinSize)
        .commands {
            ClashMacProductCommands()
        }

    }
}

 
enum ClashMacUndoAnswer: Equatable {
    case restored
     
    case superseded(String)
     
    case failed(String)
}

 
@MainActor
final class ClashMacUndoToken: Hashable {
    nonisolated static func == (lhs: ClashMacUndoToken, rhs: ClashMacUndoToken) -> Bool { lhs === rhs }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    let label: String
    let operation: String
    let undo: @MainActor () async -> ClashMacUndoAnswer
    var used = false
    var resultID: Int?

    init(label: String, operation: String, undo: @escaping @MainActor () async -> ClashMacUndoAnswer) {
        self.label = label
        self.operation = operation
        self.undo = undo
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ClashMacDockIcon {
     
    static let key = "clash.mac.hide-dock-icon"

     
     
     
     
     
    static func policy(
        hidesIcon: Bool,
        hasVisibleWindow: Bool
    ) -> NSApplication.ActivationPolicy {
        hidesIcon && !hasVisibleWindow ? .accessory : .regular
    }

    @MainActor
    static func apply(hidesIcon: Bool, application: NSApplication = .shared) {
        let visible = application.windows.contains {
            $0.isVisible && $0.level == .normal && $0.canBecomeKey
        }
        let wanted = policy(hidesIcon: hidesIcon, hasVisibleWindow: visible)
        guard application.activationPolicy() != wanted else { return }
        application.setActivationPolicy(wanted)
         
         
        if wanted == .regular {
            application.activate(ignoringOtherApps: true)
        }
    }
}

 
 
 
 
final class ClashMacRunResult<Run>: @unchecked Sendable {
    var value: Run?
}

 
 
struct ClashMacDuplicateCustomRule: ClashAuthoredError {
    var displayText: ClashDisplayText { .copy("This rule is already in the list.") }
}

struct ClashMacCollectionTakeFailure: LocalizedError {
    let lines: [String]
    var errorDescription: String? { lines.joined(separator: "\n") }
}

enum ClashMacMenuBarSpeed {
     
     
    static let key = "clash.mac.menu-bar-speed"

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func rate(_ bytesPerSecond: Int64, unit: ClashThroughputUnit) -> String {
        let bytes = Double(max(bytesPerSecond, 0))
        switch unit {
        case .bits:
            return scaled(bytes * 8, step: 1_000, units: words(unit))
        case .bytes:
            return scaled(bytes, step: 1_024, units: words(unit))
        }
    }

    private static func words(_ unit: ClashThroughputUnit) -> [String] {
        switch unit {
        case .bits: ["Kbps", "Mbps", "Gbps"]
        case .bytes: ["KB/s", "MB/s", "GB/s"]
        }
    }

    private static func scaled(_ value: Double, step: Double, units: [String]) -> String {
        var amount = value / step
        var index = 0
        while amount >= 999.95, index < units.count - 1 {
            amount /= step
            index += 1
        }
        return String(format: "%.1f ", amount) + units[index]
    }

     
     
     
     
     
     
     
     
    static func widestLines(in unit: ClashThroughputUnit) -> [String] {
        words(unit).map { "999.9 \($0) ↑" }
    }

     
     
     
    static func units(of lines: [String]) -> [ClashThroughputUnit] {
        ClashThroughputUnit.allCases.filter { unit in
            words(unit).contains { word in lines.contains { $0.contains(" \(word) ") } }
        }
    }

    static func up(_ bytesPerSecond: Int64, unit: ClashThroughputUnit) -> String {
        rate(bytesPerSecond, unit: unit) + " ↑"
    }

    static func down(_ bytesPerSecond: Int64, unit: ClashThroughputUnit) -> String {
        rate(bytesPerSecond, unit: unit) + " ↓"
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @MainActor
     
     
     
     
     
     
    static func menuBarImage(upLine: String, downLine: String, catAlpha: CGFloat) -> NSImage? {
        guard !upLine.isEmpty, !downLine.isEmpty,
              let cat = NSImage(named: ClashMacAsset.menuBarTemplate.rawValue)
        else { return nil }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
             
             
            .foregroundColor: NSColor.black,
        ]
        let upLine = upLine as NSString
        let downLine = downLine as NSString
        let upSize = upLine.size(withAttributes: attributes)
        let downSize = downLine.size(withAttributes: attributes)

         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        let drawn = units(of: [upLine as String, downLine as String])
        let reserve = (drawn.isEmpty ? ClashThroughputUnit.allCases : drawn)
            .flatMap(widestLines(in:))
            .map { ($0 as NSString).size(withAttributes: attributes).width }
            .max() ?? 0
        let column = ceil(max(reserve, max(upSize.width, downSize.width)))
        let line = ceil(max(upSize.height, downSize.height))
         
         
         
        let height = line * 2 - 2
         
         
        let cat18: CGFloat = 18
        let gap: CGFloat = 3
        let size = CGSize(width: cat18 + gap + column, height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            cat.draw(
                in: CGRect(
                    x: 0,
                    y: (height - cat18) / 2,
                    width: cat18,
                    height: cat18
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: catAlpha
            )
             
             
             
             
             
            upLine.draw(
                at: CGPoint(
                    x: cat18 + gap + column - upSize.width,
                    y: height - line
                ),
                withAttributes: attributes
            )
            downLine.draw(
                at: CGPoint(x: cat18 + gap + column - downSize.width, y: 0),
                withAttributes: attributes
            )
            return true
        }
        image.isTemplate = true
        return image
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
 
 
final class ClashMacMenuBarTrafficFeed: ObservableObject {
    @Published private(set) var upLine = ""
    @Published private(set) var downLine = ""

     
     
     
     
     
     
     
     
     
     
    private var trackingDepth = 0
    private var menuIsTracking: Bool { trackingDepth > 0 }
     
    private var thaw: DispatchWorkItem?
    private var pending: (up: String, down: String)?
    private var subscriptions: Set<AnyCancellable> = []
     
     
     
    private(set) var unit: ClashThroughputUnit
    private var lastRates: (up: Int64, down: Int64)

    init(command: ClashCommandClient, defaults: UserDefaults?) {
        unit = ClashThroughputUnit.stored(in: defaults)
        lastRates = (command.traffic.upload, command.traffic.download)
        upLine = ClashMacMenuBarSpeed.up(command.traffic.upload, unit: unit)
        downLine = ClashMacMenuBarSpeed.down(command.traffic.download, unit: unit)
        command.$traffic
            .sink { [weak self] traffic in
                guard let self else { return }
                self.lastRates = (traffic.upload, traffic.download)
                self.offer(
                    up: ClashMacMenuBarSpeed.up(traffic.upload, unit: self.unit),
                    down: ClashMacMenuBarSpeed.down(traffic.download, unit: self.unit)
                )
            }
            .store(in: &subscriptions)
        let center = NotificationCenter.default
        center.publisher(for: ClashThroughputUnit.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.unit = ClashThroughputUnit.stored(in: defaults)
                self.offer(
                    up: ClashMacMenuBarSpeed.up(self.lastRates.up, unit: self.unit),
                    down: ClashMacMenuBarSpeed.down(self.lastRates.down, unit: self.unit)
                )
            }
            .store(in: &subscriptions)
        center.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                 
                 
                self.thaw?.cancel()
                self.thaw = nil
                self.trackingDepth += 1
            }
            .store(in: &subscriptions)
        center.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.trackingDepth = max(0, self.trackingDepth - 1)
                guard self.trackingDepth == 0 else { return }
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.trackingDepth == 0 else { return }
                    self.thaw = nil
                    if let pending = self.pending {
                        self.pending = nil
                        self.upLine = pending.up
                        self.downLine = pending.down
                    }
                }
                self.thaw = work
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.25, execute: work
                )
                return
            }
            .store(in: &subscriptions)
    }

    private func offer(up: String, down: String) {
        guard up != upLine || down != downLine else { return }
        if menuIsTracking {
            pending = (up, down)
        } else {
            upLine = up
            downLine = down
        }
    }

     
     
     
     
     
     
    func tunnelDidStop() {
        thaw?.cancel()
        thaw = nil
        pending = nil
        lastRates = (0, 0)
        upLine = ClashMacMenuBarSpeed.up(0, unit: unit)
        downLine = ClashMacMenuBarSpeed.down(0, unit: unit)
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
private struct ClashMacCentreAddButton: View {
    @ObservedObject var model: ClashMacSceneModel

    var body: some View {
        switch model.configurationCenterSegment {
        case .configurations:
            Button {
                model.showsConfigurationWizard = true
            } label: {
                Label {
                    Text(clash: .copy("Add Profile"))
                } icon: {
                    Image(systemName: ClashSymbol.plus.name)
                }
            }
            .help(Text(clash: .copy("Add Profile")))
            .accessibilityIdentifier("profile-center.add")
        case .nodes:
            Button {
                model.configurationCenterImport = ClashMacImportRequest(purpose: .nodes, tab: .nodes)
            } label: {
                Label {
                    Text(clash: .copy("Add Nodes"))
                } icon: {
                    Image(systemName: ClashSymbol.plus.name)
                }
            }
            .help(Text(clash: .copy("Add Nodes")))
            .accessibilityIdentifier("configuration-center.nodes.add")
        case .rules:
            Button {
                model.configurationCenterImport = ClashMacImportRequest(purpose: .rules, tab: .manual)
            } label: {
                Label {
                    Text(clash: .copy("Add Rules"))
                } icon: {
                    Image(systemName: ClashSymbol.plus.name)
                }
            }
            .help(Text(clash: .copy("Add Rules")))
            .accessibilityIdentifier("configuration-center.rules.add")
        }
    }
}

 
 
 
 
 
 
 
 
 
@MainActor
private struct ClashMacCentreUpdateAllButton: View {
    @ObservedObject var library: ClashMacConfigurationLibraryModel
    let profiles: ProfilesViewModel
     
    @State private var linkedProfiles: Set<String>

    init(library: ClashMacConfigurationLibraryModel, profiles: ProfilesViewModel) {
        self.library = library
        self.profiles = profiles
        _linkedProfiles = State(initialValue: Self.linked(profiles.profiles))
    }

     
     
     
    private var hasLegacyProfiles: Bool {
        !linkedProfiles.subtracting(library.snapshot.recipes.map(\.id)).isEmpty
    }

    var body: some View {
        Group {
            if library.hasLinkedContent(legacyProfiles: hasLegacyProfiles) {
                Button {
                    Task { await library.updateEverything() }
                } label: {
                    Label {
                        Text(clash: .copy("Update All"))
                    } icon: {
                        Image(systemName: ClashSymbol.arrowTriangle2Circlepath.name)
                    }
                }
                .disabled(library.isUpdatingAll || library.isBusy)
                .help(Text(clash: .copy("Update All")))
                .accessibilityIdentifier("profile-center.sync-all")
            }
        }
        .onReceive(profiles.$profiles.map(Self.linked).removeDuplicates()) { linkedProfiles = $0 }
    }

    nonisolated private static func linked(_ profiles: [Profile]) -> Set<String> {
        Set(profiles.compactMap { profile in
            if case .url = profile.source { return profile.id }
            return nil
        })
    }
}

private struct ClashMacProxiesGhostChrome: View, Equatable {
    let model: ClashMacSceneModel
    @ObservedObject var channels: ClashRegularRootChannels
     
     
     
     
     
     
     
     
    @State private var preferences: ClashProxiesDisplayPreferences

    init(model: ClashMacSceneModel) {
        self.model = model
        self.channels = model.proxiesChannels
        _preferences = State(
            initialValue: ClashProxiesDisplayPreferences.uiTestOverride()
                ?? ClashProxiesDisplayPreferences.load()
        )
    }

    static func == (
        lhs: ClashMacProxiesGhostChrome,
        rhs: ClashMacProxiesGhostChrome
    ) -> Bool {
        lhs.model === rhs.model
    }

    var body: some View {
        Color.clear
            .searchable(
                text: $channels.searchText,
                prompt: Text("Search proxies")
            )
            .clashToolbarUnlessInPanel {
                ClashProxiesToolbar(
                    showsDismissControl: false,
                    hasExpandedGroups: model.proxiesHasExpandedGroupsNow,
                     
                     
                     
                     
                     
                     
                    canRefreshCatalog: true,
                    refreshDisabled: model.isTestingLatencyNow,
                    preferences: $preferences,
                    onDismiss: {},
                    onToggleFold: { [weak model] in
                        model?.proxiesChannels.foldCommand += 1
                    },
                    onRefresh: { [weak model] in
                        guard let model else { return }
                        Task { await model.refreshNodes() }
                    },
                    onShowDisplayOptions: {},
                    icon: { ClashSymbolImage(symbol: $0) }
                )
            }
            .onChange(of: preferences) { [weak model] value in
                 
                 
                 
                 
                model?.applyProxiesDisplayPreferences(value)
            }
    }
}

 
 
 
 
 
 
private struct ClashMacRulesGhostChrome: View, Equatable {
    let model: ClashMacSceneModel
    @ObservedObject var channels: ClashRegularRootChannels

    init(model: ClashMacSceneModel) {
        self.model = model
        self.channels = model.rulesChannels
    }

    static func == (lhs: ClashMacRulesGhostChrome, rhs: ClashMacRulesGhostChrome) -> Bool {
        lhs.model === rhs.model
    }

    var body: some View {
        Color.clear
            .searchable(text: $channels.searchText, prompt: Text("Search rules"))
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .primaryAction) {
                    ClashMacRulesEditButton(model: model, profiles: model.profiles)
                }
            }
    }
}

 
 
private struct ClashMacRulesEditButton: View {
    let model: ClashMacSceneModel
    @ObservedObject var profiles: ProfilesViewModel
    @Environment(\.clashPushRoute) private var pushRoute
     
     
     
     
    @State private var keepsRules = false

    var body: some View {
         
         
        if let pushRoute, model.hasConfigurationInUse {
            Button {
                Task { @MainActor in
                     
                     
                     
                     
                    await model.readConfigurationLibraryIfUnread()
                    guard let chapter = model.rulesChapterOfCurrentConfiguration() else { return }
                     
                    let token = UUID()
                    ClashViewRouteRegistry.set(token, ownership: .oneShot, onReturn: {}) { chapter() }
                    pushRoute(ClashViewRoute(id: token))
                }
            } label: {
                Text(clash: .copy("Edit"))
            }
            .disabled(keepsRules)
            .help(Text(clash: keepsRules ? ClashMacKeptRulesList.note : .copy("Edit")))
            .accessibilityIdentifier("rules.overview.edit")
            .task(id: profiles.activeProfileID) { keepsRules = await model.currentConfigurationKeepsRulesInOriginal() }
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
enum ClashMacActivityLensHandoff {
    static func binding(
        _ lens: ClashActivityLens,
        write: @escaping (ClashActivityLens) -> Void
    ) -> Binding<ClashActivityLens> {
        Binding(get: { lens }, set: write)
    }
}

 
 
 
 
 
 
 
 
 
 
enum ClashMacMainWindowClock {
    @MainActor
    static func follow(
        _ window: NSWindow,
        isMain: @escaping (NSWindow) -> Bool,
        isKey: @escaping (NSWindow) -> Bool = { $0.isKeyWindow },
        pause: @escaping () -> Void,
        resume: @escaping () -> Void
    ) -> [AnyCancellable] {
        DispatchQueue.main.async { [weak window] in
            guard let window, isMain(window) else { return }
            if isKey(window) { resume() } else { pause() }
        }
        return [
            NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification, object: window)
                .receive(on: DispatchQueue.main)
                .sink { _ in resume() },
            NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: window)
                .receive(on: DispatchQueue.main)
                .sink { _ in pause() },
        ]
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class ClashMacSceneRefresh {
    private let refresh: (_ onlyIfChanged: Bool) -> Void
    private var scheduled = false
    private var mustPublish = false

    init(refresh: @escaping (_ onlyIfChanged: Bool) -> Void) {
        self.refresh = refresh
    }

    func ask(drawnOnlyThroughSnapshot: Bool = false) {
        if !drawnOnlyThroughSnapshot { mustPublish = true }
        guard !scheduled else { return }
        scheduled = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.scheduled = false
            let onlyIfChanged = !self.mustPublish
            self.mustPublish = false
            self.refresh(onlyIfChanged)
        }
    }
}

extension AppleClientSnapshot {
     
     
     
     
     
     
    func drawsTheSame(as shown: AppleClientSnapshot) -> Bool {
        guard home.traffic.coreStartedAtUnixSeconds == shown.home.traffic.coreStartedAtUnixSeconds
        else { return false }
        return AppleClientSnapshot(
            revision: shown.revision,
            selectedProfile: selectedProfile,
            connection: connection,
            home: home.carrying(traffic: shown.home.traffic),
            profiles: profiles,
            proxies: proxies,
            activity: activity,
            rules: rules,
            dns: dns,
            utilities: utilities,
            more: more,
            capabilities: capabilities,
            activeOperations: activeOperations,
            failure: failure
        ) == shown
    }
}

extension AppleClientHomeSnapshot {
    func carrying(traffic: AppleClientTrafficSnapshot) -> AppleClientHomeSnapshot {
        AppleClientHomeSnapshot(
            routing: routing,
            traffic: traffic,
            proxyGroupCount: proxyGroupCount,
            proxyCount: proxyCount,
            ruleCount: ruleCount,
            connection: connection,
            initialSection: initialSection,
            favoriteCards: favoriteCards,
            trafficScope: trafficScope,
            proxies: proxies,
            rules: rules,
            egress: egress,
            lanAddress: lanAddress,
            isProfileActionInFlight: isProfileActionInFlight,
            selectedProfileIsSystemFallback: selectedProfileIsSystemFallback,
            profilesLoaded: profilesLoaded,
            profilesUnavailableReason: profilesUnavailableReason
        )
    }
}

 
enum ClashMacChooseNodePage {
     
     
    static func switchedAway(to root: ClashRootDestination?, pending: ClashMacSecondaryDestination?) -> Bool {
        guard let root, root != .proxies else { return false }
        if case .proxies? = pending { return false }
        return true
    }
}

@MainActor
private final class ClashMacSceneModel: ObservableObject {
     
     
     
     
     
     
     
     
    private var automaticRefreshDriver: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
     
    private lazy var refreshPowerGate = ClashMacRefreshPowerGate {
        await BackgroundRefresh.scanOnForegroundIfDue()
    }
     
     
     
    private var cardModeWatcher: ClashWidgetModeChoiceWatcher?
     
     
     
    private var modulesListenerKeys = KernelLANShareOverride()

    @Published private(set) var snapshot: AppleClientSnapshot = .empty
     
     
     
     
     
    let trafficFeed = ClashTrafficFeed(traffic: .zero)

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private var menuTrackingDepth = 0
    private var snapshotThaw: DispatchWorkItem?
     
     
     
    private lazy var snapshotGate = ClashMacSnapshotGate<AppleClientSnapshot> {
        [weak self] value in self?.snapshot = value
    }
     
     
     
    private(set) var productIsVisible = true
    private var visibilityObserver: ClashMacProductVisibilityObserver?
     
     
    private var ownerService: ClashMacOwnerService?
     
     
    private var appDataUnreadable = false
    private var menuGate: Set<AnyCancellable> = []

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private lazy var sceneRefresh = ClashMacSceneRefresh { [weak self] onlyIfChanged in
        self?.refreshSnapshot(onlyIfChanged: onlyIfChanged)
    }

    private func publish(_ value: AppleClientSnapshot) {
         
         
         
        let wasHolding = snapshotGate.held != nil
        snapshotGate.send(value)
         
         
        if !wasHolding, snapshotGate.held != nil, !snapshotGate.isVisible {
            Self.traceWindow("snapshot.gate hold revision=\(value.revision) profile=\(value.selectedProfile?.id.rawValue ?? "none") visible=\(snapshotGate.isVisible) menuTracking=\(snapshotGate.isMenuTracking) windowShows=\(snapshot.revision)")
        }
        let profileID = value.selectedProfile?.id.rawValue
        if profileID != lastTracedProfileID {
            Self.traceWindow("snapshot.profile \(lastTracedProfileID ?? "none")->\(profileID ?? "none") revision=\(value.revision) profiles=\(profiles.profiles.count) active=\(profiles.activeProfileID ?? "none")")
            lastTracedProfileID = profileID
        }
    }

     
     
    private var lastTracedProfileID: String?

     
     
     
     
    private static func traceWindow(_ line: String) {
        ClashMacDebugLog.note(line)
        ClashLogStore.shared.append(line, stream: .app)
    }

     
     
    fileprivate var latestSnapshot: AppleClientSnapshot {
        snapshotGate.latest ?? snapshot
    }

     
     
     
    func syncStatusDemand() {
        command.setStatusDemand(
            productIsVisible || UserDefaults.standard.bool(forKey: ClashMacMenuBarSpeed.key)
        )
    }

     
     
    func mainWindowContentDidAppear() {
        visibilityObserver?.windowContentDidAppear()
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func syncConnectionsChannelState(status: String) {
        connections.setChannelState(
            tunnelIsUp: ["connected", "connecting", "reasserting"].contains(status),
            channelFailed: command.channelAttachFailed
        )
    }

    private func syncConnections(commandConnected: Bool) {
        syncConnectionsChannelState(status: vpn.status)
         
         
        command.connectionActivityDemanded = productIsVisible
        if productIsVisible && commandConnected {
            connections.sync(true)
        } else if ["connected", "connecting", "reasserting"].contains(vpn.status) {
            connections.pause()
        } else {
            connections.sync(false)
        }
    }

    func productVisibilityDidChange(_ visible: Bool) {
        productIsVisible = visible
        syncHealthCheckFollow()
        syncStatusDemand()
        syncConnections(commandConnected: command.isConnected)
        if visible {
            trafficFeed.traffic = trafficSnapshot(command.traffic)
        }
        let held = snapshotGate.held
        snapshotGate.setVisible(visible)
        if let held, snapshotGate.held == nil {
            Self.traceWindow("snapshot.gate flush revision=\(held.revision) profile=\(held.selectedProfile?.id.rawValue ?? "none")")
        }
    }

     
     
     
     
     
     
     
    private func observeProxiesPageSeen() {
        let gate = proxiesChannels.latencyPulseGate
        gate.opened.merge(with: gate.closed)
            .sink { [weak self] in self?.syncHealthCheckFollow() }
            .store(in: &proxiesPageSeen)
        syncHealthCheckFollow()
    }

    private func syncHealthCheckFollow() {
        nodes.setHealthCheckFollowPausedWhileUnseen(!(productIsVisible && proxiesChannels.latencyPulseGate.isOpen))
    }

    private var proxiesPageSeen: Set<AnyCancellable> = []

    private func observeMenuTracking() {
        let center = NotificationCenter.default
        center.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.snapshotThaw?.cancel()
                self.snapshotThaw = nil
                self.menuTrackingDepth += 1
                if !self.snapshotGate.isMenuTracking {
                    Self.traceWindow("snapshot.gate menuTracking=true depth=\(self.menuTrackingDepth)")
                }
                self.snapshotGate.setMenuTracking(true)
            }
            .store(in: &menuGate)
        center.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.menuTrackingDepth = max(0, self.menuTrackingDepth - 1)
                guard self.menuTrackingDepth == 0 else { return }
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.menuTrackingDepth == 0 else { return }
                    self.snapshotThaw = nil
                    Self.traceWindow("snapshot.gate menuTracking=false held=\(self.snapshotGate.held?.revision.description ?? "none")")
                    self.snapshotGate.setMenuTracking(false)
                }
                self.snapshotThaw = work
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.25, execute: work
                )
            }
            .store(in: &menuGate)
    }
     

     
    @Published var configurationCenterSegment: ClashMacConfigurationCenterSegment = .configurations
     
     
     
     
     
    var configurationCenterDeleteHandler: ((ClashMacConfigurationCenterItem) -> Void)?
    private var configurationCenterDeleteAsks: AnyCancellable?

     
     
     
     
     
    func armDeleteConfirmation() {
        guard configurationCenterDeleteAsks == nil else { return }
        configurationCenterDeleteAsks = $configurationCenterPendingDelete
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] item in self?.presentDeleteConfirmation(item) }
    }

    private func presentDeleteConfirmation(_ item: ClashMacConfigurationCenterItem) {
         
         
         
        switch item {
        case .source, .scheme:
             
            guard configurationLibrary.deletesUndoably else { break }
            configurationCenterPendingDelete = nil
            configurationCenterDeleteHandler?(item)
            return
        default: break
        }
        let locale = preferences.language.locale
        let record: ConfigurationSourceRecord? = {
            guard case .source(let id) = item else { return nil }
            return configurationLibrary.snapshot.sources.first { $0.id == id }
        }()
        let isChain = record?.nodeChain != nil
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = ClashMacDeleteCopy.title(item, isChain: isChain, locale: locale)
        alert.informativeText = ClashMacDeleteCopy.message(item, isChain: isChain,
                                                           suppliesNodes: record?.suppliesNodes == true, locale: locale)
        let delete = alert.addButton(withTitle: ClashCopy.string("Delete", locale: locale))
        delete.hasDestructiveAction = true
        delete.setAccessibilityIdentifier("configuration-center.delete.confirm")
        let cancel = alert.addButton(withTitle: ClashCopy.string("Cancel", locale: locale))
        cancel.keyEquivalent = "\u{1b}"
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            self?.configurationCenterPendingDelete = nil
            if response == .alertFirstButtonReturn { self?.configurationCenterDeleteHandler?(item) }
        }
        if let window = NSApplication.shared.windows.first(where: { $0.level == .normal && $0.canBecomeKey && $0.isVisible }) {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }

    lazy var configurationLibrary: ClashMacConfigurationLibraryModel = {
        let model = ClashMacConfigurationLibraryModel(actions: configurationLibraryActions())
         
         
        configurationLibraryLocale = preferences.$language.sink { [weak model] language in model?.locale = language.locale }
         
         
         
         
         
         
        configurationLibraryFollowsProfiles = profiles.$profiles
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak model] _ in Task { @MainActor in await model?.reload() } }
         
         
         
         
         
         
         
         
        let center = NotificationCenter.default
        configurationLibraryFollowsRuntime = Publishers.MergeMany(
            center.publisher(for: ProfileStore.didChangeNotification).map { _ in () }.eraseToAnyPublisher(),
            center.publisher(for: .clashActiveConfigurationRepublished).map { _ in () }.eraseToAnyPublisher(),
            center.publisher(for: ProviderFirstLoadRetry.didRefreshNotification).map { _ in () }.eraseToAnyPublisher(),
            profiles.$activeProfileID.dropFirst().removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            ProviderRefreshStateWatcher.changes()
        )
        .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
        .sink { [weak model] in Task { @MainActor in model?.reloadCollections() } }
        return model
    }()
    private var configurationLibraryFollowsProfiles: AnyCancellable?
    private var configurationLibraryFollowsRuntime: AnyCancellable?

    var configurationCenterSegmentBinding: Binding<ClashMacConfigurationCenterSegment> {
        Binding(get: { self.configurationCenterSegment }, set: { self.configurationCenterSegment = $0 })
    }

     
    @Published var showsConfigurationWizard = false
     
     
     
    @Published var configurationCenterWindowSheet: ClashMacCentreWindowSheet?

     
     
    @Published var configurationCenterPendingDelete: ClashMacConfigurationCenterItem?
     
     
     
     
     
     
    private struct QuickAddKey: Hashable {
        let target: ProfileQuickAddController.Target
        let profileID: String?
    }
    private var quickAddControllers: [QuickAddKey: ProfileQuickAddController] = [:]
    @Published var configurationCenterImport: ClashMacImportRequest?
     
     
     
     
     
     
    var configurationCenterLatestList: ClashProfilesListPresentation?
    @Published var configurationCenterEditingScheme: ClashMacLibrarySelection?
     
     
    let configurationWrites = ClashMacSerialWrites()
     
    @Published var configurationCenterChain: ClashMacChainRequest?
     
    @Published var configurationCenterInspectedNode: ClashMacInspectedNode?
     
    @Published var configurationCenterEditingNode: ClashMacEditingNode?
     
     
     
     
     
     
    @Published var configurationCenterCreatesNode = false
     
     
    @Published private(set) var editorSyntax: ClashMacEditorSyntax?

     
     
    func loadEditorSyntaxOnce() {
        guard editorSyntax == nil else { return }
        Task { @MainActor [weak self] in
            guard let catalog = try? await ProfilesViewModel.loadSyntaxCatalog() else { return }
            self?.editorSyntax = ClashMacEditorSyntax(
                ruleTypes: catalog.ruleTypes.map {
                    ClashMacEditorSyntax.RuleType(name: $0.name, payload: $0.payload, options: $0.options ?? [],
                                                 logical: $0.logical == true, matchesHere: $0.matchesHere != false)
                },
                groupTypes: catalog.groupTypes.map(\.name),
                 
                 
                fields: catalog.fieldCatalog
            )
        }
    }
     
     
    @Published var configurationCenterShownItem: ClashMacConfigurationCenterItem?
     
    @Published var configurationCenterPendingPush: ClashMacConfigurationCenterItem?
    var configurationCenterPendingPushBinding: Binding<ClashMacConfigurationCenterItem?> {
        Binding(get: { self.configurationCenterPendingPush }, set: { self.configurationCenterPendingPush = $0 })
    }
     
    @Published var configurationCenterPendingModules = false
    var configurationCenterPendingModulesBinding: Binding<Bool> {
        Binding(get: { self.configurationCenterPendingModules }, set: { self.configurationCenterPendingModules = $0 })
    }

    var hasConfigurationInUse: Bool { currentProfile != nil }

     
     
     
     
    func currentConfigurationKeepsRulesInOriginal() async -> Bool {
        guard let id = currentProfile?.id, let store = profiles.configurationLibraryStore else { return false }
        return await Task.detached(priority: .utility) {
            (try? store.snapshot()).map { ClashMacOriginalRules.keepsRules(profileID: id, in: $0) } ?? false
        }.value
    }

     
     
     
    func readConfigurationLibraryIfUnread() async {
        if configurationLibrary.phase != .ready { await configurationLibrary.reload() }
    }

     
     
     
     
    func rulesChapterOfCurrentConfiguration() -> (@MainActor () -> AnyView)? {
        guard let id = currentProfile.flatMap({ try? ClashClientKit.Profile.ID($0.id) }),
              case .page(let page)? = outlineDestination(.rules, profileID: id) else { return nil }
        return page
    }

     
    func openModulesPage() {
        navigationRequest = .profiles
        configurationCenterSegment = .configurations
        configurationCenterPendingModules = true
    }

     
    func openCurrentConfigurationPage() {
        navigationRequest = .profiles
        guard let id = currentProfile.flatMap({ try? ClashClientKit.Profile.ID($0.id) }) else { return }
        configurationCenterSegment = .configurations
        configurationCenterPendingPush = .configuration(id)
    }

     
     
     
     
     
     
     
     
     
    func deleteKeyBelongsToTheShownItem(event: NSEvent?, keyWindow: NSWindow?) -> Bool {
        let fromKeyboard = event?.type == .keyDown
        guard let key = keyWindow else { return true }
        if let text = key.firstResponder as? NSTextView {
            guard fromKeyboard else { return key === mainWindow }
            if text.isEditable { text.deleteToBeginningOfLine(nil) }
            return false
        }
        return key === mainWindow || mainWindow == nil
    }

    func requestDeleteShownItem() {
        guard let item = configurationCenterShownItem else { return }
        if case .collection = item { return }
        configurationCenterPendingDelete = item
    }

    var configurationCenterPendingDeleteBinding: Binding<ClashMacConfigurationCenterItem?> {
        Binding(get: { self.configurationCenterPendingDelete }, set: { self.configurationCenterPendingDelete = $0 })
    }
    var configurationCenterImportBinding: Binding<ClashMacImportRequest?> {
        Binding(get: { self.configurationCenterImport }, set: { self.configurationCenterImport = $0 })
    }
    var configurationCenterChainBinding: Binding<ClashMacChainRequest?> {
        Binding(get: { self.configurationCenterChain }, set: { self.configurationCenterChain = $0 })
    }
    var configurationCenterInspectedNodeBinding: Binding<ClashMacInspectedNode?> {
        Binding(get: { self.configurationCenterInspectedNode }, set: { self.configurationCenterInspectedNode = $0 })
    }
    var configurationCenterEditingNodeBinding: Binding<ClashMacEditingNode?> {
        Binding(get: { self.configurationCenterEditingNode }, set: { self.configurationCenterEditingNode = $0 })
    }
    var configurationCenterCreatesNodeBinding: Binding<Bool> {
        Binding(get: { self.configurationCenterCreatesNode }, set: { self.configurationCenterCreatesNode = $0 })
    }
    var configurationCenterEditingSchemeBinding: Binding<ClashMacLibrarySelection?> {
        Binding(get: { self.configurationCenterEditingScheme }, set: { self.configurationCenterEditingScheme = $0 })
    }

    var showsConfigurationWizardBinding: Binding<Bool> {
        Binding(get: { self.showsConfigurationWizard }, set: { self.showsConfigurationWizard = $0 })
    }
    var configurationCenterWindowSheetBinding: Binding<ClashMacCentreWindowSheet?> {
        Binding(get: { self.configurationCenterWindowSheet }, set: { self.configurationCenterWindowSheet = $0 })
    }

     
     
    func closeConfigurationImport() {
        configurationCenterImport = nil
        if case .importing = configurationCenterWindowSheet { configurationCenterWindowSheet = nil }
    }

     
     
     
     
    private func configurationImportActions() -> ClashMacSourceImportActions {
        let profiles = self.profiles
        var actions = ClashMacSourceImportActions(
            fetch: { url, label in
                try await profiles.fetchConfigurationSource(url: url, label: label)
            },
            readFile: { name, data, companions in
                 
                 
                let resources = companions.map { ExternalResourceImportFile(fileName: $0.fileName, data: $0.data) }
                return try await Task.detached {
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    let yaml = try ProxyImportBridge.derivedSubscriptionYAML(from: data)
                    return try ConfigurationCenterSourceBridge.payload(
                        label: name, origin: .file(name), original: data, yaml: yaml, resources: resources
                    )
                }.value
            },
            importOriginal: { [weak self] payload in
                guard let self else { return }
                 
                 
                 
                 
                await self.configurationLibrary.reload()
                var draft = ConfigurationCreationDraft()
                draft.useOriginal(payload)
                _ = try await profiles.createConfiguration(
                    draft, generation: self.configurationLibrary.snapshot.generation, id: UUID().uuidString.lowercased()
                )
                await self.configurationLibrary.reload()
                 
                 
                self.closeConfigurationImport()
            },
             
             
             
            readNodes: { definition in
                try await Task.detached {
                    let nodes = try CustomNodePayload.payload(inDefinition: definition)
                    guard !nodes.isEmpty else { throw CustomNodeAppendError.missingName }
                    let document = try JSONSerialization.data(withJSONObject: ["proxies": nodes])
                    let yaml = try ConfigTransforms.jsonToYAML(String(decoding: document, as: UTF8.self))
                    return try ConfigurationCenterSourceBridge.payload(
                        label: nodes.count == 1 ? (nodes[0]["name"] as? String ?? ConfigurationBuiltins.customNodesName)
                            : ConfigurationBuiltins.customNodesName,
                        origin: .customNodes, original: Data(yaml.utf8), yaml: yaml
                    )
                }.value
            },
             
             
             
             
            createQuickRule: { [weak self] raw, enabled, comment in
                guard let self, let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                var snapshot = try await Task.detached { try store.snapshot() }.value
                let myRules = ClashCopy.string("My Rules", locale: self.preferences.language.locale)
                let active = profiles.activeProfileID
                let activeSchemeID = active.flatMap { id in snapshot.recipes.first { $0.id == id }?.ruleSchemeID }
                let schemeID: String
                switch QuickRulePlan.make(activeSchemeID: activeSchemeID, schemes: snapshot.rules, myRulesLabel: myRules) {
                case .reuse(let id):
                    schemeID = id
                case .copy(let base):
                    let before = Set(snapshot.rules.map(\.id))
                    snapshot = try await profiles.copyConfigurationRuleScheme(base, label: myRules, generation: snapshot.generation)
                    guard let made = snapshot.rules.first(where: { !before.contains($0.id) }) else {
                        throw ConfigurationLibraryError.invalidIdentifier
                    }
                    schemeID = made.id
                }
                guard let scheme = snapshot.rules.first(where: { $0.id == schemeID }) else {
                    throw ConfigurationLibraryError.missingDependency(schemeID)
                }
                var draft = try await Task.detached(priority: .userInitiated) {
                    try ConfigurationRuleDraft(scheme: scheme, payload: try store.ruleSchemePayload(schemeID))
                }.value
                draft.insertRuleFirst(raw)
                if let first = draft.rows.first { draft.setRule(raw, enabled: enabled, note: comment, rowID: first.id) }
                snapshot = try await profiles.saveConfigurationRuleDraft(draft, generation: snapshot.generation)
                if let active,
                   let recipe = snapshot.recipes.first(where: { $0.id == active }),
                   recipe.ruleSchemeID != schemeID {
                    var edit = ConfigurationCreationAdapter.editingDraft(
                        recipe: recipe, label: profiles.profiles.first(where: { $0.id == active })?.label ?? recipe.label
                    )
                    edit.selectedRuleID = schemeID
                    try await profiles.editConfiguration(edit, id: active, generation: snapshot.generation)
                }
                await self.configurationLibrary.reload()
            }
        )
         
         
         
        actions.fetchNodesOnly = { url, label in
            try await profiles.fetchConfigurationSource(url: url, label: label, nodesOnly: true)
        }
        actions.readFileNodesOnly = { name, data, companions in
            let resources = companions.map { ExternalResourceImportFile(fileName: $0.fileName, data: $0.data) }
            return try await Task.detached {
                try ConfigurationCenterSourceBridge.payload(
                    label: name, origin: .file(name), original: data, resources: resources, nodesOnly: true
                )
            }.value
        }
         
         
        actions.fileBytes = { try ImportedFileBytes.read($0) }
         
         
        actions.readPasted = { label, text, companions, nodesOnly in
            let resources = companions.map { ExternalResourceImportFile(fileName: $0.fileName, data: $0.data) }
            return try await Task.detached {
                try ClashMacPastedSource.payload(label: label, text: text, resources: resources, nodesOnly: nodesOnly)
            }.value
        }
        actions.refusedNodeCount = { AddProfileDraft.refusedNodeCount(for: $0) }
         
         
        actions.geoValues = { resource in
            await GeoCategoryCache.shared.categories(for: resource == .geoIP ? .geoip : .geosite)
        }
         
         
         
        actions.quickRuleTargets = { [weak self] in
            guard let self, let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let snapshot = try await Task.detached { try store.snapshot() }.value
            let myRules = ClashCopy.string("My Rules", locale: self.preferences.language.locale)
            let activeSchemeID = profiles.activeProfileID.flatMap { id in snapshot.recipes.first { $0.id == id }?.ruleSchemeID }
            let targetID: String
            switch QuickRulePlan.make(activeSchemeID: activeSchemeID, schemes: snapshot.rules, myRulesLabel: myRules) {
            case .reuse(let id): targetID = id
            case .copy(let base): targetID = base
            }
            let groups: [String] = try await Task.detached {
                if let scheme = snapshot.rules.first(where: { $0.id == targetID }) {
                    return try ConfigurationRuleDraft(scheme: scheme, payload: try store.ruleSchemePayload(targetID)).groups.map(\.name)
                }
                if ConfigurationBuiltins.isNative(targetID), let source = try ConfigurationBuiltins.source(for: targetID) {
                    return try ConfigurationRuleGroupSnapshot.read(OrderedJSON.parse(source.documentJSON)).map(\.name)
                }
                return []
            }.value
            var seen = Set<String>()
            return (["DIRECT", "REJECT"] + groups).filter { seen.insert($0).inserted }
        }
         
         
        actions.addRuleSet = { [weak self] draft in
            guard let self else { throw ConfigurationLibraryError.unreadable }
            let document = try draft.document()
            try await Task.detached { try ConfigTransforms.validateSource(document.serialized()) }.value
            let payload = ConfigurationSourcePayload(
                record: draft.record(), original: Data(document.serialized().utf8),
                documentJSON: document.serialized(), resourceFiles: draft.resourceFiles
            )
            try await self.configurationLibrary.addSource(payload)
        }
         
         
         
         
        actions.fetchRules = { url, label in try await profiles.fetchRuleLibrarySource(url: url, label: label) }
        actions.ruleSetAtLink = { _, failure in
            (failure as? ConfigurationLinkIsARuleSet).map { (found: $0.found, link: $0.link) }
        }
        actions.ruleSetIn = { data in await ConfigurationTowerRuleReader.ruleSet(in: data) }
         
         
         
        actions.customNodesEditor = { [weak self] accept, close in
            AnyView(
                 
                 
                 
                 
                ClashMacDialerCandidatesHost(
                    load: { [weak self] in await self?.dialerCandidates(excluding: "") ?? .empty }
                ) { candidates in
                    ConfigurationNodeSourceAdapter(
                        accept: accept,
                        dialerCandidates: candidates
                    )
                }
                .environment(\.clashProductModalDismiss, close)
            )
        }
        return actions
    }

    lazy var configurationImportActionsValue = configurationImportActions()

    lazy var configurationWizardActions: ClashMacConfigurationWizardActions = {
        var actions = ClashMacConfigurationWizardActions(
            create: { [profiles] draft, generation, id in
                _ = try await profiles.createConfiguration(draft, generation: generation, id: id)
            },
            sourceImport: configurationImportActionsValue
        )
        actions.loadScopeChoices = { [profiles] source, staged in
            try await Self.scopeChoices(source, staged: staged, store: profiles.configurationLibraryStore)
        }
         
         
         
        let previewLocale = preferences.language.locale
        actions.preview = { [profiles] draft in
            guard let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            return try await Task.detached {
                let generation = try store.snapshot().generation
                let nodes = try ConfigurationCompletionPreview.sections(draft: draft, library: store, generation: generation, nodes: true,
                                                                        locale: previewLocale)
                let rules = try ConfigurationCompletionPreview.sections(draft: draft, library: store, generation: generation, nodes: false,
                                                                        locale: previewLocale)
                return ClashMacWizardPreview(
                    nodes: nodes.reduce(0) { $0 + $1.rows.count },
                    rules: rules.first { $0.title == "Rules" }?.rows.count ?? rules.reduce(0) { $0 + $1.rows.count }
                )
            }.value
        }
        return actions
    }()

     
     
    static func scopeChoices(
        _ source: ConfigurationSourceRecord, staged: ConfigurationSourcePayload?, store: ConfigurationLibraryStore?
    ) async throws -> ClashMacNodeScopeChoices {
        try await Task.detached {
            let payload: ConfigurationSourcePayload
            if let staged {
                payload = staged
            } else {
                guard let store else { throw ConfigurationLibraryError.unreadable }
                payload = try store.payload(.init(source))
            }
            let document = try OrderedJSON.parse(payload.documentJSON)
            var nodes: [ClashConfigurationSelectableNode] = []
            if case .array(let entries) = document.topLevelValue("proxies") {
                nodes = entries.compactMap { node in
                    guard let name = node.topLevelValue("name")?.foundationValue as? String else { return nil }
                    return ClashConfigurationSelectableNode(name: name, type: node.topLevelValue("type")?.foundationValue as? String ?? "")
                }
            }
            return ClashMacNodeScopeChoices(
                collections: ConfigurationCollection.read(sourceID: source.id, document: document, kind: .nodes), nodes: nodes
            )
        }.value
    }

     
     
     
     
     
     
     
     
    func updateSourceAndItsCollections(_ id: String, replacingRules: Bool = false, at version: String? = nil) async throws {
        guard var source = configurationLibrary.snapshot.sources.first(where: { $0.id == id }) else {
            throw ConfigurationLibraryError.unreadable
        }
        if let version { source.version = version }
        let outcome = try await ConfigurationSourceUpdate.run(source, replacingRules: replacingRules, model: profiles,
                                                               locale: preferences.language.locale,
                                                               changed: { _ in }, status: { _ in })
        if !outcome.failures.isEmpty { configurationLibrary.report(outcome.failures.joined(separator: "\n")) }
    }

     
     
    private func configurationLibraryActions() -> ClashMacConfigurationLibraryActions {
        let profiles = self.profiles
        var actions = ClashMacConfigurationLibraryActions(
            load: {
                 
                 
                 
                 
                try? await profiles.recoverConfigurationPublications()
                do { try await profiles.registerLegacyConfigurationSources() } catch {
                     
                    NSLog("configuration-centre.legacy-registration-failed:%@", error.localizedDescription)
                }
                guard let store = await MainActor.run(body: { profiles.configurationLibraryStore }) else {
                    throw ConfigurationLibraryError.unreadable
                }
                return try await Task.detached { try store.snapshot() }.value
            },
            renameSource: { id, label, generation in
                try await profiles.renameConfigurationSource(id, label: label, generation: generation)
            },
            deleteSource: { id, generation in
                try await profiles.deleteConfigurationSource(id, generation: generation)
            },
            updateSource: { [weak self] id in
                 
                 
                 
                 
                 
                try await self?.updateSourceAndItsCollections(id)
            },
            deleteRuleScheme: { id, generation in
                try await profiles.deleteConfigurationRuleScheme(id, generation: generation)
            },
            addSource: { payload, generation in
                try await profiles.addConfigurationSource(payload, generation: generation)
            },
            addRuleScheme: { payload, generation in
                try await profiles.addConfigurationRuleScheme(payload, generation: generation)
            },
            copyScheme: { id, label, generation in
                try await profiles.copyConfigurationRuleScheme(id, label: label, generation: generation)
            }
        )
         
        actions.deleteSourceRestorably = { id, generation in
            let taken = try await profiles.deleteConfigurationSourceRestorably(id, generation: generation)
            return (taken.snapshot, taken.removal)
        }
        actions.deleteRuleSchemeRestorably = { id, generation in
            let taken = try await profiles.deleteConfigurationRuleSchemeRestorably(id, generation: generation)
            return (taken.snapshot, taken.removal)
        }
        actions.restoreRemoval = { removal, generation in
            try await profiles.restoreConfigurationLibraryRemoval(removal, expectedGeneration: generation)
        }
         
         
         
         
         
         
         
        actions.loadCollections = { snapshot in
            guard let store = await MainActor.run(body: { profiles.configurationLibraryStore }) else { return [] }
            return try await Task.detached { try ConfigurationCollectionContentBridge.catalog(store, snapshot: snapshot) }.value
        }
        actions.runningCounts = { entries in
            let container = await MainActor.run { profiles.appGroupContainer }
            return await Task.detached {
                 
                 
                let running = ConfigurationCollectionContentBridge.RunningProviders.load(container: container)
                let counted = running.map { ConfigurationCollectionContentBridge.withRunningCounts(entries, catalog: $0.catalog) } ?? entries
                return ConfigurationCollectionContentBridge.withRunningUsage(counted, running: running)
            }.value
        }
        actions.saveSourceSettings = { id, draft, generation in
            try await profiles.saveConfigurationSourceSettings(id, draft: draft, generation: generation)
        }
         
         
        actions.saveSourceDetails = { id, label, settings, generation in
            if let settings {
                return try await profiles.saveConfigurationSourceSettings(id, draft: settings, label: label, generation: generation)
            }
            return try await profiles.renameConfigurationSource(id, label: label, generation: generation)
        }
         
         
         
         
         
         
         
         
        actions.syncLegacyProfiles = { progress in
             
             
             
             
             
            var recipeIDs: Set<String> = []
            if let store = profiles.configurationLibraryStore,
               let snapshot = try? await Task.detached { try store.snapshot() }.value {
                recipeIDs = Set(snapshot.recipes.map(\.id))
            }
            let remote = profiles.profiles.filter { profile in
                guard case .url = profile.source else { return false }
                return !recipeIDs.contains(profile.id)
            }
            guard !remote.isEmpty else { return ClashMacBatchOutcome() }
            var outcome = ClashMacBatchOutcome()
            for (index, profile) in remote.enumerated() {
                progress(ClashCopy.string("Updating Sources…", locale: Locale.current) + " \(index + 1) / \(remote.count) · " + profile.label)
                do {
                    if try await profiles.refreshLegacyProfileAwaiting(profile) == .updated { outcome.updated += 1 }
                } catch {
                    outcome.failures.append(ClashCopy.format("%@: %@", locale: Locale.current, profile.label,
                                                             ClashErrorCopy.message(error, locale: Locale.current)))
                }
            }
            return outcome
        }
        actions.updateSourceReplacingRules = { [weak self] id, version in
             
             
             
            try await self?.updateSourceAndItsCollections(id, replacingRules: true, at: version)
        }
         
         
         
         
         
         
         
        actions.updateAllSources = { progress in
            guard profiles.configurationLibraryStore != nil else {
                return ClashMacBatchOutcome(failures: [ClashErrorCopy.message(ConfigurationLibraryError.unreadable, locale: Locale.current)])
            }
            let run = profiles.updateNodeLibrary(locale: Locale.current)
             
            let runID = profiles.nodeLibraryUpdate?.id
             
             
            let result = ClashMacRunResult<ProfilesViewModel.NodeLibraryUpdateRun>()
            let keep = profiles.$nodeLibraryUpdate.sink { if let run = $0, run.id == runID, run.finished { result.value = run } }
            await Self.follow(profiles.$nodeLibraryUpdate.compactMap { $0?.progress }.removeDuplicates().eraseToAnyPublisher(),
                              into: progress, until: run)
            keep.cancel()
            guard let finished = result.value else { return ClashMacBatchOutcome() }
            return ClashMacBatchOutcome(updated: finished.updated,
                                        notTaken: max(0, finished.total - finished.updated - finished.unconfirmed),
                                        unconfirmed: finished.unconfirmed, appliesOnConnect: finished.appliesOnConnect,
                                        failures: finished.failures)
        }
         
         
         
         
         
        actions.updateAllRuleSets = { progress in
            guard let store = profiles.configurationLibraryStore else {
                return ClashMacBatchOutcome(failures: [ClashErrorCopy.message(ConfigurationLibraryError.unreadable, locale: Locale.current)])
            }
            let entries: [ConfigurationCollectionEntry]
            do {
                entries = try await Task.detached {
                    let snapshot = try store.snapshot()
                     
                     
                    return ClashMacConfigurationLibraryModel.libraryRuleSets(
                        try ConfigurationCollectionContentBridge.catalog(store, snapshot: snapshot), in: snapshot)
                }.value
            } catch {
                return ClashMacBatchOutcome(failures: [ClashErrorCopy.message(error, locale: Locale.current)])
            }
            let run = profiles.updateRuleCollections(entries, scripts: .silent, locale: Locale.current)
            let runID = profiles.ruleCollectionUpdate?.id
            let result = ClashMacRunResult<ProfilesViewModel.CollectionUpdateRun>()
            let keep = profiles.$ruleCollectionUpdate.sink { if let run = $0, run.id == runID, run.finished { result.value = run } }
            await Self.follow(profiles.$ruleCollectionUpdate.compactMap { $0?.progress }.removeDuplicates().eraseToAnyPublisher(),
                              into: progress, until: run)
            keep.cancel()
            guard let finished = result.value else { return ClashMacBatchOutcome() }
            return ClashMacBatchOutcome(updated: finished.updated,
                                        notTaken: max(0, finished.total - finished.updated - finished.unconfirmed),
                                        unconfirmed: finished.unconfirmed, appliesOnConnect: finished.appliesOnConnect,
                                        failures: finished.failures)
        }
        actions.updateCollection = { entry in
            try await Self.updateCollection(entry, profiles: profiles)
        }
        return actions
    }

     
     
    private func sourcePage(_ source: ConfigurationSourceRecord, list: ClashProfilesListPresentation) -> some View {
        let sourceID = source.id
        let readers = configurationLibrary.configurations(usingSource: sourceID)
        let locale = locale
        var page = ClashMacSourceContentPage(
            source: source,
            usedBy: list.profiles.filter { readers.contains($0.id.rawValue) },
            isUpdating: configurationLibrary.updatingSourceIDs.contains(sourceID),
            collections: configurationLibrary.collections(for: sourceID),
            collectionPage: { [weak self] entry in
                AnyView(
                    ClashMacCollectionPane(
                        collection: entry.collection, sourceLabel: entry.source.displayLabel(locale: locale),
                        actions: self?.collectionPageActions(entry) ?? .unavailable
                    )
                    .navigationTitle(Text(verbatim: entry.collection.name))
                )
            },
            actions: sourceContentActions(source)
        )
        page.updateError = configurationLibrary.updateFailures[sourceID]
        page.updateIssue = Self.updateIssueMessage(configurationLibrary.snapshot, sourceID: sourceID, locale: preferences.language.locale)
        return page
    }

    private func sourceContentActions(_ source: ConfigurationSourceRecord) -> ClashMacSourceContentActions {
        let sourceID = source.id
        let isCustom = source.origin == .customNodes && source.nodeChain == nil && source.isRetainedSnapshot != true
        var actions = ClashMacSourceContentActions(
            loadNodes: { [weak self] in try await self?.sourceNodes(sourceID) ?? [] },
            openNode: { [weak self] node in self?.configurationCenterInspectedNode = ClashMacInspectedNode(node: node) },
            update: { [weak self] in Task { _ = await self?.configurationLibrary.updateSourceSaying(sourceID) } },
            delete: { [weak self] in self?.configurationCenterPendingDelete = .source(sourceID) },
            editSource: { [weak self] in
                self?.openWindowAction?(id: "source-editor", value: ClashMacSourceEditorRequest(profileID: "", nodeSourceID: sourceID))
            },
            details: ClashMacSourcePaneActions(
                save: { [weak self] label, settings in
                    guard let self else { return nil }
                    if await self.configurationLibrary.saveSourceDetails(sourceID, label: label, settings: settings) { return nil }
                     
                    return self.configurationLibrary.lastError ?? ClashErrorCopy.message(ConfigurationLibraryError.busy, locale: Locale.current)
                },
                update: {}, delete: {}
            )
        )
        if isCustom {
             
            actions.openNode = { [weak self] node in
                guard let record = CustomNodesView.record(fromNodeJSON: node.json) else {
                    self?.configurationCenterInspectedNode = ClashMacInspectedNode(node: node)
                    return
                }
                self?.configurationCenterEditingNode = ClashMacEditingNode(source: source, node: node, record: record)
            }
            actions.deleteNode = { [weak self] node in
                guard let self else { return }
                Task { @MainActor in
                    do {
                        let next = try await self.profiles.deleteConfigurationCustomNode(.init(source), index: node.index)
                        self.configurationLibrary.apply(next)
                         
                        self.offerUndo(of: node.name, operation: "node.delete.\(source.id).\(node.index)") { [weak self] in
                            guard let self,
                                  let current = self.configurationLibrary.snapshot.sources.first(where: { $0.id == source.id }) else {
                                return .superseded("")
                            }
                            do {
                                 
                                try await self.configurationLibrary.serialized {
                                    let restored = try await self.profiles.insertConfigurationCustomNode(
                                        .init(current), nodeJSON: node.json, at: node.index)
                                    self.configurationLibrary.apply(restored)
                                }
                                return .restored
                            } catch { return .failed(ClashErrorCopy.message(error, locale: Locale.current)) }
                        }
                    } catch {
                         
                         
                        self.feedback.say(ClashMacFeedbackSentences.couldNotDelete(node.name, reason: ClashErrorCopy.message(error, locale: Locale.current),
                                                                                     id: "node.delete"),
                                           operation: "node.delete.\(source.id).\(node.index)")
                    }
                }
            }
            actions.addNode = { [weak self] in
                self?.configurationCenterImport = ClashMacImportRequest(purpose: .nodes, tab: .nodes, mergeIntoSourceID: sourceID)
            }
        }
        if source.nodeChain != nil {
            actions.editChain = { [weak self] in self?.configurationCenterChain = ClashMacChainRequest(existingID: sourceID) }
        }
        return actions
    }

     
     
    static func updateIssueMessage(_ library: ConfigurationLibrarySnapshot, sourceID: String, locale: Locale) -> String? {
        let issues = (library.updateIssues ?? []).filter { $0.sourceID == sourceID }
        guard !issues.isEmpty else { return nil }
        let names = issues.map { issue in
            library.recipes.first { $0.id == issue.itemID }?.label
                ?? library.sources.first { $0.id == issue.itemID }.map { $0.displayLabel(locale: locale) } ?? issue.itemID
        }
        return ClashCopy.string("Some references are unavailable. Previous versions were kept:", locale: locale) + " " + names.joined(separator: ", ")
    }

     
     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    private static func updateCollection(
        _ entry: ConfigurationCollectionEntry, profiles: ProfilesViewModel,
        step: @escaping @MainActor (ClashMacCollectionUpdateStep) -> Void = { _ in }
    ) async throws -> ClashMacBatchOutcome {
        guard let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        if profiles.isUpdatingNodeLibrary || profiles.isUpdatingRuleCollections { step(.waiting) }
         
         
         
         
        var lines: [String] = []
        var outcome = ClashMacBatchOutcome()
        var libraryFailed = false
        await profiles.pageLibraryWrite {
            step(.downloading)
            let source: ConfigurationSourcePayload
            do { source = try await Task.detached { try store.payload(.init(entry.source)) }.value } catch {
                lines = [ClashErrorCopy.message(error, locale: Locale.current)]
                return
            }
            var libraryFailure: Error?
            var refreshed = ConfigurationCollectionContentBridge.CollectionRefresh.downloaded
            do { refreshed = try await ConfigurationCollectionContentBridge.refresh(entry, source: source, inUse: profiles.providerCatalogInUse()) }
            catch { libraryFailure = error }
             
             
             
             
            let copyIn = libraryFailure == nil && refreshed == .downloaded
            step(.applying(libraryCopyIn: copyIn))
             
             
             
            let downloaded = copyIn ? [entry] : []
             
             
             
             
             
             
             
             
            let takeStep: (ProfilesViewModel.CollectionTakeStep) -> Void = { taking in
                switch taking {
                case .publishing: break
                case .handingOver: step(.takingEffect)
                 
                 
                 
                case .coreUpdating(let onlyRuleSets): step(.tunnelDownloading(onlyRuleSets: onlyRuleSets))
                }
            }
            let take: ProfilesViewModel.CollectionTake
            switch (libraryFailure, refreshed) {
             
             
            case (nil, .downloaded): take = await profiles.takeUpdatedCollections([entry], scripts: .surfaced, step: takeStep)
            case (nil, .coreOwned): take = await profiles.takeUpdatedCollections([], coreOwned: [entry], scripts: .surfaced, step: takeStep)
            default: take = await profiles.takeUpdatedCollections([], failed: [entry], scripts: .surfaced, step: takeStep)
            }
            lines = (libraryFailure.map { [ClashErrorCopy.message($0, locale: Locale.current)] } ?? []) + take.failures
            libraryFailed = libraryFailure != nil
            let updated = ProfilesViewModel.CollectionUpdateRun.tookEffect([entry], downloaded: downloaded, take: take)
            let unconfirmed = ProfilesViewModel.CollectionUpdateRun.unconfirmed([entry], take: take)
            outcome = ClashMacBatchOutcome(updated: updated, notTaken: max(0, 1 - updated - unconfirmed),
                                           unconfirmed: unconfirmed, appliesOnConnect: take.appliesOnConnect)
             
             
            outcome.word = ProfilesViewModel.CollectionTake.word(for: entry.id, take: take, libraryCopyIn: copyIn)
        }
         
         
         
         
        if !lines.isEmpty, libraryFailed || outcome.updated + outcome.unconfirmed == 0 || outcome.notTaken > 0 {
            throw ClashMacCollectionTakeFailure(lines: lines)
        }
        return outcome
    }

     
     
     
    private static func follow(
        _ lines: AnyPublisher<String, Never>, into progress: @escaping @MainActor (String) -> Void,
        until run: Task<Void, Never>
    ) async {
        let follower = Task { @MainActor in
            for await line in lines.values { progress(line) }
        }
        await run.value
        follower.cancel()
        await follower.value
    }

    private func collectionPageActions(_ entry: ConfigurationCollectionEntry) -> ClashMacCollectionPageActions {
        let profiles = self.profiles
         
         
        let locale = preferences.language.locale
        var actions = ClashMacCollectionPageActions(load: { query, offset in
            guard let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            return try await Task.detached {
                let source = try store.payload(.init(entry.source))
                let page = try ConfigurationCollectionContentBridge.page(entry, source: source, query: query, offset: offset)
                let rows: [ClashMacCollectionPage.Row]
                if entry.id.kind == .nodes {
                    rows = page.nodes.enumerated().map { index, json in
                        let node = try? OrderedJSON.parse(json)
                        return ClashMacCollectionPage.Row(
                            id: offset + index,
                            title: node?.topLevelValue("name")?.foundationValue as? String ?? String(offset + index + 1),
                            subtitle: node?.topLevelValue("type")?.foundationValue as? String ?? ""
                        )
                    }
                } else {
                    rows = page.lines.enumerated().map { index, line in ClashMacCollectionPage.Row(id: offset + index, title: line, subtitle: nil) }
                }
                return ClashMacCollectionPage(
                    rows: rows, count: page.count, updatedAt: page.updatedAt, nextOffset: page.nextOffset, message: page.statusMessage(locale: locale)
                )
            }.value
        })
        if entry.collection.type == "http" {
            actions.update = { step in
                try await Self.updateCollection(entry, profiles: profiles, step: step).word
            }
             
             
            actions.runningCount = {
                let container = profiles.appGroupContainer
                var bare = entry
                bare.memberCount = nil
                return await Task.detached {
                    ConfigurationCollectionContentBridge.withRunningCounts([bare], container: container).first?.memberCount
                }.value
            }
            let center = NotificationCenter.default
             
             
            actions.runningCountChanges = Publishers.MergeMany(
                center.publisher(for: ProfileStore.didChangeNotification).map { _ in () }.eraseToAnyPublisher(),
                center.publisher(for: .clashActiveConfigurationRepublished).map { _ in () }.eraseToAnyPublisher(),
                center.publisher(for: ProviderFirstLoadRetry.didRefreshNotification).map { _ in () }.eraseToAnyPublisher(),
                profiles.$activeProfileID.dropFirst().removeDuplicates().map { _ in () }.eraseToAnyPublisher()
            ).debounce(for: .milliseconds(400), scheduler: RunLoop.main).eraseToAnyPublisher()
             
             
             
            let id = entry.id
            actions.inSharedRun = entry.id.kind == .rules
                ? profiles.$ruleCollectionUpdate.map { run in run.map { !$0.finished && $0.updating.contains(id) } ?? false }
                    .removeDuplicates().eraseToAnyPublisher()
                : profiles.$nodeLibraryUpdate.map { run in run.map { !$0.finished } ?? false }
                    .removeDuplicates().eraseToAnyPublisher()
        }
        if entry.id.kind == .rules {
            actions.createScheme = { [weak self] in
                guard let self, let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                let next = try await Task.detached {
                    try store.addRuleScheme(collection: entry, expectedGeneration: store.snapshot().generation)
                }.value
                self.configurationLibrary.apply(next)
            }
        }
        actions.definitionIsEditable = entry.definitionIsEditable
        actions.editSource = { [weak self] in
            self?.openWindowAction?(
                id: "source-editor",
                value: ClashMacSourceEditorRequest(profileID: "", collection: ClashMacCollectionReference(entry))
            )
        }
        actions.delete = { [weak self] in
            guard let self else { throw ConfigurationLibraryError.unreadable }
            let next = try await profiles.saveConfigurationCollection(entry, definitionJSON: nil)
            self.configurationLibrary.apply(next)
        }
        return actions
    }

     
     
    private func sourceNodes(_ sourceID: String) async throws -> [ClashMacSourceNode] {
        guard let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        return try await Task.detached {
            guard let source = try store.snapshot().sources.first(where: { $0.id == sourceID }) else {
                throw ConfigurationLibraryError.missingDependency(sourceID)
            }
            let payload = try store.payload(.init(source))
            guard case .array(let values) = try OrderedJSON.parse(payload.documentJSON).topLevelValue("proxies") else { return [] }
            return values.enumerated().map { index, node in
                ClashMacSourceNode(
                    index: index,
                    name: node.topLevelValue("name")?.foundationValue as? String ?? String(index + 1),
                    type: node.topLevelValue("type")?.foundationValue as? String ?? "",
                    server: node.topLevelValue("server")?.foundationValue as? String,
                    json: node.serialized()
                )
            }
        }.value
    }

     
     
     
    private func chainSheetActions(existing: ConfigurationSourceRecord?) -> ClashMacChainSheetActions {
        let profiles = self.profiles
        let library = configurationLibrary
        let locale = preferences.language.locale
        return ClashMacChainSheetActions(
            loadChoices: {
                guard let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                return try await Task.detached {
                    let snapshot = try store.snapshot()
                    var choices: [ClashMacChainChoice] = []
                    for record in snapshot.availableSources where record.suppliesNodes && record.nodeChain == nil {
                        let payload = try store.payload(.init(record))
                        guard case .array(let nodes) = try OrderedJSON.parse(payload.documentJSON).topLevelValue("proxies") else { continue }
                        for node in nodes {
                            guard let name = node.topLevelValue("name")?.foundationValue as? String, !name.isEmpty else { continue }
                             
                            if let dialer = node.topLevelValue("dialer-proxy")?.foundationValue as? String,
                               !dialer.isEmpty, dialer != "DIRECT" { continue }
                            choices.append(.init(hop: .init(source: .init(record), nodeName: name),
                                                 sourceLabel: record.displayLabel(locale: locale)))
                        }
                    }
                    return choices
                }.value
            },
            commit: { name, entry, exit in
                guard let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                let payload = try await Task.detached {
                    var record = existing ?? ConfigurationSourceRecord(
                        id: "chain-" + UUID().uuidString.lowercased(), label: name, origin: .customNodes, nodeCount: 1
                    )
                    record.label = name.isEmpty ? entry.nodeName + " → " + exit.nodeName : name
                    return try ConfigurationNodeChain.materialize(record: record, chain: .init(entry: entry, exit: exit), load: store.payload)
                }.value
                if let existing {
                    library.apply(try await profiles.saveConfigurationChain(.init(existing), replacement: payload))
                } else {
                    try await library.addSource(payload)
                }
            }
        )
    }

     
     
     
    @ViewBuilder
    private func configurationDoor(
        _ door: ClashMacConfigurationDoor,
        profileID: ClashClientKit.Profile.ID,
        list: ClashProfilesListPresentation
    ) -> some View {
        if case .scheme(let schemeID) = door {
             
             
             
             
             
             
            configurationCenterRoutedDetail(.scheme(schemeID), list: list, actions: configurationCenterListActions(list))
        } else if let profile = profiles.profiles.first(where: { $0.id == profileID.rawValue }) {
            switch door {
            case .scheme:
                EmptyView()
            case .network:
                 
                 
                 
                ProfileBaseDocumentHost(profiles: profiles, profile: profile) { [profiles] base in
                    ProfileNetworkSettingsView.opening(
                        profile: profile, sourceYAML: base, ownsNavigationContainer: false
                    ) { draft in
                        try profiles.updateNetwork(draft)
                    }
                }
            case .trust:
                 
                 
                 
                ProfileRuntimeTrustEditor.opening(
                    profile: profile, sourceYAML: profiles.sourceYAML(for: profile), patchJSON: profile.override.patchJSON
                ) { [profiles, feedback] patchJSON in
                    var draft = ProfileAdvancedOverridesDraft(profile: profile)
                    draft.rawPatchJSON = patchJSON
                     
                     
                     
                    Task { @MainActor in
                        do { try await profiles.updateAdvancedOverrides(draft) }
                        catch {
                            feedback.say(ClashMacFeedbackSentences.couldNotSave(reason: ClashErrorCopy.message(error, locale: Locale.current), id: "trust.save"),
                                          operation: "trust.save")
                        }
                    }
                }
            }
        } else {
            EmptyView()
        }
    }

     

     
     
     
     
    func configurationCenter(_ list: ClashProfilesListPresentation) -> some View {
        configurationCenterLatestList = list
        let actions = configurationCenterListActions(list)
        configurationCenterDeleteHandler = { item in actions.delete(item) }
        armDeleteConfirmation()
        return ClashMacConfigurationCenterView(segment: configurationCenterSegmentBinding) {
            self.configurationCenterListPage(.configurations, list: list, actions: actions)
        } nodes: {
            self.configurationCenterListPage(.nodes, list: list, actions: actions)
        } rules: {
            self.configurationCenterListPage(.rules, list: list, actions: actions)
        }
        .task { [weak self] in
            guard let self, self.configurationLibrary.phase == .idle else { return }
            await self.configurationLibrary.reload()
        }
         
         
        .onAppear { [weak self] in self?.loadEditorSyntaxOnce() }
        .environment(\.clashMacEditorSyntax, editorSyntax)
         
         
         
         
         
         
         
         
         
         
         
        .modifier(ClashMacCentrePresentations(model: self, actions: actions))
         
         
         
         
         
        .clashProductModal(item: configurationCenterInspectedNodeBinding, role: .form) { inspected in
            ProxyNodeDetailSheet(
                nodeName: inspected.node.name, yaml: nil, providersDir: nil,
                suppliedDetails: CustomNodesView.record(fromNodeJSON: inspected.node.json)?.protocolDetails
            )
            .clashModalPresentation(.form)
        }
         
         
         
        .clashProductModal(item: configurationCenterEditingNodeBinding, role: .form) { [weak self] editing in
            ClashFeatureNavigationContainer {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                ClashMacDialerCandidatesHost(
                    load: { [weak self] in
                        await self?.dialerCandidates(excluding: editing.record.name) ?? .empty
                    }
                ) { candidates in
                    ProxyNodeDetailsView(
                        record: editing.record,
                        retest: {},
                        saveNode: { [weak self] _, json in
                            guard let self else { throw ConfigurationLibraryError.unreadable }
                            let next = try await self.profiles.saveConfigurationCustomNode(
                                .init(editing.source), nodeJSON: json, index: editing.node.index
                            )
                            self.configurationLibrary.apply(next)
                        },
                        showsTesting: false,
                        dialerRouting: .payloadField,
                        dialerCandidates: candidates,
                        onDone: { [weak self] in self?.configurationCenterEditingNode = nil },
                        commitTitle: "Save"
                    )
                }
            }
            .clashPageSizedSheet()
        }
         
         
         
         
         
        .clashProductModal(isPresented: configurationCenterCreatesNodeBinding, role: .form) { [weak self] in
            ClashFeatureNavigationContainer {
                ClashMacDialerCandidatesHost(
                    load: { [weak self] in await self?.dialerCandidates(excluding: "") ?? .empty }
                ) { candidates in
                    ProxyNodeDetailsView(
                        record: CustomNodesView.newNodeTemplate,
                        retest: {},
                        saveNode: { [weak self] _, json in
                            guard let self else { throw ConfigurationLibraryError.unreadable }
                             
                             
                             
                             
                             
                            let payload = try await Task.detached {
                                let nodes = try CustomNodeAppend.appended(payload: [], editedJSON: json)
                                let document = try JSONSerialization.data(withJSONObject: ["proxies": nodes])
                                let yaml = try ConfigTransforms.jsonToYAML(
                                    String(decoding: document, as: UTF8.self)
                                )
                                return try ConfigurationCenterSourceBridge.payload(
                                    label: nodes.first?["name"] as? String ?? ConfigurationBuiltins.customNodesName,
                                    origin: .customNodes,
                                    original: Data(yaml.utf8),
                                    yaml: yaml
                                )
                            }.value
                            var source = payload
                            source.record.registersSuppliedRules = false
                            try await self.configurationLibrary.addSource(source)
                        },
                        showsTesting: false,
                        isNew: true,
                        dialerRouting: .payloadField,
                        dialerCandidates: candidates,
                        onDone: { [weak self] in self?.configurationCenterCreatesNode = false },
                        commitTitle: "Save"
                    )
                }
            }
            .clashPageSizedSheet()
        }
    }

     
     
     
     
     
    fileprivate func importSheet(_ request: ClashMacImportRequest) -> some View {
        ClashMacSourceImportSheet(
            purpose: request.purpose,
            actions: configurationImportActionsValue,
            initialTab: request.tab,
            accept: { [weak self] payload in
                guard let self else { return }
                 
                let existed = self.configurationLibrary.snapshot.sources.contains { $0.id == payload.record.id }
                if let target = request.mergeIntoSourceID,
                   let source = self.configurationLibrary.snapshot.sources.first(where: { $0.id == target }) {
                     
                    guard case .array(let nodes) = try OrderedJSON.parse(payload.documentJSON).topLevelValue("proxies"), !nodes.isEmpty else {
                        throw ConfigurationLibraryError.unreadable
                    }
                    var version = ConfigurationSourceVersion(source)
                    for node in nodes {
                        let next = try await self.profiles.saveConfigurationCustomNode(version, nodeJSON: node.serialized(), index: nil)
                        self.configurationLibrary.apply(next)
                        if let updated = next.sources.first(where: { $0.id == target }) { version = ConfigurationSourceVersion(updated) }
                    }
                } else {
                    switch request.purpose {
                    case .rules:
                         
                         
                         
                        if payload.record.ruleCount > 0 {
                            try await self.configurationLibrary.addRuleScheme(payload)
                        } else {
                            let collections = try ConfigurationCollection.read(
                                sourceID: payload.record.id, document: try OrderedJSON.parse(payload.documentJSON), kind: .rules
                            )
                            guard !collections.isEmpty else { throw ConfigurationLibraryError.missingRules }
                            var source = payload
                            source.record.suppliesNodes = false
                            source.record.registersSuppliedRules = false
                            try await self.configurationLibrary.addSource(source)
                        }
                    case .nodes:
                         
                         
                        guard payload.record.suppliesNodes, payload.record.nodeCount > 0 || payload.record.providerCount > 0 else {
                            throw ConfigurationLibraryError.missingNodes
                        }
                        var source = payload
                        source.record.registersSuppliedRules = false
                        try await self.configurationLibrary.addSource(source)
                    }
                }
                self.closeConfigurationImport()
                 
                 
                if let target = request.mergeIntoSourceID,
                   let source = self.configurationLibrary.snapshot.sources.first(where: { $0.id == target }) {
                    self.feedback.say(ClashMacFeedbackSentences.updated(source.displayLabel(locale: self.preferences.language.locale),
                                                                        id: "import"), operation: "import")
                } else if existed {
                    self.feedback.say(ClashMacFeedbackSentences.updated(payload.record.displayLabel(locale: self.preferences.language.locale),
                                                                        id: "import"), operation: "import")
                } else {
                    self.feedback.say(ClashMacFeedbackSentences.added(payload.record.displayLabel(locale: self.preferences.language.locale),
                                                                      id: "import"), operation: "import")
                }
            },
            close: { [weak self] in self?.closeConfigurationImport() }
        )
    }

     
     
     
     
     
    fileprivate func configurationWizardSheet() -> some View {
        ClashMacConfigurationWizardSheet(
            model: configurationLibrary,
            actions: configurationWizardActions,
            created: { [weak self] name in
                self?.feedback.say(ClashMacFeedbackSentences.added(name, id: "configuration.create"),
                                    operation: "configuration.create")
            }
        )
    }

     
     
     
    func dialerCandidates(excluding selfName: String) async -> DialerProxyCandidates {
         
         
         
         
         
         
         
        guard let profile = currentProfile,
              let yaml = await profiles.loadPresentedProxiesYAML(for: profile)
        else { return .empty }
        return DialerProxyCandidates.make(sourceYAML: yaml, excluding: selfName)
    }

     
     
    func quickAddController(
        _ target: ProfileQuickAddController.Target,
        profileID: String? = nil
    ) -> ProfileQuickAddController {
        let key = QuickAddKey(target: target, profileID: profileID)
        if let existing = quickAddControllers[key] { return existing }
        let controller = ProfileQuickAddController(model: profiles, target: target)
        switch target {
        case .source, .rules:
             
             
            controller.onSourceAdded = { [weak self] snapshot in
                self?.configurationLibrary.apply(snapshot)
            }
        case .profile, .scripts:
            break
        }
        quickAddControllers[key] = controller
        return controller
    }

     
    @ViewBuilder
    private func quickAddCard(_ segment: ClashMacConfigurationCenterSegment) -> some View {
        switch segment {
        case .configurations:
             
             
             
            MacQuickAddCard(
                controller: quickAddController(.profile),
                identifiers: .configurations,
                doors: ClashMacQuickAddDoors()
            )
        case .nodes:
            MacQuickAddCard(
                controller: quickAddController(.source),
                identifiers: .nodes,
                doors: ClashMacQuickAddDoors()
            )
        case .rules:
            MacQuickAddCard(
                controller: quickAddController(.rules),
                identifiers: .rules,
                doors: ClashMacQuickAddDoors()
            )
        }
    }

     
     
     
     
    @ViewBuilder
    private func scriptsQuickAddCard(
        profileID: ClashClientKit.Profile.ID,
        reload: @escaping @MainActor () -> Void
    ) -> some View {
         
         
         
         
         
         
        let controller = quickAddController(.scripts, profileID: profileID.rawValue)
        MacQuickAddCard(
            controller: controller,
            identifiers: .scripts,
            doors: ClashMacQuickAddDoors()
        )
        .onAppear { controller.onScriptAdded = { _ in reload() } }
    }

    private func configurationCenterListPage(
        _ segment: ClashMacConfigurationCenterSegment,
        list: ClashProfilesListPresentation,
        actions: ClashMacConfigurationCenterListActions
    ) -> some View {
        ClashMacConfigurationCenterListPage(
            segment: segment,
            model: configurationLibrary,
            profiles: list.profiles,
            pendingDelete: configurationCenterPendingDeleteBinding,
            pendingPush: configurationCenterPendingPushBinding,
            pendingModules: configurationCenterPendingModulesBinding,
            actions: actions,
            quickAdd: { [weak self] segment in
                AnyView(self?.quickAddCard(segment))
            }
        ) { [weak self] item in
            self?.configurationCenterRoutedDetail(item, list: list, actions: actions) ?? AnyView(EmptyView())
        }
    }

     
     
     
    private func configurationCenterRoutedDetail(
        _ item: ClashMacConfigurationCenterItem, list: ClashProfilesListPresentation, actions: ClashMacConfigurationCenterListActions
    ) -> AnyView {
                 
                 
                let hadRecipe: Bool = {
                    guard case .configuration(let id) = item else { return false }
                    return self.configurationLibrary.snapshot.recipes.contains { $0.id == id.rawValue }
                }()
                return AnyView(
                    ClashMacObservedLibraryPage(model: self.configurationLibrary) { [weak self] _ in
                        if let self {
                             
                             
                             
                             
                            ClashMacFollowsProfilesPage(profiles: self.profiles) { [weak self] in
                                if let self {
                                    self.configurationCenterDetail(item, list: self.configurationCenterLatestList ?? list, hadRecipe: hadRecipe)
                                }
                            }
                        }
                    }
                    .onAppear { [weak self] in self?.configurationCenterShownItem = item }
                    .onDisappear { [weak self] in
                        if self?.configurationCenterShownItem == item { self?.configurationCenterShownItem = nil }
                    }
                     
                     
                     
                     
                     
                     
                     
                    .modifier(ClashMacCentrePresentations(model: self, actions: actions))
                )
    }

     
     
     
    fileprivate func chainSheet(_ request: ClashMacChainRequest) -> some View {
        let existing = request.existingID.flatMap { id in configurationLibrary.snapshot.sources.first { $0.id == id } }
        return ClashMacChainSheet(
            existing: existing,
            actions: chainSheetActions(existing: existing),
            close: { [weak self] in self?.configurationCenterChain = nil }
        )
    }

     
    fileprivate func ruleEditorSheet(_ selection: ClashMacLibrarySelection) -> some View {
        loadEditorSyntaxOnce()
        return ClashMacRuleEditorSheet(
            actions: ruleEditorActions(schemeID: selection.id),
            initialPane: selection.pane,
            saved: { [weak self] in Task { await self?.configurationLibrary.reload() } }
        )
         
         
        .environment(
            \.clashGroupIconImages,
            (ClashProxiesDisplayPreferences.uiTestOverride() ?? ClashProxiesDisplayPreferences.load()).groupIconImages
        )
        .environment(\.clashMacEditorSyntax, editorSyntax)
    }

     
     
     
     
     
     
     
     
    func requestNewConfiguration() {
        navigationRequest = .profiles
        configurationCenterSegment = .configurations
        configurationCenterWindowSheet = .wizard
    }

     
     
     
    func requestAddSource(purpose: ClashMacSourceImportPurpose) {
        navigationRequest = .profiles
        configurationCenterSegment = purpose == .rules ? .rules : .nodes
        configurationCenterWindowSheet = .importing(ClashMacImportRequest(purpose: purpose))
    }

     
    private func installFeedback() {
         
         
        guard feedbackFailures == nil else { return }
        feedback.locale = preferences.language.locale
        feedbackLocale = preferences.$language.sink { [weak self] language in self?.feedback.locale = language.locale }
        configurationLibrary.feedback = feedback
         
         
         
         
         
        feedbackFailures = profiles.$lastFailure.dropFirst().sink { [weak self] failure in
            if let failure { self?.sayProfilesFailure(failure) }
        }
    }

    private func sayProfilesFailure(_ failure: ConfigurationFailure) {
        let shaped = ProfileSwitchAlertFailure(failure, locale: preferences.language.locale)
        let retries: Bool = failure.recoveryActions.contains(ConfigurationRecoveryAction.retry)
        let action: ClashFeedbackPresentation.Action? = retries ? ClashFeedbackPresentation.Action.retry : nil
        let result = ClashFeedbackPresentation.error(
            title: .verbatim(shaped.titleText),
            message: .verbatim(shaped.messageText),
            action: action,
            accessibilityIdentifier: "feedback.profiles.failure"
        )
        var retry: (() -> Void)?
        if retries {
            retry = { [weak self] in self?.profiles.retryLastFailure() }
        }
         
         
         
         
        feedback.say(result, operation: "profiles.failure", perform: retry,
                     onDismiss: { [weak self] in
                         if self?.profiles.lastFailure == failure { self?.profiles.dismissFailure() }
                     })
    }

     
     
     
    func deleteUndoably(_ item: ClashMacConfigurationCenterItem) async {
        let library = configurationLibrary
        let label: String
        let segment: ClashMacConfigurationCenterSegment
        let removal: ClashMacLibraryDeletion?
        let itemID: String
        switch item {
        case .source(let id):
            itemID = id
            label = library.snapshot.sources.first { $0.id == id }.map { $0.displayLabel(locale: preferences.language.locale) } ?? id
            segment = .nodes
            removal = library.deletesUndoably ? await library.deleteSourceRestorably(id) : nil
            if !library.deletesUndoably, await library.deleteSource(id) { return }
        case .scheme(let id):
            itemID = id
            label = library.snapshot.rules.first { $0.id == id }?.label ?? id
            segment = .rules
            removal = library.deletesUndoably ? await library.deleteRuleSchemeRestorably(id) : nil
            if !library.deletesUndoably, await library.deleteRuleScheme(id) { return }
        default:
            return
        }
        guard let removal else {
            feedback.say(ClashMacFeedbackSentences.couldNotDelete(label, reason: library.lastError ?? "", id: "library.delete"),
                          operation: "library.delete." + itemID)
            return
        }
        offerUndo(of: label, operation: "library.delete." + itemID) { [weak self] in
            guard let self else { return .failed("") }
            switch await self.configurationLibrary.restore(removal) {
            case .restored:
                 
                self.navigationRequest = .profiles
                self.configurationCenterSegment = segment
                return .restored
            case .superseded(let reason): return .superseded(reason)
            case .failed(let reason): return .failed(reason)
            }
        }
    }

     
     
     
     
     
    func offerUndo(of label: String, operation: String, undo: @escaping @MainActor () async -> ClashMacUndoAnswer) {
        let token = ClashMacUndoToken(label: label, operation: operation, undo: undo)
        undoTokens.insert(token)
        token.resultID = feedback.say(ClashMacFeedbackSentences.deleted(label, undoable: true, id: operation),
                                      operation: operation, perform: { [weak self] in self?.answerUndo(token) })
        registerUndo(token)
        Task { @MainActor [weak self] in
             
            try? await Task.sleep(nanoseconds: 600 * 1_000_000_000)
            self?.retireUndo(token)
        }
    }

    private func registerUndo(_ token: ClashMacUndoToken) {
        guard let undoManager = mainWindow?.undoManager else { return }
        undoManager.registerUndo(withTarget: token) { [weak self] token in
            if let id = token.resultID { self?.feedback.dismiss(id) }
            self?.answerUndo(token)
        }
        undoManager.setActionName(ClashFeedbackCopy.deleteActionName(token.label).resolved(locale: preferences.language.locale))
    }

     
     
    private func retireUndo(_ token: ClashMacUndoToken) {
        mainWindow?.undoManager?.removeAllActions(withTarget: token)
        undoTokens.remove(token)
    }

    private func answerUndo(_ token: ClashMacUndoToken) {
        guard !token.used else { return }
        token.used = true
        mainWindow?.undoManager?.removeAllActions(withTarget: token)
        Task { @MainActor in
            var answer = await token.undo()
            if case .failed = answer {
                 
                try? await Task.sleep(nanoseconds: 700_000_000)
                answer = await token.undo()
            }
            switch answer {
            case .restored:
                self.retireUndo(token)
                self.feedback.say(ClashMacFeedbackSentences.restored(token.label, id: token.operation), operation: token.operation)
            case .superseded(let reason):
                self.retireUndo(token)
                self.feedback.say(.error(title: ClashFeedbackCopy.couldNotUndo, message: reason.isEmpty ? nil : .copy(reason),
                                         accessibilityIdentifier: "feedback.undo-failed"),
                                  operation: token.operation)
            case .failed(let reason):
                token.used = false
                token.resultID = self.feedback.say(
                    .error(title: ClashFeedbackCopy.couldNotUndo, message: reason.isEmpty ? nil : .verbatim(reason), action: .retry,
                           accessibilityIdentifier: "feedback.undo-failed"),
                    operation: token.operation, perform: { [weak self] in self?.answerUndo(token) })
                self.registerUndo(token)
            }
        }
    }

     
    func requestConfigurationCenter(_ segment: ClashMacConfigurationCenterSegment) {
        navigationRequest = .profiles
        configurationCenterSegment = segment
    }

    private func configurationCenterListActions(_ list: ClashProfilesListPresentation) -> ClashMacConfigurationCenterListActions {
        var actions = ClashMacConfigurationCenterListActions(
             
            addConfiguration: { [weak self] in self?.showsConfigurationWizard = true },
            addSource: { [weak self] tab in self?.configurationCenterImport = ClashMacImportRequest(purpose: .nodes, tab: tab) },
            addScheme: { [weak self] tab in self?.configurationCenterImport = ClashMacImportRequest(purpose: .rules, tab: tab) },
            activate: { id in list.select(id) },
            delete: { [weak self] item in
                guard let self else { return }
                switch item {
                case .configuration(let id): list.perform(.delete(id: id))
                case .source, .scheme: Task { await self.deleteUndoably(item) }
                case .collection: break
                }
            }
        )
        actions.editScheme = { [weak self] id in self?.configurationCenterEditingScheme = ClashMacLibrarySelection(id: id) }
        actions.addChain = { [weak self] in self?.configurationCenterChain = ClashMacChainRequest(existingID: nil) }
        actions.createNode = { [weak self] in self?.configurationCenterCreatesNode = true }
         
        actions.reorder = { ids in list.reorder(ids) }
         
        actions.updateConfiguration = { [weak self] id in self?.updateConfigurationSources(id.rawValue) }
        actions.copyProfileURL = { [weak self] id in
             
             
            guard let self, self.copyProfileURL(of: id.rawValue) else { return }
            self.feedback.say(ClashMacFeedbackSentences.copied("Profile URL", id: "configuration.copy-link"),
                               operation: "configuration.copy-link")
        }
         
        actions.copySourceLink = { [weak self] id in
            guard let self,
                  let source = self.configurationLibrary.snapshot.sources.first(where: { $0.id == id }),
                  let link = ClashMacConfigurationLibraryModel.link(of: source) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link, forType: .string)
            self.feedback.say(ClashMacFeedbackSentences.copied("Link", id: "configuration-center.copy-link"),
                               operation: "configuration-center.copy-link")
        }
        actions.hasProfileURL = { [weak self] id in self?.profileURL(of: id.rawValue) != nil }
        actions.hasLegacyProfileURLs = profiles.profiles.contains { profile in if case .url = profile.source { return true }; return false }
         
        actions.statusMessage = profiles.statusMessage
        actions.failure = profiles.lastFailure.map { (message: .verbatim($0.message), canRetry: true) }
        actions.retryFailure = { list.perform(.retryFailure) }
         
        actions.backupPage = { AnyView(BackupRestoreView().navigationTitle(Text(clash: .copy("Backup & Restore")))) }
         
         
        actions.modulesPage = { [weak self] in
            AnyView(ModulePageHost(model: ModulePageModel.shared, noticePlaces: self?.modulesNoticePlaces))
        }
        actions.modulesValue = ModulePageModel.shared.entrySource.entry?.value ?? "Off"
        return actions
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func liveProfile(
        _ listed: ClashProfileSnapshot,
        appProfile: Profile?,
        in snapshot: ConfigurationLibrarySnapshot
    ) -> ClashProfileSnapshot {
        var profile = listed
        guard let appProfile,
              let facts = ProfileCenterView.libraryFacts(for: appProfile, in: snapshot)
        else { return profile }
        profile.lastUpdatedAt = facts.lastUpdatedAt
         
         
        profile.sourceSummary = ProfileCenterView.sourceSummary(
            appProfile, updatedAt: facts.lastUpdatedAt, locale: .current
        )
        profile.subscription = facts.usage.map {
            ProfileCenterView.subscriptionSnapshot(
                upload: $0.upload, download: $0.download, total: $0.total, expire: $0.expire
            )
        }
        return profile
    }

    @ViewBuilder
    private func configurationCenterDetail(
        _ item: ClashMacConfigurationCenterItem, list: ClashProfilesListPresentation, hadRecipe: Bool = false
    ) -> some View {
        let snapshot = configurationLibrary.snapshot
        switch item {
        case .configuration(let id):
            if let listed = list.profiles.first(where: { $0.id == id }) {
                let appProfile = profiles.profiles.first { $0.id == id.rawValue }
                let recipe = snapshot.recipes.first { $0.id == id.rawValue }
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                let profile = Self.liveProfile(
                    listed, appProfile: appProfile, in: snapshot
                )
                let sources = snapshot.sources.filter(\.suppliesNodes)
                 
                 
                let shelves = ClashMacConfigurationLibraryModel.ruleShelves(snapshot, keeping: recipe?.ruleSchemeID)
                let profileURL = appProfile.flatMap { if case .url(let url) = $0.source { url } else { nil } }
                let actions = configurationInspectorActions(list, profile: profile, id: id)
                let outlineScheme = Self.outlineScheme(snapshot, profileID: id.rawValue)
                let schemeUsage = Self.schemeUsage(snapshot)
                let schemeChoices = Self.schemeChoices(snapshot, for: recipe)
                 
                 
                let followedLinks = Self.followedLinks(snapshot, schemes: schemeChoices)
                let scripts = scriptsActions(profileID: id)
                 
                 
                 
                 
                 
                ClashMacUnchangedPage(key: ClashMacConfigurationPageKey(
                    profile: profile, sources: sources, shelves: shelves, recipe: recipe, profileURL: profileURL,
                    outlineScheme: outlineScheme, schemeUsage: schemeUsage, schemeChoices: schemeChoices,
                    generation: snapshot.generation, isUpdatingSource: actions.isUpdatingSource,
                    updateError: actions.updateError, edits: actions.saveLibraryLink != nil,
                    linkSharedBy: actions.libraryLinkSharedBy
                )) {
                ClashMacConfigurationInspector(
                    profile: profile,
                    sources: sources,
                    ruleShelves: shelves,
                    recipe: recipe,
                    scriptsActions: scripts,
                    scriptsQuickAdd: { [weak self] reload in
                        AnyView(self?.scriptsQuickAddCard(profileID: id, reload: reload))
                    },
                    profileURL: profileURL,
                    actions: actions,
                    door: { [weak self] door in AnyView(self?.configurationDoor(door, profileID: id, list: list)) },
                    outlineScheme: outlineScheme,
                    schemeUsage: schemeUsage,
                    followedLinks: followedLinks,
                    schemeChoices: schemeChoices,
                    libraryGeneration: snapshot.generation,
                    updateFollowing: snapshot.updateFollowing(ofRecipe: id.rawValue),
                    linksToRejoin: snapshot.linksToRejoin(ofRecipe: id.rawValue)
                )
                }
                .equatable()
                .id(id)
                .navigationTitle(Text(verbatim: profile.label))
                 
                 
                 
                 
                 
                 
                .clashMacPopsWhenGone(!profiles.profiles.contains { $0.id == id.rawValue }
                    || (hadRecipe && !snapshot.recipes.contains { $0.id == id.rawValue }))
            }
        case .source(let sourceID):
            if let source = snapshot.sources.first(where: { $0.id == sourceID }) {
                sourcePage(source, list: list)
                    .id(sourceID)
                    .navigationTitle(Text(clash: ClashConfigurationSourceCopy.name(source)))
                    .clashMacPopsWhenGone(!snapshot.sources.contains { $0.id == sourceID })
            }
        case .scheme(let schemeID):
            if let scheme = configurationLibrary.ruleShelves.flatMap(\.schemes).first(where: { $0.id == schemeID }) {
                schemePane(scheme, schemeID: schemeID, snapshot: snapshot, list: list)
                .id(schemeID)
                .navigationTitle(Text(verbatim: scheme.displayLabel))
                .clashMacPopsWhenGone(!configurationLibrary.ruleShelves.flatMap(\.schemes).contains { $0.id == schemeID })
            }
        case .collection(let collectionID):
            if let entry = configurationLibrary.collections.first(where: { $0.id == collectionID }) {
                 
                ClashMacCollectionPane(collection: entry.collection, sourceLabel: entry.source.displayLabel(locale: locale), actions: collectionPageActions(entry))
                    .navigationTitle(Text(verbatim: entry.collection.name))
                    .clashMacPopsWhenGone(!configurationLibrary.collections.contains { $0.id == collectionID })
            }
        }
    }

     
     
    private func schemePane(
        _ scheme: ConfigurationRuleScheme, schemeID: String, snapshot: ConfigurationLibrarySnapshot, list: ClashProfilesListPresentation
    ) -> ClashMacSchemePane {
        let readers = configurationLibrary.configurations(usingScheme: schemeID)
        var pane = ClashMacSchemePane(
            scheme: scheme,
             
             
             
            source: snapshot.sources.first { $0.id == scheme.sourceID }
                ?? (ConfigurationBuiltins.isNative(scheme.id) ? (try? ConfigurationBuiltins.source(for: scheme.id))?.record : nil),
            usedBy: list.profiles.filter { readers.contains($0.id.rawValue) },
            actions: ClashMacSchemePaneActions(
                edit: { [weak self] in self?.configurationCenterEditingScheme = ClashMacLibrarySelection(id: schemeID) },
                 
                 
                duplicate: { [weak self] in
                    guard let self else { throw ConfigurationLibraryError.unreadable }
                    let label = ClashCopy.string("Copy", locale: self.preferences.language.locale) + " · " + scheme.displayLabel
                    return try await self.configurationLibrary.copyScheme(schemeID, label: label)
                },
                update: { [weak self] in
                    guard let self else { throw ConfigurationLibraryError.unreadable }
                     
                     
                     
                    let version = { self.configurationLibrary.snapshot.sources.first { $0.id == scheme.sourceID }?.version }
                    let before = version()
                    guard await self.configurationLibrary.updateSource(scheme.sourceID) else {
                        throw ClashMacUpdateFailure(message: self.configurationLibrary.updateFailures[scheme.sourceID]
                            ?? ClashErrorCopy.message(ConfigurationLibraryError.unreadable, locale: Locale.current))
                    }
                    return version() != before
                },
                delete: { [weak self] in self?.configurationCenterPendingDelete = .scheme(schemeID) },
                load: { [weak self] in
                    guard let self else { throw ConfigurationLibraryError.unreadable }
                    return try await self.ruleEditorActions(schemeID: schemeID).load()
                },
                page: { [weak self] id in
                    guard let self else { return AnyView(EmptyView()) }
                    return self.configurationCenterRoutedDetail(.scheme(id), list: self.configurationCenterLatestList ?? list, actions: self.configurationCenterListActions(list))
                },
                editAt: { [weak self] pane in self?.configurationCenterEditingScheme = ClashMacLibrarySelection(id: schemeID, pane: pane) }
            ).renaming { [weak self] name in
                guard let self else { throw ConfigurationLibraryError.unreadable }
                self.configurationLibrary.apply(try await self.profiles.renameConfigurationRuleScheme(schemeID, label: name))
            }.waitingOutUpdateAll { [profiles] waiting in
                 
                guard profiles.isUpdatingNodeLibrary || profiles.isUpdatingRuleCollections else { return }
                waiting()
                await profiles.waitForNodeLibraryUpdate()
                await profiles.waitForRuleCollectionUpdate()
            }
        )
        pane.updateError = configurationLibrary.updateFailures[scheme.sourceID]
        return pane
    }

     
     
    static func outlineScheme(_ snapshot: ConfigurationLibrarySnapshot, profileID: String) -> ClashMacOutlineScheme? {
        ClashMacOutlineScheme.of(snapshot, profileID: profileID)
    }

     
     
     
     
     
     
     
    private func keyOwners(
        for section: ConfigurationOutlineSection, original: Bool,
        profileID: ClashClientKit.Profile.ID, list: ClashProfilesListPresentation
    ) -> [String: ClashMacKeyOwner] {
        func go(_ title: ClashDisplayText, _ destination: ClashMacSecondaryDestination) -> ClashMacKeyOwner {
            ClashMacKeyOwner(title: title, open: { [weak self] in self?.navigationRequest = destination })
        }
         
         
         
        var owners: [String: ClashMacKeyOwner] = [:]
        if section == .general, original {
            owners["tls"] = ClashMacKeyOwner(title: .copy("Certificates & Trust"), push: { [weak self] in
                AnyView(self?.configurationDoor(.trust, profileID: profileID, list: list))
            })
        }
         
         
         
        if section == .inbound {
            let routes = ClashMacKeyOwner(title: .copy("Tunnel & Routes"), push: { [weak self] in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(GoldenFlowMoreDestinationAdapter(
                    vpn: self.vpn, command: self.command, preferences: self.preferences,
                    destination: .tunnelAndRoutes, usesRegularDetailLayout: true, profileID: profileID.rawValue
                ))
            })
            for key in ["route-address", "route-exclude-address", "route-address-set", "route-exclude-address-set",
                        "inet6-address", "loopback-address", "strict-route", "endpoint-independent-nat",
                        "udp-timeout", "icmp-timeout"] {
                owners["tun." + key] = routes
            }
        }
        return owners
    }

     
    private func pageOwners(profileID: ClashClientKit.Profile.ID, list: ClashProfilesListPresentation) -> [ConfigurationKeyOwner: ClashMacKeyOwner] {
        func go(_ title: ClashDisplayText, _ destination: ClashMacSecondaryDestination) -> ClashMacKeyOwner {
            ClashMacKeyOwner(title: title, open: { [weak self] in self?.navigationRequest = destination })
        }
        var owners: [ConfigurationKeyOwner: ClashMacKeyOwner] = [:]
        for owner in ConfigurationKeyOwner.allCases {
            switch owner {
            case .lanSharing: owners[owner] = go(.copy("LAN Proxy Share"), .utility(.proxyShare))
            case .clientSettings: owners[owner] = go(.copy("Client Settings"), .more(.clientSettings))
            case .certificatesAndTrust:
                owners[owner] = ClashMacKeyOwner(title: .copy("Certificates & Trust"), push: { [weak self] in
                    AnyView(self?.configurationDoor(.trust, profileID: profileID, list: list))
                })
            case .tunnelAndRoutes:
                owners[owner] = ClashMacKeyOwner(title: .copy("Tunnel & Routes"), push: { [weak self] in
                    guard let self else { return AnyView(EmptyView()) }
                    return AnyView(GoldenFlowMoreDestinationAdapter(
                        vpn: self.vpn, command: self.command, preferences: self.preferences,
                        destination: .tunnelAndRoutes, usesRegularDetailLayout: true, profileID: profileID.rawValue
                    ))
                })
            }
        }
        return owners
    }

     
    static func macLayout(_ layout: ConfigurationSectionLayout, owners: [ConfigurationKeyOwner: ClashMacKeyOwner]) -> ClashMacSectionLayout {
        func macRow(_ row: ConfigurationSectionLayout.Row) -> ClashMacSectionLayout.Row {
            let control: ClashMacSectionLayout.Control
            switch row.control {
            case .inline: control = .inline
            case .page: control = .page
            case .drill: control = .drill
            case .platform(let reason): control = .platform(reason)
            case .owned(let owner): control = owners[owner].map { .owned($0) } ?? .page
            }
            return ClashMacSectionLayout.Row(key: row.key, path: row.path, field: row.field, value: row.value,
                                            control: control, conditionalEffective: row.conditionalEffective)
        }
        return ClashMacSectionLayout(groups: layout.groups.map { group in
            let title: ClashDisplayText? = {
                switch group.title {
                case .none: return nil
                case .copy(let key): return .copy(key)
                case .key(let key): return .verbatim(key)
                case .words(let words): return .verbatim(words)
                }
            }()
            return ClashMacSectionLayout.Group(id: group.id, title: title, rows: group.rows.map(macRow), footer: group.footer)
        },
         
         
        platformDecided: layout.platformDecided.map(macRow))
    }

     
     
    static func followedLinks(_ snapshot: ConfigurationLibrarySnapshot, schemes: [ConfigurationRuleScheme]) -> [String: String] {
        var links: [String: String] = [:]
        for scheme in schemes { if let label = snapshot.followedLinkLabel(ofScheme: scheme.id) { links[scheme.id] = label } }
        return links
    }

    static func schemeUsage(_ snapshot: ConfigurationLibrarySnapshot) -> [String: Int] {
        ClashMacOutlineScheme.usage(snapshot)
    }

     
     
     
     
    private func outlineDestination(
        _ section: ConfigurationOutlineSection, profileID: ClashClientKit.Profile.ID
    ) -> ClashMacOutlineDestination? {
        func settings(_ destination: AppNavigationDestination.MoreDestination) -> ClashMacOutlineDestination {
            .page { [weak self] in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(GoldenFlowMoreDestinationAdapter(
                    vpn: self.vpn, command: self.command, preferences: self.preferences,
                    destination: destination, usesRegularDetailLayout: true, profileID: profileID.rawValue
                ))
            }
        }
         
         
         
         
         
        func editor(_ pane: ClashMacRuleEditorSheet.Pane) -> ClashMacOutlineDestination? {
            let recipe = configurationLibrary.snapshot.recipes.first(where: { $0.id == profileID.rawValue })
            guard let recipe, recipe.preservesOriginal != true else {
                 
                 
                return .page { [weak self] in
                    guard let self else { return AnyView(EmptyView()) }
                    return AnyView(
                        ClashMacRuleEditorSheet(
                            actions: self.originalRuleEditorActions(profileID: profileID.rawValue),
                            initialPane: pane,
                            presentation: .page
                        )
                        .environment(\.clashMacEditorSyntax, self.editorSyntax)
                    )
                }
            }
            let scheme = recipe.ruleSchemeID
            loadEditorSyntaxOnce()
            return .page { [weak self] in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(
                    ClashMacRuleEditorSheet(
                        actions: self.ruleEditorActions(schemeID: scheme, profileID: profileID.rawValue),
                        initialPane: pane,
                        presentation: .page
                    )
                    .environment(
                        \.clashGroupIconImages,
                        (ClashProxiesDisplayPreferences.uiTestOverride() ?? ClashProxiesDisplayPreferences.load()).groupIconImages
                    )
                    .environment(\.clashMacEditorSyntax, self.editorSyntax)
                )
            }
        }
         
         
         
         
        func configurationPage(_ build: @escaping @MainActor (Profile) -> AnyView) -> ClashMacOutlineDestination {
            .page { [weak self] in
                guard let self, let profile = self.profiles.profiles.first(where: { $0.id == profileID.rawValue }) else {
                    return AnyView(EmptyView())
                }
                return build(profile)
            }
        }
        let profiles = self.profiles
        switch section {
         
         
        case .dns:
            return configurationPage { profile in
                AnyView(CurrentConfigurationSettingsHost(profiles: profiles, profile: profile) { settings, reread in
                    ProfileProjectionLoader(profile: profile, model: profiles) { projected in
                        ProfileDNSSettingsAdapter(profile: settings.profile, sourceYAML: projected,
                                                  saveHosts: {
                                                      try await profiles.updateHosts($0, readAs: settings)
                                                      await reread()
                                                  },
                                                  ownsNavigationContainer: false, configurationScope: settings.dnsScope) {
                            try await profiles.updateDNS($0, readAs: settings)
                            await reread()
                        }
                    }
                })
            }
         
        case .inbound: return settings(.tunnelAndRoutes)
        case .proxyGroups: return editor(.groups)
        case .rules: return editor(.rules)
        case .ruleProviders: return editor(.ruleSets)
         
         
         
         
         
        case .proxies:
            let recipe = configurationLibrary.snapshot.recipes.first(where: { $0.id == profileID.rawValue })
            guard recipe?.preservesOriginal ?? true else { return nil }
            return .page { [weak self] in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(ClashMacOriginalNodesPage(actions: self.originalNodesActions(profileID: profileID.rawValue)))
            }
         
         
         
         
        case .proxyProviders:
            let recipe = configurationLibrary.snapshot.recipes.first(where: { $0.id == profileID.rawValue })
            guard recipe?.preservesOriginal ?? true else { return nil }
            return .page { [weak self] in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(ClashMacOriginalProvidersPage(actions: self.originalProvidersActions(profileID: profileID)))
            }
        case .subRules: return editor(.subRules)
        default: return nil
        }
    }

     
     
     
     
    private func settingsSectionActions(
        id: ClashClientKit.Profile.ID, list: ClashProfilesListPresentation?
    ) -> ClashMacSettingsSectionActions {
        let profiles = self.profiles
        let library = configurationLibrary
         
         
         
         
        var settings = ClashMacSettingsSectionActions(
            load: { [weak self] section in
                let page = try await profiles.loadConfigurationEditorPage(profileID: id.rawValue)
                self?.modulesListenerKeys = await profiles.publishedModules()?.listenerKeys ?? KernelLANShareOverride()
                let catalog = try? await ProfilesViewModel.loadSyntaxCatalog()
                var scheme: String?
                var scope: ClashDisplayText?
                var original = false
                switch page.form {
                case .composed(let running, let ownership):
                    if page.ownLayer == nil { scheme = running.id }
                    scope = ClashMacSettingsSectionDocument.scope(running: running, ownership: ownership, ownLayer: page.ownLayer != nil)
                case .original:
                    original = true
                    scope = ClashMacSettingsSectionDocument.scope(running: nil, ownership: .original, ownLayer: false)
                }
                var choices: [String: [String]] = [:]
                if let modes = catalog?.dnsEnhancedModes { choices["dns.enhanced-mode"] = modes }
                var document = ClashMacSettingsSectionDocument(
                    page: page.document, ownLayer: page.ownLayer, scheme: scheme, scope: scope,
                    elsewhere: [],
                     
                     
                     
                     
                     
                    platformReasons: Dictionary((catalog?.platformDecidedKeys ?? []).filter(\.overridesTheFile).map { ($0.path, $0.reason) },
                                                uniquingKeysWith: { first, _ in first }),
                    choices: choices,
                    catalog: catalog?.fieldCatalog
                )
                document.platformKeysKnown = catalog?.platformDecidedKeys != nil
                document.catalogVersion = catalog?.schemaVersion ?? 0
                document.ownDNSSwitch = page.ownDNSSwitch
                 
                 
                 
                document.activeConditions.formUnion(profiles.platformConditionsHolding())
                document.owners = list.flatMap { self?.keyOwners(for: section, original: original, profileID: id, list: $0) } ?? [:]
                 
                 
                let running = document.running
                let conditions = profiles.platformConditionsHolding()
                let pageOwners = list.flatMap { self?.pageOwners(profileID: id, list: $0) } ?? [:]
                 
                 
                let locale = self?.preferences.language.locale ?? .current
                document.layout = { basePath in
                    Self.macLayout(ConfigurationSectionLayout.make(
                        section: section, basePath: basePath, document: running, catalog: catalog,
                        original: original, conditions: conditions
                    ).arranged(by: .shared, locale: locale, catalog: catalog, document: running), owners: pageOwners)
                }
                return document
            },
            save: { edits, scheme in
                try await profiles.editConfigurationSettings(id.rawValue, edits: edits, readScheme: scheme)
                await library.reload()
            }
        )
        settings.setOwnDNSSwitch = { on in try profiles.updateOwnDNSSwitch(profileID: id.rawValue, on: on) }
         
         
         
        settings.runsOver = { [weak self] in
            async let modules = profiles.publishedModules()
            async let scripted = profiles.scriptedSettings(profileID: id.rawValue)
            let (published, built) = await (modules, scripted)
            guard published != nil || built != nil else { return nil }
            let held = profiles.keysHeldOverModules(profileID: id.rawValue)
            let locale = self?.preferences.language.locale ?? .current
            return { path, field, opensPage, running in
                ConfigurationRunsOverNote.words(path: path, field: field, opensPage: opensPage, document: running,
                                                modules: published, held: held, scripted: built, locale: locale)
            }
        }
         
         
         
         
         
         
         
         
         
        settings.generalOverrides = { [weak self] in
            guard let self else { return nil }
            let mode = profiles.outboundModeSetOnHome()
            let level = profiles.logLevelForcedByLogSettings()
            guard mode != nil || level != nil else { return nil }
            return ClashMacGeneralOverrides(
                outboundMode: mode.map { ClashGeneralOverrideNote.outboundModeSetOnHome(ConfigurationOutboundModeWords.title($0)) },
                logLevel: level.map(ClashGeneralOverrideNote.logLevelForcedByLogSettings),
                followConfiguration: mode == nil ? nil : { [weak self] in
                    guard let self else { return }
                    do { try profiles.followConfigurationOutboundMode() } catch {
                        self.feedback.say(ClashFeedbackPresentation.error(
                            title: .copy("The configuration's own mode did not come back."),
                            message: ClashErrorCopy.text(error),
                            accessibilityIdentifier: "feedback.general.follow-configuration.failure"
                        ), operation: "general.follow-configuration")
                    }
                }
            )
        }
         
         
         
         
         
         
         
         
         
         
        settings.generalOverridesChanged = Publishers.MergeMany(
            NotificationCenter.default.publisher(for: ProfileStore.didChangeNotification).map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: GlobalConfig.didChangeNotification).map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
        .eraseToAnyPublisher()
         
         
        settings.geoValues = { resource in
            await GeoCategoryCache.shared.categories(for: resource == .geoIP ? .geoip : .geosite)
        }
         
         
         
         
        settings.turnOff = { path in
            let page = try await profiles.loadConfigurationEditorPage(profileID: id.rawValue)
            switch ConfigurationListenOff.of(path: path, page: page) {
            case .remove?: return .edits([.remove(path: path)])
            case .writeEmpty?: return .edits([.set(path: path, to: .string(""))])
            case .fileText?:
                try await profiles.editingOriginalOffItsLink(id.rawValue) {
                    try await profiles.editOriginalConfiguration(id.rawValue, at: path.map(ConfigurationTextPathStep.key), .delete,
                                                                 readDigest: page.readDigest) }
                await library.reload()
                return .written
            case .layerAndFileText?:
                try await profiles.editingOriginalOffItsLink(id.rawValue) {
                    try await profiles.deleteInOriginalConfiguration(id.rawValue, at: path, readDigest: page.readDigest) }
                await library.reload()
                return .written
            case nil: return .nothing
            }
        }
         
         
        settings.lanShare = lanShareEntry(id: id)
        return settings
    }

     
     
     
    private func lanShareEntry(id: ClashClientKit.Profile.ID) -> ClashMacLANShareEntry {
        let profiles = self.profiles
        return ClashMacLANShareEntry(
            keys: ConfigurationSectionKeys.lanShareKeys,
            status: { [weak self] document in
                let override = profiles.profiles.first { $0.id == id.rawValue }
                    .map { KernelLANShareOverride(patch: OverridePatch(patchJSON: $0.override.patchJSON)) }
                 
                 
                return ConfigurationLANShareStatus.words(override: override ?? KernelLANShareOverride(), document: document,
                                                         modules: self?.modulesListenerKeys ?? KernelLANShareOverride())
            },
            page: { [weak self] in self?.lanSharePage(profileID: id) ?? AnyView(EmptyView()) }
        )
    }

     
     
     
     
     
     
     
     
     
    private func lanSharePage(profileID id: ClashClientKit.Profile.ID) -> AnyView {
        AnyView(ClashMacLANSharePage(profiles: profiles, proxyShare: proxyShare, profileID: id.rawValue,
                                    rows: ProxyShareSettingsRows(from: self, profileID: id.rawValue,
                                                                 rows: lanShareSettingsRows(id: id))))
    }

     
     
     
    private var activeLANShareSettingsRows: ProxyShareSettingsRows? {
        ProxyShareSettingsRows(from: self) { [weak self] keys, saysScope in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(ClashMacActiveLANShareRows(profiles: self.profiles) { [weak self] id in
                self?.lanShareSettingsRows(id: id)(keys, saysScope) ?? AnyView(EmptyView())
            })
        }
    }

     
     
     
     
     
     
     
     
     
     
    fileprivate var modulesNoticePlaces: ClashModulesNoticePlaces {
        ClashModulesNoticePlaces(
            offers: { [weak self] place in self?.offersModulesNoticePlace(place) ?? false },
            page: { [weak self] place in
                 
                 
                 
                 
                guard let self, self.offersModulesNoticePlace(place) else { return AnyView(ClashOpeningCancelButton()) }
                switch place {
                case .snifferSettings(let raw):
                    guard let id = ClashMacModulesNotice.profileID(raw, in: self.profiles.profiles) else {
                        return AnyView(ClashOpeningCancelButton())
                    }
                    return AnyView(ClashMacModulesNoticePage(section: .sniffer) { [weak self] in
                        self?.settingsSectionActions(id: id, list: nil)
                    })
                }
            }
        )
    }

     
     
     
    private func offersModulesNoticePlace(_ place: ClashModulesSnapshot.NoticePlace) -> Bool {
        let profiles = self.profiles
        return ModulePageHost.offers(place, activeProfileID: profiles.activeProfileID,
                                     exists: { ClashMacModulesNotice.profileID($0, in: profiles.profiles) != nil })
    }

     
    private func lanShareSettingsRows(id: ClashClientKit.Profile.ID) -> ([String], Bool) -> AnyView {
        { [weak self] keys, saysScope in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(ClashMacSettingsKeyRows(keys: keys, saysScope: saysScope,
                                                   actions: self.settingsSectionActions(id: id, list: nil)).id(id.rawValue))
        }
    }

    private func configurationInspectorActions(
        _ list: ClashProfilesListPresentation, profile: ClashProfileSnapshot, id: ClashClientKit.Profile.ID
    ) -> ClashMacConfigurationInspectorActions {
        let profiles = self.profiles
        let library = configurationLibrary
        let writes = configurationWrites
         
         
         
         
         
         
        func editNow(_ change: (inout ConfigurationCreationDraft) -> Void) async throws {
             
             
             
            let cached = library.snapshot.generation
            await library.reload()
            let snapshot = library.snapshot
            guard let recipe = snapshot.recipes.first(where: { $0.id == id.rawValue }) else {
                ClashMacDebugLog.note("edit \(id.rawValue): no recipe at generation \(snapshot.generation) — nothing written")
                return
            }
            var draft = ConfigurationCreationAdapter.editingDraft(recipe: recipe, label: profile.label)
            change(&draft)
            ClashMacDebugLog.note("edit \(id.rawValue): generation cached \(cached) fresh \(snapshot.generation) recipe \(recipe.sources.map(\.id)) → sources \(draft.selectedSourceIDs) rule \(draft.selectedRuleID)")
            try await profiles.editConfiguration(draft, id: id.rawValue, generation: snapshot.generation)
            await library.reload()
            let after = library.snapshot
            ClashMacDebugLog.note("edit \(id.rawValue): written, generation \(after.generation) recipe \(after.recipes.first { $0.id == id.rawValue }?.sources.map(\.id) ?? [])")
        }
         
         
         
         
        let failed: @MainActor (Error) -> Void = { [weak self] error in
            NSLog("configuration-centre.edit-failed:%@", error.localizedDescription)
            ClashMacDebugLog.note("edit \(id.rawValue): REFUSED \(error) — \(error.localizedDescription)")
            library.report(ClashErrorCopy.message(error, locale: Locale.current))
             
             
            self?.feedback.say(ClashMacFeedbackSentences.couldNotSave(reason: ClashErrorCopy.message(error, locale: Locale.current),
                                                                       id: "configuration.edit"),
                                operation: "configuration.edit")
            Task { @MainActor in await library.reload() }
        }
         
         
         
        func edit(_ change: @escaping (inout ConfigurationCreationDraft) -> Void) {
            writes.enqueue({
                if library.snapshot.recipes.contains(where: { $0.id == id.rawValue }) {
                    try await editNow(change)
                } else {
                    try await convertLegacyNow(sources: nil, scheme: nil, change: change)
                }
            }, failure: failed)
        }
         
         
         
         
         
        func saveProfileURL(_ change: @escaping (inout ClashMacSubscriptionSettingsState) -> Void) async throws {
            do {
                try await writes.run {
                    guard let appProfile = profiles.profiles.first(where: { $0.id == id.rawValue }) else { return }
                    var state = Self.subscriptionState(appProfile)
                    change(&state)
                    ClashMacDebugLog.note("profile-url \(id.rawValue): save autoUpdate \(state.autoUpdate) interval \(state.updateIntervalHours)")
                    let saved = try await self.subscriptionActions(profileID: id).save(state)
                    ClashMacDebugLog.note("profile-url \(id.rawValue): saved autoUpdate \(saved.autoUpdate) interval \(saved.updateIntervalHours)")
                }
            } catch {
                ClashMacDebugLog.note("profile-url \(id.rawValue): save failed \(error.localizedDescription)")
                 
                 
                self.feedback.say(ClashMacFeedbackSentences.couldNotSave(reason: ClashErrorCopy.message(error, locale: Locale.current), id: "profile-url.save"),
                                   operation: "profile-url.save")
                throw ClashStoredWriteSaidElsewhere()
            }
        }
         
         
         
         
         
         
         
         
         
         
         
         
         
        func convertLegacyNow(
            sources: [String]?, scheme: String?, change: (inout ConfigurationCreationDraft) -> Void = { _ in }
        ) async throws {
            await library.reload()
            let generation = library.snapshot.generation
            ClashMacDebugLog.note("convert \(id.rawValue): generation \(generation) sources \(sources ?? []) scheme \(scheme ?? "nil")")
            let source = try await profiles.configurationSourceFromLegacy(id.rawValue)
            var draft = ConfigurationCreationDraft()
            draft.add(source, rule: nil)
             
             
             
             
             
             
             
            if let sources { draft.selectedSourceIDs = sources }
            draft.selectedRuleID = scheme ?? ConfigurationBuiltins.basicRuleID
            draft.label = profile.label
            draft.dnsMode = .system
            draft.connectAfterCreation = false
            change(&draft)
            try await profiles.editConfiguration(draft, id: id.rawValue, generation: generation)
            await library.reload()
            ClashMacDebugLog.note("convert \(id.rawValue): written, generation \(library.snapshot.generation) recipe \(library.snapshot.recipes.first { $0.id == id.rawValue }?.sources.map(\.id) ?? [])")
        }
         
         
        func setComposition(sources: [String]?, scheme: String?) {
            writes.enqueue({
                if library.snapshot.recipes.contains(where: { $0.id == id.rawValue }) {
                    try await editNow { draft in
                        if let sources { draft.selectedSourceIDs = sources }
                        if let scheme { draft.selectedRuleID = scheme }
                    }
                } else {
                    try await convertLegacyNow(sources: sources, scheme: scheme)
                }
            }, failure: failed)
        }
        var actions = ClashMacConfigurationInspectorActions(
            rename: { label in list.perform(.rename(id: id, label: label)) },
            setSources: { ids in setComposition(sources: ids, scheme: nil) },
             
             
             
            setScheme: { scheme in
                writes.enqueue({
                    if library.snapshot.recipes.contains(where: { $0.id == id.rawValue }) {
                        try await profiles.switchConfigurationScheme(id.rawValue, to: scheme)
                        await library.reload()
                        ClashMacDebugLog.note("scheme \(id.rawValue): switched to \(scheme), generation \(library.snapshot.generation)")
                    } else {
                        try await convertLegacyNow(sources: nil, scheme: scheme)
                    }
                }, failure: failed)
            },
            activate: { list.select(id) },
             
             
            duplicate: { [profiles, library, locale = preferences.language.locale] in
                guard let appProfile = profiles.profiles.first(where: { $0.id == id.rawValue }),
                      let copy = await profiles.duplicate(appProfile)
                else {
                    throw ClashMacOriginalEditRefusal(message: ClashCopy.string(for: profiles.statusMessage, locale: locale))
                }
                await library.reload()
                return copy.label
            },
            export: { list.perform(.export(id: id)) },
            editSource: { [weak self] in self?.openSourceEditor(profileID: id.rawValue) },
            delete: { [weak self] in self?.configurationCenterPendingDelete = .configuration(id) },
             
             
             
             
             
             
            setSourceUpdates: { on in
                do {
                    try await writes.run {
                        try await profiles.setConfigurationSourceUpdates(id.rawValue, enabled: on)
                        await library.reload()
                        ClashMacDebugLog.note("edit \(id.rawValue): followsUpdates \(on) written, generation \(library.snapshot.generation)")
                    }
                } catch {
                    failed(error)
                    throw ClashStoredWriteSaidElsewhere()
                }
            },
            openRuntimePreview: { [weak self] in
                self?.openWindowAction?(id: "runtime-preview", value: ClashMacRuntimePreviewRequest(profileID: id.rawValue))
            },
            restoreLastKnownGood: { list.perform(.restoreLastKnownGood(id: id)) },
            setAutoUpdate: { on in try await saveProfileURL { $0.autoUpdate = on } },
            setInterval: { hours in Task { @MainActor in try? await saveProfileURL { $0.updateIntervalHours = hours } } },
             
             
             
             
             
             
             
             
            updateSource: { [weak self] in self?.updateConfigurationSources(id.rawValue) },
            stripCredentials: { [weak self] in
                guard let self else { return }
                let actions = self.subscriptionActions(profileID: id)
                Task { @MainActor in
                     
                     
                    do {
                        _ = try await actions.stripCredentials()
                        self.feedback.say(ClashMacFeedbackSentences.credentialsRemoved(id: "profile-url.strip"),
                                           operation: "profile-url.strip")
                    } catch {
                        self.feedback.say(ClashMacFeedbackSentences.couldNotSave(reason: ClashErrorCopy.message(error, locale: Locale.current),
                                                                                  id: "profile-url.strip"),
                                           operation: "profile-url.strip")
                    }
                }
            },
            adoptHeldBack: { keyPath in list.perform(.adoptHeldBackUpdate(id: id, keyPath: keyPath)) },
            dismissHeldBack: { list.perform(.dismissHeldBackUpdates(id: id)) }
        )
         
         
         
         
         
        actions.setOriginalUse = { uses in
            writes.enqueue({
                if library.snapshot.recipes.contains(where: { $0.id == id.rawValue }) {
                    try await profiles.setUsesOriginalConfiguration(id.rawValue, enabled: uses)
                    await library.reload()
                    ClashMacDebugLog.note("original-use \(id.rawValue): \(uses) written, generation \(library.snapshot.generation)")
                } else if !uses {
                    try await convertLegacyNow(sources: nil, scheme: nil)
                }
            }, failure: failed)
        }
         
        actions.leaveOriginal = { scheme in
            writes.enqueue({
                try await profiles.composingOffTheOriginal(id.rawValue, onto: scheme)
                await library.reload()
                ClashMacDebugLog.note("original-use \(id.rawValue): off onto \(scheme), generation \(library.snapshot.generation)")
            }, failure: failed)
        }
         
         
        actions.followLink = { linkID in
            writes.enqueue({
                try await profiles.setConfigurationSourceUpdates(id.rawValue, enabled: true, link: linkID)
                await library.reload()
                ClashMacDebugLog.note("edit \(id.rawValue): follows link \(linkID), generation \(library.snapshot.generation)")
            }, failure: failed)
        }
        actions.customRules = customRulesActions(profileID: id)
         
        actions.loadOutline = { customRules in try await profiles.configurationOutline(id.rawValue, customRules: customRules) }
        actions.outlineDestination = { [weak self] section in self?.outlineDestination(section, profileID: id) }
         
         
        if library.snapshot.recipes.contains(where: { $0.id == id.rawValue }) {
            actions.saveAsScheme = { label in
                writes.enqueue({
                    try await profiles.saveConfigurationAsScheme(id.rawValue, label: label)
                    await library.reload()
                    ClashMacDebugLog.note("save-as-scheme \(id.rawValue): written, generation \(library.snapshot.generation)")
                     
                     
                    library.feedback?.say(ClashMacFeedbackSentences.added(label, id: "configuration.save-as-scheme"),
                                           operation: "configuration.save-as-scheme")
                }, failure: failed)
            }
        }
         
         
        actions.settingsSection = settingsSectionActions(id: id, list: list)
         
         
         
         
        let isOriginal = library.snapshot.recipes.first { $0.id == id.rawValue }.map { $0.preservesOriginal == true } ?? true
        if isOriginal, actions.settingsSection != nil {
            actions.originalGroupPage = { [weak self] name in
                guard let self else { return AnyView(EmptyView()) }
                self.loadEditorSyntaxOnce()
                return AnyView(
                    ClashMacRuleEditorSheet(actions: self.originalRuleEditorActions(profileID: id.rawValue),
                                           initialPane: .groups, presentation: .page, focus: .group(named: name))
                        .environment(\.clashMacEditorSyntax, self.editorSyntax)
                )
            }
            actions.originalEntrySettings = originalEntrySettingsActions(id: id, list: list)
        } else {
             
             
             
             
             
            actions.schemeGroupPage = { [weak self] name in
                guard let self,
                      let scheme = self.configurationLibrary.snapshot.recipes.first(where: { $0.id == id.rawValue })?.ruleSchemeID
                else { return AnyView(EmptyView()) }
                self.loadEditorSyntaxOnce()
                return AnyView(
                    ClashMacRuleEditorSheet(actions: self.ruleEditorActions(schemeID: scheme, profileID: id.rawValue),
                                           initialPane: .groups, presentation: .page, focus: .group(named: name))
                        .environment(
                            \.clashGroupIconImages,
                            (ClashProxiesDisplayPreferences.uiTestOverride() ?? ClashProxiesDisplayPreferences.load()).groupIconImages
                        )
                        .environment(\.clashMacEditorSyntax, self.editorSyntax)
                )
            }
            actions.loadSchemeGroups = {
                guard let store = profiles.configurationLibraryStore else { return [] }
                let groups = try? await Task.detached(priority: .userInitiated) { () -> [(name: String, type: String)] in
                    let snapshot = try store.snapshot()
                     
                    guard let schemeID = snapshot.recipes.first(where: { $0.id == id.rawValue })?.ruleSchemeID,
                          let scheme = snapshot.rules.first(where: { $0.id == schemeID })
                            ?? ConfigurationBuiltins.schemes.first(where: { $0.id == schemeID }) else { return [] }
                    return try ConfigurationRuleDraft(scheme: scheme, payload: store.ruleSchemePayload(scheme.id)).groups
                        .map { (name: $0.name, type: $0.type) }
                }.value
                return groups ?? []
            }
        }
        actions.compile = {
            switch await ProfilesViewModel.compileConfiguration(id.rawValue) {
            case .accepted: return .accepted
            case .refused(let problems): return .refused(problems.map { ClashMacCompileProblem(message: $0.message, place: $0.place) })
            case .unavailable(let why): return .unavailable(why)
            }
        }
         
         
        actions.setScope = { sourceID, scope in
            edit { draft in
                var scopes = draft.nodeScopes ?? [:]
                scopes[sourceID] = scope?.isEmpty == true ? nil : scope
                draft.nodeScopes = scopes.isEmpty ? nil : scopes
                if scope?.isEmpty == true { draft.selectedSourceIDs.removeAll { $0 == sourceID } }
                 
                 
                 
                else if !draft.selectedSourceIDs.contains(sourceID) { draft.selectedSourceIDs.append(sourceID) }
            }
        }
        actions.loadScopeChoices = { source in
            try await Self.scopeChoices(source, staged: nil, store: profiles.configurationLibraryStore)
        }
         
         
        actions.sourceNodes = { record, scope in
            guard let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let group = try await Task.detached(priority: .userInitiated) {
                try ConfigurationSourceContents.group(of: record, scope: scope, in: store)
            }.value
            return ClashMacSourceNodes(nodes: group.nodes.map { .init(name: $0.name, type: $0.type) },
                                      providers: group.providers.map { .init(name: $0.name, type: $0.type) })
        }
         
         
         
         
        let references = profiles.profiles.first(where: { $0.id == id.rawValue })
            .flatMap { profiles.configurationLibrarySources(for: $0) } ?? []
        actions.isUpdatingSource = references.contains { configurationLibrary.updatingSourceIDs.contains($0) }
         
         
         
        let failures = references.compactMap { configurationLibrary.updateFailures[$0] }
        actions.updateError = failures.isEmpty ? nil : failures.joined(separator: "\n")
        actions.copyProfileURL = { [weak self] in self?.copyProfileURL(of: id.rawValue) ?? false }
         
         
         
        let snapshot = configurationLibrary.snapshot
        if let recipe = snapshot.recipes.first(where: { $0.id == id.rawValue }),
           recipe.sources.count == 1, let reference = recipe.sources.first,
           let record = snapshot.sources.first(where: { $0.id == reference.id }),
           case .subscription = record.origin {
            let library = configurationLibrary
            actions.libraryLinkSharedBy = snapshot.recipes.filter { $0.sources.contains { $0.id == record.id } }.count
            actions.saveLibraryLink = { [profiles] url in
                let current = library.snapshot
                guard let latest = current.sources.first(where: { $0.id == record.id }) else {
                    throw ConfigurationLibraryError.missingDependency(record.id)
                }
                var draft = ConfigurationSourceSettingsDraft(source: latest)
                draft.url = url
                _ = try await profiles.saveConfigurationSourceSettings(latest.id, draft: draft, generation: current.generation)
                await library.reload()
                if let profile = profiles.profiles.first(where: { $0.id == id.rawValue }) {
                    await profiles.syncAwaitingLibrary(profile)
                }
                await library.reload()
            }
             
             
            actions.saveLibraryInterval = { [profiles] hours in
                let current = library.snapshot
                guard let latest = current.sources.first(where: { $0.id == record.id }) else {
                    throw ConfigurationLibraryError.missingDependency(record.id)
                }
                var draft = ConfigurationSourceSettingsDraft(source: latest)
                draft.intervalHours = hours
                _ = try await profiles.saveConfigurationSourceSettings(latest.id, draft: draft, generation: current.generation)
                await library.reload()
            }
        }
         
         
        actions.sourceIsViewOnly = { [profiles] in
            guard let appProfile = profiles.profiles.first(where: { $0.id == id.rawValue }) else { return false }
            let workingDir = profiles.workingDir
            return await Task.detached(priority: .userInitiated) {
                ProfilesViewModel.sourceIsTooLargeToReadWhole(appProfile, workingDir: workingDir)
            }.value
        }
        return actions
    }

     
     
     
    func updateConfigurationSources(_ id: String) {
        Task { @MainActor in
            guard let profile = self.profiles.profiles.first(where: { $0.id == id }) else { return }
             
             
             
             
             
             
            let references = self.profiles
                .configurationLibrarySources(for: profile) ?? []
            let subscriptions = references.filter { reference in
                guard let record = self.configurationLibrary.snapshot.sources
                    .first(where: { $0.id == reference }) else { return false }
                if case .subscription = record.origin { return true }
                return false
            }
            guard !subscriptions.isEmpty else {
                 
                 
                self.profiles.sync(profile)
                return
            }
            for reference in subscriptions {
                _ = await self.configurationLibrary.updateSourceSaying(reference)
            }
            self.profiles.load()
            self.refreshSnapshot()
        }
    }

     
    func profileURL(of id: String) -> String? {
        profiles.profiles.first(where: { $0.id == id }).flatMap { profiles.subscriptionLink(for: $0) }
    }

     
     
    @discardableResult
    func copyProfileURL(of id: String) -> Bool {
        guard let link = profileURL(of: id) else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        return true
    }

     

     
     
     
     
     
     
     
    private func customRulesActions(profileID: ClashClientKit.Profile.ID) -> ClashMacCustomRulesActions {
        let profiles = self.profiles
        let id = profileID.rawValue
         
         
         
        let targetNodes = RuleTargetNodeSource()
        let targetSearch = ConfigurationRuleTargetSearch(
            configurationID: id, defaults: DelayTestSettings.appGroupDefaults,
            locale: preferences.language.locale
        ) { await targetNodes.source(profileID: id) }
        func state() -> ClashMacCustomRulesState {
            guard let profile = profiles.profiles.first(where: { $0.id == id }) else { return .empty }
            let muted = Set(profile.override.disabledAppendRules ?? [])
            let comments = profile.override.appendRuleComments ?? [:]
            return ClashMacCustomRulesState(
                rules: profile.override.appendRules.map {
                    ClashMacCustomRule(text: $0, isEnabled: !muted.contains($0), comment: comments[$0])
                },
                prepends: profile.override.prependRules
            )
        }
        func write(_ change: (inout Profile) -> Void) throws -> ClashMacCustomRulesState {
            guard profiles.profiles.contains(where: { $0.id == id }) else {
                throw ConfigurationLibraryError.missingDependency(id)
            }
             
            profiles.updateRestagingIfActive(profileID: id, change)
            return state()
        }
        var actions = ClashMacCustomRulesActions(
            load: { state() },
            save: { rules in
                guard Set(rules.map(\.text)).count == rules.count else { throw ClashMacDuplicateCustomRule() }
                return try write { profile in
                    profile.override.appendRules = rules.map(\.text)
                    let muted = rules.filter { !$0.isEnabled }.map(\.text)
                    profile.override.disabledAppendRules = muted.isEmpty ? nil : muted
                    var comments: [String: String] = [:]
                    for rule in rules { if let comment = rule.comment, !comment.isEmpty { comments[rule.text] = comment } }
                    profile.override.appendRuleComments = comments.isEmpty ? nil : comments
                }
            },
            setPrepends: { on in try write { $0.override.prependRules = on } },
            targets: {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                if let summary = try? await targetNodes.source(profileID: id)?.summary() {
                    return ConfigurationRuleTargetCandidates.make(groups: ClashMacCustomRuleGroups.from(summary), sources: [])
                }
                let text = try await profiles.loadSavedConfigurationPreview(for: id)
                let label = profiles.profiles.first(where: { $0.id == id })?.label ?? id
                return try await Task.detached {
                    let json = try ConfigTransforms.yamlToJSON(text)
                    var groups: [String] = []
                    if let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                       let declared = root["proxy-groups"] as? [[String: Any]] {
                         
                         
                         
                        groups = declared.compactMap { $0["hidden"] as? Bool == true ? nil : $0["name"] as? String }
                    }
                    return ConfigurationRuleTargetCandidates.make(
                        groups: groups, sources: [.init(id: "configuration-" + id, label: label, documentJSON: json)]
                    )
                }.value
            },
            geoValues: { resource in
                await GeoCategoryCache.shared.categories(for: resource == .geoIP ? .geoip : .geosite)
            },
            targetSearch: ClashRuleTargetSearchHook(
                sections: { query, current in await targetSearch.sections(query: query, current: current) },
                recordUse: { targetSearch.recordUse($0) }
            )
        )
         
         
         
         
         
         
         
         
        actions.ruleNames = {
            guard let profile = profiles.profiles.first(where: { $0.id == id }),
                  let declared = await profiles.publishedRuleSetsAndSubRules(for: profile) else { return nil }
            return ClashRuleNames(policies: nil, ruleSets: declared.ruleSets, subRules: declared.subRules)
        }
        return actions
    }

     

     
     
     
     
     
     
    func ruleEditorActions(schemeID: String, profileID: String? = nil) -> ClashMacRuleEditorActions {
        let profiles = self.profiles
        let library = configurationLibrary
        func store() throws -> ConfigurationLibraryStore {
            guard let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            return store
        }
        @MainActor func load(previous: ConfigurationRuleDraft?) async throws -> ClashMacRuleEditorState {
            let store = try store()
            let snapshot = try await Task.detached { try store.snapshot() }.value
            library.apply(snapshot)
             
             
             
             
            let running = profileID.flatMap { id in snapshot.recipes.first { $0.id == id }?.ruleSchemeID }
            let wanted = previous?.schemeID ?? running ?? schemeID
             
             
             
            let exact = profileID == nil ? nil
                : snapshot.rules.first { $0.id == wanted } ?? ConfigurationBuiltins.schemes.first { $0.id == wanted }
            guard let scheme = exact ?? snapshot.effectiveRuleScheme(wanted) else {
                throw ConfigurationLibraryError.missingDependency(wanted)
            }
            let sets = snapshot.localRuleSets ?? []
            return try await Task.detached {
                _ = ConfigurationRuleCatalog.builtIn
                let draft = try ConfigurationRuleDraft(scheme: scheme, payload: store.ruleSchemePayload(scheme.id))
                let base = try scheme.baseSchemeID.flatMap { id in
                    ConfigurationBuiltins.isNative(id) ? try ConfigurationBuiltins.source(for: id)?.documentJSON : nil
                }
                return ClashMacRuleEditorState(
                    draft: previous.map { draft.preservingIdentity(from: $0) } ?? draft,
                    localSets: sets,
                    resetDocument: base ?? scheme.initialDocumentJSON ?? draft.originalDocument.serialized()
                )
            }.value
        }
        @MainActor func save(_ draft: ConfigurationRuleDraft) async throws -> ConfigurationRuleDraft {
            let snapshot = try await profiles.saveConfigurationRuleCustomization(
                draft, profileID: profileID, generation: library.snapshot.generation
            )
            library.apply(snapshot)
             
             
             
             
             
             
            let followed = profileID.flatMap { id in snapshot.recipes.first { $0.id == id }?.ruleSchemeID }.flatMap { id in
                snapshot.rules.first { $0.id == id } ?? ConfigurationBuiltins.schemes.first { $0.id == id }
            }
            guard let current = followed ?? snapshot.ruleSchemeAfterSavingCustomization(draft.schemeID) else {
                throw ConfigurationLibraryError.unreadable
            }
            let store = try store()
            return try await Task.detached {
                try ConfigurationRuleDraft(scheme: current, payload: store.ruleSchemePayload(current.id))
                    .preservingIdentity(from: draft)
            }.value
        }
        var editor = ClashMacRuleEditorActions(
            load: { try await load(previous: nil) },
            save: { draft in try await save(draft) },
            saveLocal: { value in
                library.apply(try await profiles.saveConfigurationLocalRuleSet(value, generation: library.snapshot.generation))
                return try await load(previous: nil)
            },
            deleteLocal: { id in
                library.apply(try await profiles.saveConfigurationLocalRuleSet(nil, deleting: id, generation: library.snapshot.generation))
                return try await load(previous: nil)
            },
             
             
             
            copy: { draft, name in
                library.apply(try await profiles.copyConfigurationRuleScheme(
                    draft: draft, label: name, generation: library.snapshot.generation
                ))
            },
            download: { input in try await ConfigurationTowerRuleReader.ruleSet(input) }
        )
         
         
         
        let locale = preferences.language.locale
        editor.candidates = {
            let store = try store()
            return try await Task.detached {
                 
                 
                 
                let snapshot = try store.snapshot()
                return try ConfigurationRuleTargetCandidates.make(groups: [], snapshot: snapshot, providers: true,
                                                                  naming: { $0.displayLabel(locale: locale) }, payload: store.payload)
            }.value
        }
         
         
         
         
         
         
         
        let targetNodes = RuleTargetNodeSource()
        let targetSearch = ConfigurationRuleTargetSearch(
            configurationID: profileID, defaults: DelayTestSettings.appGroupDefaults,
            locale: preferences.language.locale
        ) { await targetNodes.source(profileID: profileID) }
        editor.targetSearch = ClashRuleTargetSearchHook(
            sections: { query, current in await targetSearch.sections(query: query, current: current) },
            recordUse: { targetSearch.recordUse($0) }
        )
         
         
         
         
        editor.geoValues = { resource in
            await GeoCategoryCache.shared.categories(for: resource == .geoIP ? .geoip : .geosite)
        }
        editor.documentText = { try ConfigTransforms.jsonToYAML($0) }
        editor.documentFromText = { try ConfigTransforms.yamlToJSON($0) }
        return editor
    }

     
     
     
     
     
     
     
     
     
     
    static func editOriginalEntry(profiles: ProfilesViewModel, id: String, edits: [ConfigurationPageEdit]) async throws {
        let page = try await profiles.loadConfigurationEditorPage(profileID: id)
        var document = page.document
        for edit in edits {
            switch edit {
            case .set(let path, let value):
                let written = document.node(at: path) != nil
                let json = value.serialized()
                try await profiles.editingOriginalOffItsLink(id) {
                    try await profiles.editOriginalConfiguration(id, at: path.map(ConfigurationTextPathStep.key),
                                                                 written ? .set(json: json) : .insert(json: json)) }
                document = document.setting(path: path, to: value)
            case .remove(let path):
                 
                 
                 
                let inFile = document.node(at: path) != nil
                let inLayer = page.ownLayer?.node(at: path) != nil
                switch (inFile, inLayer) {
                case (true, true): try await profiles.editingOriginalOffItsLink(id) {
                    try await profiles.deleteInOriginalConfiguration(id, at: path, readDigest: page.readDigest) }
                case (true, false): try await profiles.editingOriginalOffItsLink(id) {
                    try await profiles.editOriginalConfiguration(id, at: path.map(ConfigurationTextPathStep.key), .delete) }
                case (false, true): try await profiles.editConfigurationSettings(id, edits: [.remove(path: path)])
                case (false, false): continue
                }
                document = document.setting(path: path, to: nil)
            default:
                throw PipelineError.sourceUnavailable("Change this one in the source.")
            }
        }
    }

     
     
     
     
     
    func originalNodesActions(profileID: String) -> ClashMacOriginalNodesActions {
        let profiles = self.profiles
        let library = configurationLibrary
        let locale = preferences.language.locale
         
         
        @MainActor final class Picks { var sources: [ConfigurationLibraryPicks.Source] = [] }
        let picks = Picks()
        @MainActor func write(_ steps: [ConfigurationTextStep]) async throws {
            guard !steps.isEmpty else { return }
            try await Self.writeOriginal(profiles: profiles, id: profileID, steps: steps, locale: locale)
            await library.reload()
        }
         
         
         
         
        @MainActor func listed() async throws -> OrderedJSON {
            if let kept = await ClashMacOriginalRules.documentWithoutKeptRules(
                profileID: profileID, store: profiles.configurationLibraryStore) { return kept }
            return try await profiles.loadConfigurationEditorPage(profileID: profileID).document
        }
        var actions = ClashMacOriginalNodesActions(
            load: {
                ClashMacOriginalNodes.nodes(in: try await listed())
            },
            nodeForm: { node, done in
                AnyView(ClashMacOriginalNodeForm(profiles: profiles, profileID: profileID, node: node, locale: locale,
                                                written: { await library.reload() }, done: done)
                    .clashPageSizedSheet())
            },
            librarySources: {
                guard let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                let sources = try await Task.detached(priority: .userInitiated) {
                    try ConfigurationLibraryPicks.sources(in: store, excludingThoseOf: profileID)
                }.value
                picks.sources = sources
                 
                let document = try await listed()
                let added = ConfigurationLibraryPicks.addedNodeIDs(sources, in: document)
                return sources.map { Self.librarySource($0, addedNodes: added, in: document, locale: locale) }
            },
            addFromLibrary: { picked in
                let ids = Set(picked.map(\.id))
                let nodes = picks.sources.flatMap(\.offered).filter { ids.contains($0.id) }
                guard !nodes.isEmpty else { return nil }
                let page = try await profiles.loadConfigurationEditorPage(profileID: profileID)
                 
                 
                 
                let plan: ConfigurationLibraryPicks.NodePlan
                do {
                    plan = try ConfigurationLibraryPicks.nodeSteps(nodes, available: picks.sources.flatMap(\.nodes), in: page.document)
                } catch let unreachable as ConfigurationLibraryPicks.UnreachableDialer {
                    throw ClashMacOriginalEditRefusal(message: ClashCopy.string(for: unreachable.sentence, locale: locale))
                }
                try await write(plan.steps)
                return ConfigurationLibraryPicks.notice(for: plan)
            },
            delete: { node in
                let page = try await profiles.loadConfigurationEditorPage(profileID: profileID)
                guard let found = ClashMacOriginalNodes.value(of: node, in: page.document) else { return }
                 
                 
                var places = OriginalListEdits.uses(ofNode: node.name, in: page.document)
                if places.isEmpty, let kept = page.keptRules {
                    let name = node.name
                    places = try await Task.detached(priority: .userInitiated) {
                        try OriginalListEdits.keptUses(of: name, keptAt: kept.file)
                    }.value
                }
                guard places.isEmpty else {
                    let sentence = ClashCopy.string(for: .format("“%@” is still in use. Change these first.", [node.name]), locale: locale)
                    throw ClashMacOriginalEditRefusal(message: ([sentence] + places.prefix(5)).joined(separator: "\n"))
                }
                try await write(OriginalListEdits.deleting([found.index], under: [.key("proxies")]))
            }
        )
        return actions
    }

     
     
     
     
    private func originalEntrySettingsActions(id: ClashClientKit.Profile.ID,
                                              list: ClashProfilesListPresentation? = nil) -> ClashMacSettingsSectionActions {
        let profiles = self.profiles
        let library = configurationLibrary
        let settings = settingsSectionActions(id: id, list: list)
        var entry = settings
        let load = settings.load
        entry.load = { section in
            var document = try await load(section)
            document.removesFileText = true
            return document
        }
        entry.save = { edits, _ in
            try await Self.editOriginalEntry(profiles: profiles, id: id.rawValue, edits: edits)
            await library.reload()
        }
        return entry
    }

     
     
     
     
     
     
    func originalProvidersActions(profileID id: ClashClientKit.Profile.ID) -> ClashMacOriginalProvidersActions {
        let profiles = self.profiles
        let library = configurationLibrary
        let locale = preferences.language.locale
        @MainActor final class Picks { var sources: [ConfigurationLibraryPicks.Source] = [] }
        let picks = Picks()
        @MainActor func write(_ steps: [ConfigurationTextStep]) async throws {
            guard !steps.isEmpty else { return }
            try await Self.writeOriginal(profiles: profiles, id: id.rawValue, steps: steps, locale: locale)
            await library.reload()
        }
         
         
         
         
        @MainActor func listed() async throws -> OrderedJSON {
            if let kept = await ClashMacOriginalRules.documentWithoutKeptRules(
                profileID: id.rawValue, store: profiles.configurationLibraryStore) { return kept }
            return try await profiles.loadConfigurationEditorPage(profileID: id.rawValue).document
        }
        @MainActor func written() async throws -> OrderedJSON? {
            try await listed().topLevelValue("proxy-providers")
        }
        var actions = ClashMacOriginalProvidersActions(
            load: {
                guard case .object(let entries)? = try await written() else { return nil }
                return entries.enumerated().map { index, entry in
                    let type: String
                    switch entry.value.topLevelValue("type") {
                    case .string(let text)?: type = text
                    case .scalar(let token)?: type = token == "null" ? "" : token
                    default: type = ""
                    }
                    return ClashMacOriginalNode(index: index, name: entry.key, type: type)
                }
            },
            entrySettings: originalEntrySettingsActions(id: id),
            add: { name, type, location in
                let existing = try await written()
                try await write([OriginalListEdits.adding(name, OriginalListEdits.newProxyProvider(type: type, location: location),
                                                          toMappingAt: "proxy-providers", exists: existing != nil)])
            },
            librarySources: {
                guard let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                let sources = try await Task.detached(priority: .userInitiated) {
                    try ConfigurationLibraryPicks.sources(in: store, excludingThoseOf: id.rawValue)
                }.value
                picks.sources = sources
                 
                let document = try await listed()
                let added = ConfigurationLibraryPicks.addedNodeIDs(sources, in: document)
                return sources.map { Self.librarySource($0, addedNodes: added, in: document, locale: locale) }
            },
            addFromLibrary: { picked in
                guard let source = picks.sources.first(where: { $0.id == picked.id }) else { return nil }
                let document = try await listed()
                let existing = document.topLevelValue("proxy-providers")
                 
                let taken = ConfigurationLibraryPicks.takenNodeSetNames(in: document)
                guard let made = ConfigurationLibraryPicks.provider(for: source, taken: taken) else { return nil }
                try await write([OriginalListEdits.adding(made.name, made.value, toMappingAt: "proxy-providers", exists: existing != nil)])
                return made.name == source.label ? nil
                    : .format("Added as “%@”: this configuration already uses the name “%@”.", [made.name, source.label])
            },
            delete: { name in
                 
                 
                let places = OriginalListEdits.uses(ofProvider: name, in: try await listed())
                guard places.isEmpty else {
                    let sentence = ClashCopy.string(for: .format("“%@” is still in use. Change these first.", [name]), locale: locale)
                    throw ClashMacOriginalEditRefusal(message: ([sentence] + places.prefix(5)).joined(separator: "\n"))
                }
                try await write(OriginalListEdits.deleting([name], fromMappingAt: "proxy-providers"))
            },
            takenNames: {
                ConfigurationLibraryPicks.takenNodeSetNames(in: try await listed())
            },
            catalog: { (try? await ProfilesViewModel.loadSyntaxCatalog())?.fieldCatalog }
        )
        return actions
    }

     
     
     
     
     
     
    static func schemeChoices(_ snapshot: ConfigurationLibrarySnapshot, for recipe: ConfigurationRecipe?) -> [ConfigurationRuleScheme] {
        ProfilesViewModel.schemeChoices(snapshot, for: recipe)
    }

     
     
     
     
    static func librarySource(_ source: ConfigurationLibraryPicks.Source, addedNodes: Set<String> = [],
                              in document: OrderedJSON? = nil, locale: Locale) -> ClashMacLibrarySource {
        let kind: ClashMacLibrarySource.SetKind?
        switch source.providerKind {
        case .link?: kind = .link
        case .nodes?: kind = .nodes
        case nil: kind = nil
        }
         
         
         
         
        return ClashMacLibrarySource(id: source.id, label: source.record.displayLabel(locale: locale),
                                    nodes: source.offered.map {
                                        ClashMacLibraryNode(id: $0.id, name: $0.name, type: source.record.nodeChain == nil ? $0.type : "",
                                                           isAdded: addedNodes.contains($0.id))
                                    },
                                    setKind: kind, isChain: source.record.nodeChain != nil,
                                    addedSetName: document.flatMap { ConfigurationLibraryPicks.addedSetName(source, in: $0) })
    }

     
     
     
     
    static func writeOriginal(profiles: ProfilesViewModel, id: String, steps: [ConfigurationTextStep],
                              readDigest: String? = nil, locale: Locale) async throws {
        do {
            try await profiles.editingOriginalOffItsLink(id) {
                try await profiles.editOriginalConfiguration(id, steps: steps, readDigest: readDigest) }
        } catch let refused as ConfigurationTextEditRefusal {
            let sentence = ClashCopy.string(refused.errorDescription ?? "", locale: locale)
            throw ClashMacOriginalEditRefusal(message: ([sentence] + [refused.failureReason].compactMap { $0 })
                .filter { !$0.isEmpty }.joined(separator: "\n\n"))
        }
    }

    func originalRuleEditorActions(profileID: String) -> ClashMacRuleEditorActions {
        let profiles = self.profiles
        let library = configurationLibrary
        let locale = preferences.language.locale
        final class Read {
            var document: OrderedJSON?
            var digest: String?
            var kept: ProfilesViewModel.ConfigurationEditorPage.KeptRules?
        }
        let read = Read()
        @MainActor func load() async throws -> ClashMacRuleEditorState {
            let page = try await profiles.loadConfigurationEditorPage(profileID: profileID)
            guard case .original = page.form else { throw ConfigurationLibraryError.unreadable }
            read.document = page.document
            read.digest = page.readDigest
            read.kept = page.keptRules
            let draft = try ClashMacOriginalRules.editorDraft(of: page, id: "original-" + profileID)
            return ClashMacRuleEditorState(draft: draft, localSets: library.snapshot.localRuleSets ?? [],
                                          resetDocument: page.document.serialized(), keptRuleCount: page.keptRules?.count)
        }
        @MainActor func save(_ draft: ConfigurationRuleDraft) async throws -> ConfigurationRuleDraft {
            guard let before = read.document else { throw ConfigurationLibraryError.unreadable }
            let steps = try await ClashMacOriginalRules.savedSteps(draft, over: before, kept: read.kept, locale: locale)
            try await profiles.editingOriginalOffItsLink(profileID) {
                try await profiles.editOriginalConfiguration(profileID, steps: steps, readDigest: read.digest) }
            return try await load().draft.preservingIdentity(from: draft)
        }
        var editor = ClashMacRuleEditorActions(
            load: { try await load() },
            save: { draft in try await save(draft) },
            saveLocal: { value in
                library.apply(try await profiles.saveConfigurationLocalRuleSet(value, generation: library.snapshot.generation))
                return try await load()
            },
            deleteLocal: { id in
                library.apply(try await profiles.saveConfigurationLocalRuleSet(nil, deleting: id, generation: library.snapshot.generation))
                return try await load()
            },
            copy: { _, _ in throw ConfigurationLibraryError.unreadable },
            download: { input in try await ConfigurationTowerRuleReader.ruleSet(input) }
        )
        editor.rulesHaveSwitches = false
         
         
        editor.keptRulesPane = {
            guard let kept = read.kept else { return AnyView(EmptyView()) }
            return AnyView(ClashMacKeptRulesList(kept: kept))
        }
        editor.keptRulesNote = ClashMacKeptRulesList.note
         
         
        let nodesTitle = ClashCopy.string("Nodes", locale: preferences.language.locale)
        let providersTitle = ClashCopy.string("Proxy Providers (Configuration Chapter)", locale: preferences.language.locale)
        editor.candidates = {
            var sections: [ConfigurationRuleTargetCandidates.Section] = []
            if case .array(let nodes)? = read.document?.topLevelValue("proxies") {
                let names = nodes.compactMap { node -> String? in if case .string(let name)? = node.topLevelValue("name") { return name }; return nil }
                if !names.isEmpty { sections.append(.init(id: "file", kind: .source, sourceLabel: nodesTitle, names: names)) }
            }
            if let document = read.document {
                let keys = ConfigurationRuleTargetCandidates.providerKeys(inDocumentJSON: document.serialized())
                if !keys.isEmpty { sections.append(.init(id: "providers:file", kind: .providers, sourceLabel: providersTitle, names: keys)) }
            }
            return ConfigurationRuleTargetCandidates(sections: sections)
        }
        editor.geoValues = { resource in
            await GeoCategoryCache.shared.categories(for: resource == .geoIP ? .geoip : .geosite)
        }
        editor.documentText = { try ConfigTransforms.jsonToYAML($0) }
        editor.documentFromText = { try ConfigTransforms.yamlToJSON($0) }
        return editor
    }

     

    private static func subscriptionState(_ profile: Profile) -> ClashMacSubscriptionSettingsState {
        var url = ""
        if case .url(let link) = profile.source { url = link }
        return ClashMacSubscriptionSettingsState(
            url: url,
            autoUpdate: profile.autoUpdate,
            updateIntervalHours: profile.updateIntervalHours,
            canStripCredentials: ProfileMetadataUpdate.strippingSourceCredentials(from: profile) != nil
        )
    }

    private func appProfile(_ id: ClashClientKit.Profile.ID) throws -> Profile {
        guard let profile = profiles.profiles.first(where: { $0.id == id.rawValue }) else {
            throw ConfigurationLibraryError.unreadable
        }
        return profile
    }

     
     
     
    private func subscriptionActions(profileID: ClashClientKit.Profile.ID) -> ClashMacSubscriptionSettingsActions {
        ClashMacSubscriptionSettingsActions(
            save: { [weak self] draft in
                guard let self else { throw ConfigurationLibraryError.unreadable }
                let current = try self.appProfile(profileID)
                try self.profiles.updateMetadata(
                    current, label: current.label, subscriptionURL: draft.url,
                    autoUpdate: draft.autoUpdate, updateIntervalHours: draft.updateIntervalHours
                )
                return Self.subscriptionState(try self.appProfile(profileID))
            },
            stripCredentials: { [weak self] in
                guard let self else { throw ConfigurationLibraryError.unreadable }
                try self.profiles.stripSourceCredentials(try self.appProfile(profileID))
                return Self.subscriptionState(try self.appProfile(profileID))
            }
        )
    }

     

     
     
     
     
    private func scriptsActions(profileID: ClashClientKit.Profile.ID) -> ClashMacScriptsActions {
        func state() throws -> ClashMacScriptsState {
            let profile = try appProfile(profileID)
            let scripts = ScriptLibrary.load().map { ClashMacScriptEntry(id: $0.id, label: $0.label, canRefresh: $0.sourceURL != nil, sourceHost: $0.sourceURL.flatMap { URL(string: $0)?.host }) }
            var fields = 0
            if let data = profile.override.patchJSON.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                fields = object.count
            }
            return ClashMacScriptsState(
                scripts: scripts,
                 
                 
                 
                selectedID: profile.overwriteMode == .script ? profile.selectedScriptID : nil,
                patchFieldCount: fields,
                exceptions: profile.override.appendRules
            )
        }
        func write(_ change: (inout Profile) -> Void) throws -> ClashMacScriptsState {
            _ = try appProfile(profileID)
             
            profiles.updateRestagingIfActive(profileID: profileID.rawValue, change)
             
             
             
             
             
             
             
            return try state()
        }
        func select(_ id: String?) throws -> ClashMacScriptsState {
            try write { profile in
                profile.selectedScriptID = id
                profile.overwriteMode = ProfileOverrideModePolicy.mode(
                    stored: profile.overwriteMode ?? .standard, selectedScriptID: id
                )
            }
        }
         
         
        func store(label: String, body: String, link: String? = nil) throws -> ConfigScript {
            let existing = ScriptLibrary.load()
            let id = UUID().uuidString
            var candidate = label.trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.isEmpty { candidate = ScriptLibrary.defaultLabel }
            var attempt = 2
            var script = ScriptLibrary.editedScript(id: id, label: candidate, body: body, sourceURL: link, existing: existing)
            while script == nil, attempt < 100 {
                script = ScriptLibrary.editedScript(id: id, label: "\(candidate) \(attempt)", body: body, sourceURL: link, existing: existing)
                attempt += 1
            }
            guard let script else { throw ScriptImportError.empty }
            ScriptLibrary.upsert(script)
            return script
        }
         
         
         
         
         
         
         
         
        func update(_ scripts: [ConfigScript]) async -> ClashFeedbackPresentation {
            var summary = ScriptUpdateSummary()
            for script in scripts {
                do {
                    let refreshed = try await ScriptImport.refreshed(script)
                    if refreshed.body != script.body { ScriptLibrary.upsert(refreshed); summary.changed.append(script.label) } else { summary.unchanged.append(script.label) }
                } catch { summary.failed.append((name: script.label, reason: ClashErrorCopy.message(error, locale: Locale.current))) }
            }
            return Self.scriptUpdateResult(summary)
        }
        func refresh(_ id: String) async throws -> (state: ClashMacScriptsState, result: ClashFeedbackPresentation) {
            guard let script = ScriptLibrary.load().first(where: { $0.id == id }) else { throw ScriptImportError.emptyAddress }
            let result = await update([script])
            return (try state(), result)
        }
         
        func updateAll() async throws -> (state: ClashMacScriptsState, result: ClashFeedbackPresentation) {
            let linked = ScriptLibrary.load().filter { $0.sourceURL != nil }
            guard !linked.isEmpty else {
                return (try state(), .information(
                    title: .copy("These scripts were imported before the app kept their link, so there is nothing to fetch yet. Import each from its link once more; Update works from then on."),
                    isBatchSummary: true, accessibilityIdentifier: "feedback.scripts.update.no-links"))
            }
            let result = await update(linked)
            return (try state(), result)
        }
        var actions = ClashMacScriptsActions(
            load: { (try? state()) ?? .empty },
            select: { id in try select(id) },
            addLink: { link in
                let body = try await ScriptImport.body(at: link)
                let label = (try? ScriptImport.address(link)).flatMap(ScriptImport.suggestedName(for:))
                    ?? ScriptLibrary.defaultLabel
                let script = try store(label: label, body: body, link: link)
                return try select(script.id)
            },
            addManual: { name, body in
                let script = try store(label: name, body: body)
                return try select(script.id)
            },
            remove: { [weak self] id in
                 
                 
                if let removal = ScriptLibrary.removeRestorably(id: id) {
                    self?.offerUndo(of: removal.script.label, operation: "scripts.delete.\(id)") {
                        do { try ScriptLibrary.restore(removal); return .restored } catch { return .failed(ClashErrorCopy.message(error, locale: Locale.current)) }
                    }
                }
                return try state()
            },
            clearPatch: {
                try write { $0.override.patchJSON = "" }
            },
            removeException: { index in
                try write { profile in
                    if profile.override.appendRules.indices.contains(index) {
                        profile.override.appendRules.remove(at: index)
                    }
                }
            },
            refresh: { id in try await refresh(id) },
            updateAll: { try await updateAll() }
        )
        actions.edit = { [weak self] id in self?.openWindowAction?(id: "script-editor", value: ClashMacScriptEditorRequest(scriptID: id)) }
        actions.didChange = ScriptLibrary.didChange
        return actions
    }

    @Published var navigationRequest: ClashMacSecondaryDestination?
     
     
     
    let feedback = ClashMacFeedback.makeCenter()
    private var mainWindowKey: [AnyCancellable] = []
    private var feedbackLocale: AnyCancellable?
    private var configurationLibraryLocale: AnyCancellable?
    private var feedbackFailures: AnyCancellable?
     
    private var undoTokens: Set<ClashMacUndoToken> = []
     
     
     
     
    let providersRefreshRequests = ProvidersRefreshRequests()

    func requestUpdateAllSources() {
        navigationRequest = .utility(.providers)
        providersRefreshRequests.request()
    }
     
     
     
     
     
     
     
    @Published var activityLens: ClashActivityLens = .connections
    @Published private var stagedProxyGroup: String?
     
     
     
    @Published private var stagedProxyOpening: ProxyBrowsingVisibility.Opening = .browsing
     
    private var proxiesPageChoosesInGlobal = false
    @Published private var profileRefreshToken = 0
     
     
    @Published private var lanAddress: String?
     
     
     
     
     
     
    @Published private(set) var modeRefusalMessage = ""
     
     
     
     
    let proxiesChannels = ClashRegularRootChannels()
     
     
     
    private var poolContentEpoch = 0
    func nextPoolEpoch() -> Int {
        poolContentEpoch &+= 1
        return poolContentEpoch
    }
     
     
    let rulesChannels = ClashRegularRootChannels()
    @Published private var proxiesHasExpandedGroups = false
     
     
     
    private lazy var proxiesFoldStateSink = ClashBoolSink { [weak self] value in
        guard let self, self.proxiesHasExpandedGroups != value else {
            return
        }
        self.proxiesHasExpandedGroups = value
    }
     
     
    private lazy var rulesFoldStateSink = ClashBoolSink { _ in }

    let vpn: VPNController
    let profiles: ProfilesViewModel
     
     
     
     
    let reviewContainer: URL?
     
     
     
     
    let backupScope: ClashBackupDataScope
    let command: ClashCommandClient
    let stats: StatsModel
    let nodes: NodesModel
     
     
    private let nodeListRereads = NodeListRereads()
     
     
    var proxiesHasExpandedGroupsNow: Bool { proxiesHasExpandedGroups }
    var isTestingLatencyNow: Bool { nodes.isTestingLatency }
    func refreshNodes() async { await nodes.refresh() }
     
     
     
     
     
     
     
    func applyProxiesDisplayPreferences(
        _ value: ClashProxiesDisplayPreferences
    ) {
        value.save()
        proxiesChannels.requestDisplayPreferences(value)
    }
    let networkQuality: NetworkQualityModel
    let stun: STUNTestModel
    let connections: ConnectionsModel
    let proxyShare: ProxyShareModel
    let profileImports: ProfileImportRouter
    let preferences: AppPreferencesModel

    private var revision: UInt64 = 0
    private var cancellables: Set<AnyCancellable> = []
     
     
     
     
    private let pendingCompileWatcher = ProviderRefreshStateWatcher()
     
     
    private let startupOutcome = StartupOutcomeWatcher(read: {
        StartupOutcomeRecord.read(from: ClashMacAppGroupAccess.readableContainer())
    })
     
     
    private var egressRecheck = EgressRecheckDebt()
     
     
     
     
     
    lazy var menuBarTraffic = ClashMacMenuBarTrafficFeed(command: command, defaults: GlobalConfig.appGroupDefaults)

    private lazy var connectionRequests = ConnectionRequestCoalescer(
        gestureWindow: { NSEvent.doubleClickInterval },
         
         
         
         
         
         
         
        isSettling: { [weak self] in
            guard let status = self?.vpn.status.lowercased() else { return false }
            return self?.vpn.isStarting == true || status == "connecting" || status == "disconnecting"
        }
    )

    init() {
         
         
         
         
         
         
         
        defer {
            Self.current = self
             
             
             
             
            let sink: () -> Void = { [weak nodes = self.nodes] in
                nodes?.latencyPublishQuietUntil = Date(
                    timeIntervalSinceNow: 0.6
                )
            }
            proxiesChannels.uiTransitionSink = sink
            rulesChannels.uiTransitionSink = sink
        }
        let vpn = VPNController()
        self.vpn = vpn
         
         
        ModulePageModel.isConnectedOnTheMac = { [weak vpn] in ["connected", "reasserting"].contains(vpn?.status ?? "") }
        let reviewContainer = (nil as URL?)
        self.reviewContainer = reviewContainer




         
         
         
         
        if let working = (reviewContainer ?? ClashAppIdentifiers.appGroupContainer)?
            .appendingPathComponent("working", isDirectory: true) {
            ClashMacDebugLog.sink = ClashMacDebugLog.fileSink(working.appendingPathComponent("configuration-centre.debug.log"))
            ClashMacDebugLog.note("app.launch review=\(reviewContainer != nil)")
        }
         
         
        if reviewContainer == nil, !false,
           !ClashMacAppGroupAccess.isWithheldFromThisProcess,
           let container = ClashAppIdentifiers.appGroupContainer {
            ownerService = ClashMacOwnerService(container: container)
            ownerService?.start()
        }

            backupScope = .ordinary
            profiles = ProfilesViewModel(vpn: vpn)

        command = ClashCommandClient()
        stats = StatsModel()

             
             
            nodes = NodesModel(
                automaticPinsDefaults: UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite)
            )

        networkQuality = NetworkQualityModel()
        stun = STUNTestModel()

            connections = ConnectionsModel()

        proxyShare = ProxyShareModel()
        profileImports = ProfileImportRouter()
        preferences = AppPreferencesModel()

        observeRuntimeChanges()
        installFirstLoadProbes()
        installLibraryGoneAnswer()

        observeMenuTracking()
        observeProxiesPageSeen()
        refreshSnapshot()


        Self.current = self
         
         
         
         
         
         
        ClashMacLaunchGate.shared.onceLaunched { [weak self] in
            self?.installStatusItem()
        }
        visibilityObserver = ClashMacProductVisibilityObserver { [weak self] visible in
            self?.productVisibilityDidChange(visible)
        }
        visibilityObserver?.trace = { Self.traceWindow($0) }
    }

     
     
     
     
    static weak var current: ClashMacSceneModel?

     
    private(set) var statusItem: NSStatusItem?
    private var statusMenuController: ClashMacStatusMenuController?
    private var statusItemSubscriptions: Set<AnyCancellable> = []
     
     
     
     
     
    private var statusItemTunnelStatus = ""

     
     
    func focusMainWindow(_ openWindow: OpenWindowAction) {
        quietLaunch.cancel()
        if raiseExistingMainWindow() { return }
        openWindow(id: "main")
         
         
        noteWindowOpen(from: "main-menu", path: "opener")
    }

     
     
     
    private var openWindowAction: OpenWindowAction?

    func rememberWindowOpener(_ openWindow: OpenWindowAction) {
        openWindowAction = openWindow
    }

     
     
    func openSourceEditor(profileID: String) {
        openWindowAction?(
            id: "source-editor",
            value: ClashMacSourceEditorRequest(profileID: profileID)
        )
    }

     
     
     
     
     
     
    func openProxiesGroup(_ group: String) {
        stagedProxyGroup = group
        stagedProxyOpening = .browsing
        proxiesPageChoosesInGlobal = false
        proxiesChannels.requestOpenGroup(group)
        navigationRequest = .proxies
        openMainWindow(from: "menu.group")
    }

     
     
     
     
     
     
     
     
     
     
    private func endChoosingInGLOBALIfSwitchedAway(to root: ClashRootDestination?) {
        shownRoot = root
        guard proxiesPageChoosesInGlobal, ClashMacChooseNodePage.switchedAway(to: root, pending: navigationRequest) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, proxiesPageChoosesInGlobal,
                  ClashMacChooseNodePage.switchedAway(to: shownRoot, pending: navigationRequest) else { return }
            proxiesPageChoosesInGlobal = false
            stagedProxyOpening = .browsing
            proxiesChannels.requestBrowsing()
        }
    }
    private var shownRoot: ClashRootDestination?

     
     
     
     
    func openGLOBALToChooseANode() {
         
         
         
        stagedProxyGroup = GlobalProxySelectionPolicy.groupName
        stagedProxyOpening = .choosingInGlobal
        proxiesPageChoosesInGlobal = true
        proxiesChannels.requestOpenGroup(GlobalProxySelectionPolicy.groupName, opening: .choosingInGlobal)
        navigationRequest = .proxies
        openMainWindow(from: "mode.choose-node")
    }

    func openMainWindow(from entry: String) {
         
        quietLaunch.cancel()
        let raised = raiseExistingMainWindow()
        if !raised {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindowAction?(id: "main")
        }
        noteWindowOpen(from: entry, path: raised ? "raised" : (openWindowAction == nil ? "no-opener" : "opener"))
    }

     
     
     
     
     
     
    private func noteWindowOpen(from entry: String, path: String) {
        Self.traceWindow(#"window.open from=\#(entry) path=\#(path) \#(ClashMacWindowFacts.line(mainWindow))"#)
        guard path != "raised" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            Self.traceWindow(#"window.open from=\#(entry) after=0.6s \#(ClashMacWindowFacts.line(self.mainWindow))"#)
        }
    }

     
     
     
     
    private weak var mainWindow: NSWindow?
    private var mainWindowClose: AnyCancellable?
     
    private var quietLaunch = ClashMacQuietLaunch()

     
     
     
     
     
    func comeUpQuietlyAtLogin() {
        if let window = mainWindow {
            Self.putAway(window)
        } else {
            quietLaunch.arm(at: Date())
        }
    }

     
     
    private static func putAway(_ window: NSWindow) {
        window.orderOut(nil)
        DispatchQueue.main.async { window.close() }
    }

    func mainWindowDidAttach(_ window: NSWindow) {
        if quietLaunch.putsAway(at: Date()) {
            Self.putAway(window)
            return
        }
        guard window !== mainWindow else { return }
        mainWindow = window
        mainWindowClose = NotificationCenter.default
            .publisher(for: NSWindow.willCloseNotification, object: window)
            .sink { [weak self] _ in
                self?.mainWindow = nil
                self?.mainWindowClose = nil
            }
         
        mainWindowKey = ClashMacMainWindowClock.follow(
            window,
            isMain: { [weak self] in $0 === self?.mainWindow },
            pause: { [weak self] in self?.feedback.pause("window") },
            resume: { [weak self] in self?.feedback.resume("window") }
        )
    }

    @discardableResult
    private func raiseExistingMainWindow() -> Bool {
        guard let window = mainWindow else { return false }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        return true
    }

     
     
     
     
     
    var currentOutboundMode: AppleClientOutboundMode {
        AppleClientOutboundMode(rawValue: outboundMode.rawValue) ?? .rule
    }

    var actions: AppleClientActions {
        let home = AppleClientActions(capability: .home) {
            [weak self] action in
            guard case .home(let command) = action else { return }
            await self?.perform(command)
        }
        let connection = AppleClientActions(capability: .connection) {
            [weak self] action in
            guard case .connection(let intent) = action else { return }
            await self?.performConnection(intent)
        }
        let profiles = AppleClientActions(capability: .profiles) {
            [weak self] action in
            guard let self, case .profiles(let command) = action else { return }
            switch command {
            case .select(let id):
                await self.selectProfile(id)
            case let .adoptHeldBackUpdate(id, keyPath):
                self.adoptHeldBackUpdate(id, keyPath: keyPath)
            case .dismissHeldBackUpdates(let id):
                self.dismissHeldBackUpdates(id)
            default:
                 
                 
                 
                break
            }
        }
        let selection = AppleClientActions(capability: .profileSelection) {
            [weak self] action in
            guard case .selectProfile(let id) = action else { return }
            await self?.selectProfile(id)
        }
        let routing = AppleClientActions(capability: .outboundMode) {
            [weak self] action in
            guard case .setOutboundMode(let mode) = action else { return }
            await self?.changeOutboundMode(mode, from: .window)
        }
        let utilities = AppleClientActions(capability: .utilities) {
            action in
            guard case .openUtility = action else { return }
        }
        let more = AppleClientActions(capability: .more) { action in
            guard case .openMore = action else { return }
        }
        let activity = AppleClientActions(capability: .activity) { action in
            guard case .activity(let command) = action else { return }
            switch command {
             
             
             
             
             
             
            case .setLogSeverityFilter(let levels):
                ClashLogSettings.setSeverityFilter(
                    levels,
                    in: GlobalConfig.appGroupDefaults
                )
            default:
                break
            }
        }
        return (try? AppleClientActions.composing([
            home,
            connection,
            profiles,
            selection,
            routing,
            utilities,
            more,
            activity,
        ])) ?? .unavailable
    }

    func refreshVPNInstallation() async {
         
         
         
         
         
        guard !Self.withholdsTunnelHousekeeping else { return }
        await vpn.refreshSystemVPNInstallation()
        rebind()
        refreshSnapshot()
    }

     
     
     
     
     
     
    private func appGroupIsReadable() async -> Bool {
        guard !ClashMacAppGroupAccess.isWithheldFromThisProcess else { return true }
        let began = Date()
        let container = await ClashMacAppGroupAccess.awaitReadable(
            read: ClashMacAppGroupAccess.readableContainer,
            pause: { seconds in
                (try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))) != nil
            },
            onImpatient: { [weak self] in
                 
                 
                NSLog("%@", "app-group: launch still cannot read \(ClashAppIdentifiers.appGroup); waiting")
                self?.appDataUnreadable = true
                self?.refreshSnapshot()
            }
        )
        let waited = Date().timeIntervalSince(began)
        if waited > 0.1 {
             
             
            let outcome = container == nil ? "cancelled" : "readable"
            NSLog("%@", "app-group: \(outcome) after \(String(format: "%.1f", waited)) s")
            ClashMacDebugLog.note("app-group \(outcome) after \(String(format: "%.1f", waited)) s")
        }
         
        guard container != nil else { return false }
        if appDataUnreadable {
            appDataUnreadable = false
            refreshSnapshot()
        }
        ownerService?.start()
        return true
    }

    func prepare() async {
        installFeedback()

             
            guard await appGroupIsReadable() else { return }
             
             
             
             
             
             
            if let container = ClashMacAppGroupAccess.readableContainer() {
                try? await VPNController.ensureCoreSetupOffMain(container: container)
            }
            vpn.legacySettingsMigration = vpn.migrateLegacyGlobalSettingsIfNeeded()
             
             
            AppGoCrashReportStore.shared.consumeOnce()

        profiles.load()
         
        recomputeHomeRuleTally()
        profiles.selectSoleProfileIfNeeded()
        profileImports.importSharedFiles()
        rebind()
        prewarmEditorPreparations()
        await vpn.refresh()
        rebind()
        syncConnections(commandConnected: command.isConnected)
        proxyShare.updateAPIAvailability(command.isConnected)
        if command.isConnected {
            await command.refreshMetadata()
            await nodes.refresh()
            await proxyShare.refresh()
        }
         
         
         
        await profiles.settleLibraryHousekeeping()
        startAutomaticResourceRefresh()
         
         
        ClashMacScriptNotifications.start()
         
         
        ClashMacModuleScripts.start(tunnelIsConnected: { [weak self] in self?.vpn.status == "connected" })
        startTakingModesChosenOnCards()
        handlePendingSystemAction()
         
         
         
        await appCameToFront()
         
         
         
         
         
         
        profiles.publishWidgetFacts()
         
         
         
         
         
        ICloudAutoBackup.shared.start()
        refreshSnapshot()
         
         
         
         
        ClashMacScriptNotificationPresenter.shared.appIsPrepared()
    }



     
     
     
     
    private func startAutomaticResourceRefresh() {
        guard !false,
              automaticRefreshDriver == nil else { return }
        let gate = refreshPowerGate
        gate.start()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in await gate.automatic() }
        }
        automaticRefreshDriver = Task { @MainActor in
            await gate.automatic()
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: UInt64(
                        BackgroundRefresh.foregroundScanInterval
                    ) * 1_000_000_000
                )
                guard !Task.isCancelled else { break }
                await gate.automatic()
            }
        }
    }

     
     
     
     
     
     
     
    private func startTakingModesChosenOnCards() {
        if cardModeWatcher == nil {
            cardModeWatcher = ClashWidgetModeChoiceWatcher(store: ClashWidgetFactsPublisher.store) { [weak self] in
                Task { await self?.adoptModeChosenOnACard() }
            }
        }
        guard let watcher = cardModeWatcher else { return }
        if !watcher.start() {
             
             
             
             
            let root = ClashWidgetFactsPublisher.store.root.path
            ClashLogStore.shared.append(
                "widget mode watcher: not listening on \(root); a card's mode is taken on the next activation",
                stream: .app, level: .warning)
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func adoptModeChosenOnACard() async {
        guard !false, currentProfile != nil,
              let raw = ClashWidgetFactsPublisher.takeModeChosenOnACard(),
              let mode = AppleClientOutboundMode(rawValue: raw) else { return }
        let refusalBefore = modeRefusalMessage
        await setOutboundMode(mode)
        globalQuestion = nil
        if modeRefusalMessage != refusalBefore {
            ClashLogStore.shared.append(
                "widget mode \(raw) not applied  \(modeRefusalMessage)",
                stream: .app, level: .warning)
            modeRefusalMessage = refusalBefore
        }
    }

     
     
     
     
     
     
     
     
    private let systemHandoff = ClashSystemHandoff()

    func handlePendingSystemAction() {
        guard !false,
              let route = systemHandoff.consume() else { return }
        ClashLogStore.shared.append(
            "system handoff consumed -> \(String(describing: route))", stream: .app, level: .warning)
        handleSystemRoute(route)
    }

     
     
    func takeModesChosenOnCardsNow() async {
        startTakingModesChosenOnCards()
        await adoptModeChosenOnACard()
    }

    deinit {
        automaticRefreshDriver?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

     
     
     
     
    private var legacySettingsAttention: LegacySettingsAttention? {
        guard let result = vpn.legacySettingsMigration else { return nil }
        return LegacySettingsAttention.make(from: result, profiles: profiles.profiles)
    }

     
     
     
    func performLegacySettingsAttention(actionID: String) {
        if legacySettingsAttention == nil,
           ClashMoreAttention.settingsMovedIntoConfigurations.actions.contains(where: { $0.id == actionID }) {
            FlClashRuntimeConfig.acknowledgeMovedIntoConfigurationsNotice()
            refreshSnapshot()
            return
        }
        guard let attention = legacySettingsAttention,
              let action = attention.actions.first(where: { $0.id == actionID })
        else { return }
        switch action.resolution {
        case .openProfile, .openScripts:
             
             
             
            navigationRequest = .profiles
        default:
            guard let workingDirectory = ClashAppIdentifiers.appGroupContainer?
                .appendingPathComponent("working", isDirectory: true)
            else { return }
            if let fresh = LegacySettingsResolver.perform(
                action.resolution,
                attentionID: attention.id,
                workingDirectory: workingDirectory
            ) {
                vpn.legacySettingsMigration = fresh
            }
             
             
             
            profiles.load()
            refreshSnapshot()
        }
    }

    func dismissModeRefusalMessage() {
        modeRefusalMessage = ""
    }

     
     
     
    func cancelStart() {
        Task { await performPrimaryAction(.cancel) }
    }

    func performPrimaryAction() {
         
         
        guard let intent = latestSnapshot.connection.primaryIntent else { return }
        Task { await performConnection(intent) }
    }

     
     
     
     
     
    func performPrimaryActionFromMenu() {
        guard let intent = latestSnapshot.connection.primaryIntent else { return }
        performPrimaryAction()
        menuStartFailure = nil
        guard intent != .disconnect else { return }
         
        let tunnel = vpn
        let connected = tunnel.$status.filter { $0 == "connected" }.map { _ in Optional<String>.none }
        let failed = tunnel.$lastError.dropFirst().filter { !$0.isEmpty }.map { Optional($0) }
        menuStartFailure = connected.merge(with: failed)
            .first()
            .timeout(.seconds(60), scheduler: RunLoop.main)
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { [weak self] _ in self?.menuStartFailure = nil }) { [weak self] sentence in
                guard let self, let sentence else { return }
                 
                let message = tunnel.text(of: sentence)
                let result = ClashFeedbackPresentation.error(title: .copy("Connection failed"), message: message,
                                                             accessibilityIdentifier: "feedback.menu.start.failed")
                ClashMacMenuBarFeedback.fail(result, on: self.mainWindow, locale: self.preferences.language.locale)
            }
    }
    private var menuStartFailure: AnyCancellable?

     
     
     
     
    private func pickFromMenu(group: String, member: String) {
        nodes.picks.pick(group, member, repick: .skipped) { [weak self] group, member in
            await self?.performMenuPick(group: group, member: member)
        }
    }

     
     
     
    private func performMenuPick(group: String, member: String) async {
         
         
        let tried = !nodes.isSwitchingProxy && command.isConnected
        await nodes.select(group: group, name: member)
        guard tried else { return }
         
         
         
        guard ClashSystemVPNPolicy.isActive(vpn.status),
              nodes.groups.first(where: { $0.name == group })?.holdsSelection(member) == false else { return }
        ClashMacMenuBarFeedback.fail(
            .error(title: ClashFeedbackCopy.couldNotSwitch(to: member), accessibilityIdentifier: "feedback.menu.select.failed"),
            on: mainWindow, locale: preferences.language.locale)
    }

    func selectProfile(_ id: ClashClientKit.Profile.ID) async {
        guard let profile = profiles.profiles.first(
            where: { $0.id == id.rawValue }
        ) else { return }
        guard await profiles.selectAndWait(profile) else {
            refreshSnapshot()
            return
        }
        activeRuntimeDidChange()
        refreshSnapshot()
    }

     
     
    func adoptHeldBackUpdate(_ id: ClashClientKit.Profile.ID, keyPath: String) {
        guard let profile = profiles.profiles.first(where: { $0.id == id.rawValue }) else { return }
        do {
            try profiles.adoptHeldBackUpdate(profile, keyPath: keyPath)
            activeRuntimeDidChange()
        } catch {
            Logger(subsystem: ClashPerf.subsystem, category: "profiles")
                .error("adopt held-back update failed: \(String(describing: error), privacy: .public)")
             
            feedback.say(ClashMacFeedbackSentences.couldNotSave(reason: ClashErrorCopy.message(error, locale: Locale.current), id: "held-back.adopt"),
                          operation: "held-back.adopt")
        }
        refreshSnapshot()
    }

     
    func dismissHeldBackUpdates(_ id: ClashClientKit.Profile.ID) {
        guard let profile = profiles.profiles.first(where: { $0.id == id.rawValue }) else { return }
        do {
            try profiles.dismissHeldBackUpdates(profile)
        } catch {
            Logger(subsystem: ClashPerf.subsystem, category: "profiles")
                .error("dismiss held-back updates failed: \(String(describing: error), privacy: .public)")
            feedback.say(ClashMacFeedbackSentences.couldNotSave(reason: ClashErrorCopy.message(error, locale: Locale.current), id: "held-back.dismiss"),
                          operation: "held-back.dismiss")
        }
        refreshSnapshot()
    }

     
     
     
    enum ModeChangeOrigin { case window, menu, unattended }

     
     
     
     
     
    func changeOutboundMode(_ mode: AppleClientOutboundMode, from origin: ModeChangeOrigin) async {
        dismissModeRefusalMessage()
        await setOutboundMode(mode)
        let locale = preferences.language.locale
        if let question = globalQuestion, origin != .unattended, !asksAboutGlobal {
             
             
             
            globalQuestion = nil
            dismissModeRefusalMessage()
            asksAboutGlobal = true
            let answer = await ClashMacGlobalModeQuestion.ask(question.exit, on: mainWindow, locale: locale)
            asksAboutGlobal = false
            switch answer {
            case .chooseNode:
                openGLOBALToChooseANode()
                return
            case .cancel:
                return
            case .switchAnyway:
                 
                 
                 
                guard currentProfile?.id == question.profileID else { return }
                await setOutboundMode(.global, overNoProxy: true)
            }
        }
        globalQuestion = nil
        guard !modeRefusalMessage.isEmpty else { return }
        let result = ClashMacFeedbackSentences.modeNotChanged(
            reason: ClashCopy.string(modeRefusalMessage, locale: locale), id: "mode")
        dismissModeRefusalMessage()
         
         
        let windowShown = mainWindow?.isVisible == true
        switch origin {
        case .window where windowShown, .unattended where windowShown: feedback.say(result, operation: "mode")
        case .window, .menu, .unattended: ClashMacMenuBarFeedback.fail(result, on: mainWindow, locale: locale)
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func openGLOBALOnTheLivingProxiesPage() {
        guard let global = HomeProxiesEntryPolicy.globalToOpen(
            mode: .global,
            liveCatalog: command.isConnected && nodes.isRuntimeAvailable,
            candidates: HomeProxiesEntryPolicy.candidates(
                nodes.groups, mode: .global, name: \.name, isHidden: \.hidden
            ),
            readerFoldedAll: nodes.readerFoldedAllGroups
        ) else { return }
        proxiesChannels.requestOpenGroup(global)
    }

     
    struct GlobalQuestion: Equatable {
        let profileID: String
        let exit: ClashTunnelOutboundMode.GlobalExit
    }
    private(set) var globalQuestion: GlobalQuestion?
    private var asksAboutGlobal = false

     
     
    func setOutboundMode(_ mode: AppleClientOutboundMode, overNoProxy: Bool = false) async {
        globalQuestion = nil
        guard let profile = currentProfile,
              let storedMode = Profile.OutboundMode(
                  rawValue: mode.rawValue
              )
        else { return }

         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        let stored = await profiles.outboundMode(for: profile)
        if OutboundModeSelection.changesNothing(
            requested: storedMode,
            stored: stored,
            running: command.isConnected ? command.mode : nil
        ) {
            return
        }

        if storedMode == .global, command.isConnected {
             
             
             
             
             
             
             
             
            if !overNoProxy {
                var check = await nodes.checkGlobalMode()
                if check == .notYetKnown {
                     
                     
                     
                     
                     
                     
                     
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    check = await nodes.checkGlobalMode()
                }
                switch GlobalModeConfirmation.switchStep(check: check, groups: nodes.groups) {
                case .switchNow:
                    break
                case .ask(let exit):
                     
                     
                    globalQuestion = GlobalQuestion(profileID: profile.id, exit: exit)
                    modeRefusalMessage = ClashTunnelOutboundMode.notTurnedOnKey(exit)
                    return
                case .refuse(let sentence):
                    modeRefusalMessage = sentence
                    return
                case .notKnown:
                     
                    modeRefusalMessage = nodes.groups.isEmpty
                        ? """
                        The core has not reported its proxy groups yet, so \
                        Global mode was not applied. Try again in a moment.
                        """
                        : GlobalModeConfirmation.switchNotConfirmed
                    return
                }
            }
        }

         
        var opensGLOBAL = false
        do {
             
             
             
             
             
             
             
            try profiles.updateOutboundMode(
                profileID: profile.id,
                mode: storedMode,
                kernelCarriesTheChange: command.isConnected
            )
            if command.isConnected {
                await command.setMode(storedMode.rawValue)
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                if command.isConnected, command.mode != storedMode.rawValue {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    await command.setMode(storedMode.rawValue)
                }
                if command.isConnected, command.mode != storedMode.rawValue {
                    modeRefusalMessage = """
                        The running tunnel did not accept the mode change. \
                        The profile was saved; the mode applies on the next \
                        connect.
                        """
                } else if command.isConnected, storedMode == .global {
                    opensGLOBAL = true
                }
            }
        } catch {
             
             
            modeRefusalMessage = """
                The outbound mode could not be saved to this profile. \
                \(error.localizedDescription)
                """
            return
        }
        refreshSnapshot()
         
         
         
        if opensGLOBAL {
            DispatchQueue.main.async { [weak self] in self?.openGLOBALOnTheLivingProxiesPage() }
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
    private func performConnection(
        _ intent: AppleClientConnectionIntent,
        beforeRun: (@MainActor @Sendable () -> Void)? = nil
    ) async {
         
         
         
         
        await connectionRequests.run(interruptInFlight: intent == .disconnect && (vpn.isStarting || vpn.isPreparingStart)) { [weak self] in
            await beforeRun?()
            await self?.performConnectionUncoalesced(intent)
            return true
        }
    }

    private func performConnectionUncoalesced(
        _ intent: AppleClientConnectionIntent
    ) async {
         
         
         
         
         
         
         
        switch intent {
        case .disconnect:
            vpn.recordReaderWord(.stop)
            await vpn.stop()
        case .connect, .activateSystemExtension,
             .updateSystemExtension, .installConfiguration:
             
             
             
            let word = vpn.recordReaderWord(.connect).map { VPNController.StandingWord(generation: $0, required: false) }
             
             
             
             
             
            vpn.nextStartIsUserInitiated = true
            defer { vpn.nextStartIsUserInitiated = false }
            await VPNController.$standingOnWord.withValue(word) {
                if let currentProfile {
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    let profiles = profiles
                    let started = await vpn.preparingToStart { await profiles.connectFromHome(currentProfile) }
                    if started { activeRuntimeDidChange() }
                } else {
                    _ = await vpn.start()
                }
            }
        }
        rebind()
        refreshSnapshot()
    }

     
     
     
     
     
     
     
     
     
    private func installFirstLoadProbes() {
        let command = self.command
         
         
        ProviderTunnelUpdate.perform = { [weak command] target, stillInUse in
            guard let command else { return .noSession }
            return await command.updateProviderInTunnel(kind: target.kind, name: target.name,
                                                        url: target.url ?? "", stillInUse: stillInUse)
        }
         
         
        command.takesWhatTheCompileCouldNotTake = { [weak self] held in
            guard let self, !Self.withholdsTunnelHousekeeping,
                  let container = ClashAppIdentifiers.appGroupContainer else { return }
            self.profiles.publishWhatOnlyAPublicationTakes(container: container, handedOn: held)
        }
         
         
         
         
         
         
        AppGroupDirectFetch.session = command
        DirectFetchFallback.perform = { [weak command] request, maxBytes, timeout, redirectPolicy in
            guard let command else { throw DirectFetchUnavailable() }
            return try await command.fetchDirect(request, maxBytes: maxBytes, timeout: timeout,
                                                 redirectPolicy: redirectPolicy)
        }
        ProviderFirstLoadRetry.loadedRuleProvidersInCore = { [weak command] in
            await MainActor.run {
                guard let command, command.isConnected else { return nil as ClashCommandClient? }
                return command
            }.map { client in
                Task { @MainActor in
                     
                     
                    let catalog = try? await client.ruleProviderCatalog()
                    return Set(catalog?.ruleProviders.compactMap { name, provider in
                        provider.updatedAt == nil ? nil : name
                    } ?? [])
                }
            }?.value ?? []
        }
        ProviderFirstLoadRetry.loadedProxyProvidersInCore = { [weak command] in
            await MainActor.run {
                guard let command, command.isConnected else { return nil as ClashCommandClient? }
                return command
            }.map { client in
                Task { @MainActor in
                     
                     
                     
                    let catalog = try? await client.providerRuntimeCatalog()
                    return Set(catalog?.proxyProviders.compactMap { name, provider in
                        provider.nodeCount > 0 || (provider.updatedAt?.timeIntervalSince1970 ?? 0) > 0
                            ? name : nil
                    } ?? [])
                }
            }?.value ?? []
        }
    }

     
     
     
     
     
    func providerDownloadActivityChanged() {
        recomputeHomeRuleTally()
        if !command.isConnected { Task { [nodes] in await nodes.refresh() } }
    }

    func applyFirstLoadRefreshes() {
         
         
        let updates = ProviderFirstLoadRetry.takeRuntimeUpdates()
        guard let published = updates.compactMap(\.publishedIn).last else { return }
        Task { [vpn] in await PublishedRuntimeHandover.apply(vpn: vpn, profileID: published.profileID) }
    }

    func open(_ url: URL) {
        if let route = ClashSystemRoute(url: url) {
            handleSystemRoute(route)
            return
        }
        if ClashMacModuleInstallLink.open(url, request: ModulePageModel.shared.addRequest, pushModulesPage: openModulesPage) {
            return
        }
         
         
         
         
        profileImports.open(url)
        if url.isFileURL {
            navigationRequest = .profiles
        }
    }

     
     
     
     
     
     
    private func handleSystemRoute(_ route: ClashSystemRoute) {
        Task { [weak self] in
            guard let self else { return }
             
             
             
            await self.vpn.refresh()
            let plan = ClashMacSystemRoutePlan.plan(
                for: route,
                isActive: ClashSystemVPNPolicy.isActive(self.vpn.status)
            )
            if let destination = plan.destination {
                self.navigationRequest = destination
            }
            if let mode = plan.mode {
                await self.changeOutboundMode(mode, from: .unattended)
            }
            switch plan.command {
            case .start?:
                await self.performConnection(.connect)
            case .stop?:
                await self.performConnection(.disconnect)
            case .unchanged?, nil:
                break
            }
        }
    }

    func secondaryContent(
        _ destination: ClashMacSecondaryDestination
    ) -> AnyView {
        switch destination {
        case .profiles:
             
             
             
            AnyView(
                ProfileCenterAdapter(
                    profiles: self.profiles,
                    importRouter: self.profileImports,
                    ownsNavigationContainer: false,
                    palette: ClashMacPlatformPresentation.palette,
                    onActiveRuntimeChanged: {
                        [weak self] in
                        self?.activeRuntimeDidChange()
                    },
                    capabilityInterceptor: { [weak self] destination in
                        guard let self,
                              case .sourceEditor(let id) = destination
                        else { return false }
                        self.openSourceEditor(profileID: id.rawValue)
                        return true
                    },
                    listPresentation: { list in
                        AnyView(self.configurationCenter(list))
                    }
                )
                .clashToolbarUnlessInPanel {
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    ToolbarItemGroup(placement: .primaryAction) {
                         
                         
                         
                         
                         
                         
                        ClashMacCentreAddButton(model: self)
                        ClashMacCentreUpdateAllButton(library: self.configurationLibrary, profiles: self.profiles)
                    }
                }
            )
        case .proxies:
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            AnyView(
                ClashMacProxiesGhostChrome(model: self).equatable()
            )
        case .rules:
             
             
             
            AnyView(ClashMacRulesGhostChrome(model: self).equatable())
        case .activeRules:
            AnyView(ActiveRulesView(command: command))
        case .dnsQuery:
            AnyView(DNSQueryView(command: command))
        case .runtimeConfiguration:
            runtimeConfigurationContent()
        case .configuration:
             
             
             
             
            AnyView(Color.clear.onAppear { [weak self] in self?.openCurrentConfigurationPage() })
        case .utility(let destination):
            AnyView(
                GoldenFlowUtilitiesDestinationAdapter(
                    vpn: vpn,
                    command: command,
                    connections: connections,
                    networkQuality: networkQuality,
                    stun: stun,
                    proxyShare: proxyShare,
                    destination: destination,
                     
                     
                     
                    activityLens: ClashMacActivityLensHandoff.binding(activityLens) { [weak self] lens in
                        guard let self, self.activityLens != lens else { return }
                        self.activityLens = lens
                    },
                    usesRegularDetailLayout: true,
                    loadsPersistedLogs:
                        !false
                )
                 
                 
                 
                .environment(\.proxyShareSettingsRows, activeLANShareSettingsRows)
                 
                 
                 
                .environment(\.clashProvidersRefreshRequests, providersRefreshRequests)
            )
        case .more(let destination):
            AnyView(
                GoldenFlowMoreDestinationAdapter(
                    vpn: vpn,
                    command: command,
                    preferences: preferences,
                    destination: destination,
                    usesRegularDetailLayout: true
                )
            )
        }
    }

    private func runtimeConfigurationContent() -> AnyView {
        guard let profile = currentProfile else {
            return AnyView(
                ClashMacSecondaryUnavailableView(
                    destination: .runtimeConfiguration
                )
            )
        }
         
         
         
        let isActive = profiles.activeProfileID == profile.id
        let verdictsHome: URL? = reviewContainer
            ?? ClashAppIdentifiers.appGroupContainer
        return AnyView(
            ClashMacRuntimeConfigurationPage(
                profile: profile,
                isActive: isActive,
                fetchTexts: { [weak self] in
                    guard let self else { return (nil, nil, nil) }
                    let profiles = self.profiles
                    let workingDir = profiles.workingDir
                    return await ClashMacRuntimeConfigurationTexts.texts(
                        large: profiles.hasLargeSource(profile),
                         
                         
                         
                         
                         
                         
                        effective: { await profiles.runtimeDisplayTextOffTheMainActor(for: profile) },
                        source: { await profiles.loadSourceYAML(for: profile) },
                        captured: { workingDir.flatMap { ProfileSourceStore.capturedText(workingDirectory: $0, profileID: profile.id) } }
                    )
                },
                 
                 
                fetchOmittedRules: { [weak self] in
                    guard let self,
                          let snapshot = try? self.profiles.configurationLibraryStore?.snapshot()
                    else { return [] }
                    return snapshot.recipes.first { $0.id == profile.id }?.droppedRules ?? []
                },
                blockedRuleSets: isActive
                    ? { [verdictsHome] in
                        guard let verdictsHome else { return [] }
                        return ProviderCompileVerdicts
                            .load(
                                coreHome: verdictsHome
                                    .appendingPathComponent("working")
                            )
                            .blockedRuleProviders
                    }
                    : nil
            )
            .equatable()
        )
    }

    private func savePayloadDialerEdits(
        _ edits: [ProxyPayloadDialerEdit],
        profileID: String
    ) async throws {
        guard !edits.isEmpty else {
            return
        }
        guard let latest = profiles.profiles.first(
            where: { $0.id == profileID }
        ) else {
            throw PipelineError.sourceUnavailable(
                "the profile is no longer available"
            )
        }
        var working = try profiles.providerDefinitionsDraft(for: latest)
        for edit in edits {
            try working.setPayloadDialer(
                provider: edit.provider,
                node: edit.node,
                dialerProxy: edit.dialerProxy
            )
        }
        try await profiles.updateProviderDefinitions(working)
    }

    private var currentProfile: Profile? {
        return HomeProfileResolution.workingProfile(in: profiles)
    }

     
     
     
     
    private var runsPreviousRevision: Bool {
        if startupOutcome.record?.homeShowsPreviousRevision(vpnStatus: vpn.status) == true { return true }
        return vpn.lastReloadNotice?.errorClass == .config
            && ["connected", "reasserting"].contains(vpn.status)
    }

     
     
     
    private var runningPreviousProfileName: String? {
        guard runsPreviousRevision,
              let id = startupOutcome.record?.runningProfileID(ifNot: currentProfile?.id)
        else { return nil }
        return profiles.profiles.first { $0.id == id }?.label
    }

    private var outboundMode: Profile.OutboundMode {
        ClashMacOutboundModeResolution.resolve(
            vpnStatus: vpn.status,
            liveMode: command.mode,
            saved: savedOutboundModeForDisplay()
        )
    }

     
     
     
     
     
     
     
     
     
     
    private func savedOutboundModeForDisplay() -> Profile.OutboundMode {
        guard let profile = currentProfile else { return .rule }
        guard let known = profiles.cachedOutboundMode(for: profile)
                ?? profiles.lastKnownOutboundMode(for: profile)
        else { return lastShownSavedOutboundMode ?? .direct }
        lastShownSavedOutboundMode = known
        return known
    }

    private var lastShownSavedOutboundMode: Profile.OutboundMode?

     
     
     
     
    var menuBarProxyCatalog: ClashMacMenuProxyCatalog {
        ClashMacMenuProxyCatalog.make(
            groups: menuBarGroups,
            mode: ProxyBrowsingVisibility.Mode(coreValue: outboundMode.rawValue),
            delays: nodes.delays,
            testing: nodes.testingNames,
            isConnected: command.isConnected,
            configuredSelections: menuBarConfiguredSelections,
            sort: menuBarSort
        )
    }

     
     
     
    private var menuBarSort: ClashProxiesDisplayPreferences.Sort {
        (ClashProxiesDisplayPreferences.uiTestOverride() ?? ClashProxiesDisplayPreferences.load()).sort
    }

     
     
     
    private var menuBarGroups: [ProxyGroup] {
        command.isConnected || nodes.offlineGroupsProfileID == currentProfile?.id ? nodes.groups : []
    }

     
     
     
     
     
     
    private var menuBarConfiguredSelections: [String: String] {
        guard !command.isConnected, let profile = currentProfile else { return [:] }
         
         
        if profiles.hasLargeSource(profile) {
            return ClashMacMenuProxyCatalog.configuredSelections(
                offlineGroups: menuBarGroups, selectedMap: profile.selectedMap
            )
        }
        let model = ProxiesOverviewModel
            .cached(sourceYAML: profiles.sourceYAML(for: profile))
            .applying(selectedMap: profile.selectedMap)
        return model.groups.reduce(into: [:]) { all, group in
            if let selection = group.configuredSelection { all[group.name] = selection }
        }
    }

     
     
     
     
    fileprivate func menuBarLatency(
        delays: [String: Int],
        testing: Set<String>
    ) -> [String: [String: ClashProxyLatencyState]] {
        ClashMacMenuProxyCatalog.make(
            groups: nodes.groups,
            mode: ProxyBrowsingVisibility.Mode(coreValue: outboundMode.rawValue),
            delays: delays,
            testing: testing
        ).groups.reduce(into: [:]) { all, group in
            all[group.name] = group.latency
        }
    }

    private var selectedRoute: (name: String?, delay: Int?) {
         
         
         
         
        guard outboundMode == .global else { return (nil, nil) }
        let route = HomeNamedRoute.route(mode: .global, groups: nodes.groups, delays: nodes.delays)
        return (route.node, route.delay)
    }

     
     
     
    private func finalRuleRoute(mode: Profile.OutboundMode) -> ClashHomeFinalRuleRoute? {
        guard mode == .rule else { return nil }
        let route = HomeNamedRoute.route(
            mode: mode, groups: nodes.groups, delays: nodes.delays,
            terminals: nodes.resolvedNowByGroup, groupsAreTheCores: nodes.groupsAreTheCores,
            finalRuleTarget: homeFinalRuleTarget)
        return route.node.map { ClashHomeFinalRuleRoute(group: route.group, node: $0, delayMilliseconds: route.delay) }
    }

     
     
     
    private var homeVPNStatus: String {
        ClashHomeConnectionPresenter.homeStatus(status: vpn.status, isPreparingStart: vpn.isPreparingStart,
                                                systemHasNotAnswered: vpn.startAwaitingSystem)
    }

    private var connectionPhase: AppleClientConnectionPhase {
        switch homeVPNStatus.lowercased() {
        case "connected", "reasserting":
            .connected
        case "connecting":
            .preparing
        case "disconnecting":
            .disconnecting
        case "invalid", "unknown", "unavailable":
            .unavailable
        default:
            .disconnected
        }
    }

    private func trafficSnapshot(_ traffic: ClashTrafficSnapshot) -> AppleClientTrafficSnapshot {
        AppleClientTrafficSnapshot(
            uploadBytesPerSecond: traffic.upload,
            downloadBytesPerSecond: traffic.download,
            uploadTotalBytes: traffic.uploadTotal,
            downloadTotalBytes: traffic.downloadTotal,
            uploadRatesBytesPerSecond: traffic.uploadHistory,
            downloadRatesBytesPerSecond: traffic.downloadHistory,
            coreStartedAtUnixSeconds: {


                return HomeConnectionClock.startedAtUnixSeconds(
                    coreReported: command.runtimeDiagnostics?.startTimeUnix,
                    connectedSince: vpn.connectedSince)
            }()
        )
    }

    private func refreshSnapshot(onlyIfChanged: Bool = false) {
        let revision = self.revision &+ 1
        let profile = currentProfile
        let selected = profile.flatMap { stored in
            try? ClashClientKit.Profile.ID(stored.id)
        }.map {
            AppleClientProfileSnapshot(
                id: $0,
                label: profile?.label ?? ""
            )
        }
        let mode = outboundMode
        let route = selectedRoute
        let info = AppBuildInfo.current()

        let value = AppleClientSnapshot(
            revision: revision,
            selectedProfile: selected,
            connection: AppleClientConnectionSnapshot(
                phase: connectionPhase,
                selectedRouteName: route.name,
                selectedRouteDelayMilliseconds: route.delay,
                issue: vpn.reportableLastError.isEmpty
                    ? nil
                    : AppleClientFailure(
                        code: .connection,
                        title: "Connection",
                        message: vpn.reportableLastError
                    )
            ),
            home: AppleClientHomeSnapshot(
                routing: AppleClientRoutingSnapshot(
                    mode:
                        AppleClientOutboundMode(
                            rawValue: mode.rawValue
                        ) ?? .rule
                ),
                traffic: trafficSnapshot(command.traffic),
                proxyGroupCount: homeConfigTally?.proxyGroups ?? 0,
                proxyCount: homeProxyCount.unit == "proxies" ? (homeProxyCount.value ?? 0) : 0,
                 
                 
                 
                ruleCount: homeConfigTally?.rules ?? 0,
                connection:
                    ClashHomeConnectionPresenter.presentation(
                        for: ClashHomeConnectionFacts(
                            activeProfileName: profile?.label,
                            vpnStatus: homeVPNStatus,
                            errorMessage: vpn.reportableLastError,
                            vpnAuthorization: vpn.systemVPNAuthorization,
                            errorIsConfigurationNotFound:
                                vpn.lastErrorOffersVPNProfileReset,
                             
                            errorSubject: vpn.startRefusedByCore?.words,
                            allowsSystemVPNProfileReset:
                                vpn.systemVPNProfileResetAvailable,
                            isSwitchingProxy:
                                nodes.isSwitchingProxy,
                            mode: mode.rawValue,
                            selectedProxyName: route.name,
                            selectedProxyDelayMilliseconds:
                                route.delay,
                            runningPreviousRevision: runsPreviousRevision,
                            runningPreviousProfileName: runningPreviousProfileName,
                             
                             
                            globalExitWithoutProxy: command.isConnected ? ClashHomeGlobalExit(nodes.globalExit) : nil,
                             
                             
                            finalRuleRoute: finalRuleRoute(mode: mode)
                        )
                    ),
                favoriteCards: HomeFavoriteCardPreferences().load(),
                trafficScope: TrafficStatisticsSettings.onlyProxy()
                    ? .proxiedOnly
                    : .allTraffic,
                 
                 
                 
                 
                 
                 
                 
                 
                 
                proxies: HomeProxiesCardPolicy.domainSnapshot(
                    mode: outboundMode,
                    standard: ClashHomeDomainSnapshot(
                        count: homeProxyCount.value,
                        countUnit: homeProxyCount.unit,
                        names: homeConfigTally?.groupNames ?? []
                    ),
                    globalNode: globalGroupNode
                ),
                rules: ClashHomeDomainSnapshot(
                    count: homeConfigTally?.rules,
                    countUnit: "rules",
                    names: homeRuleTargets
                ),
                 
                 
                 
                 
                 
                egress: egressSnapshot,
                lanAddress: lanAddress,
                isProfileActionInFlight:
                    profiles.isActivationInFlight,
                 
                 
                 
                 
                 
                 
                selectedProfileIsSystemFallback: ProfileCenterPolicy.selectedProfileIsSystemFallback(
                    selectedID: profile?.id,
                    profiles: profiles.profiles
                ),
                profilesLoaded: profiles.hasLoadedProfiles || appDataUnreadable,
                profilesUnavailableReason: profiles.profiles.isEmpty
                    ? (appDataUnreadable
                        ? ClashCopy.string("Clash can't read its data yet. Wait a moment, or quit and reopen Clash.", locale: preferences.language.locale)
                        : profiles.lastFailure?.message)
                    : nil
            ),
            profiles: ClashProfilesSnapshot(
                 
                 
                 
                 
                 
                 
                profiles: ProfileCenterPolicy.catalog(profiles.profiles).compactMap(
                    profileSnapshot
                ),
                statusMessage: profiles.statusMessage,
                featureAvailability: .full
            ),
            utilities: ClashUtilitiesSnapshot(
                nativeAPIConnected: command.isConnected,
                activeConnectionCount:
                    connections.activeConnectionCount,
                requestCount: connections.requestLog.count,
                logCount: command.logs.count,
                isRecordingLogs: ClashLogSettings.isRecording(
                    from: GlobalConfig.appGroupDefaults
                ),
                logRetentionTitle: ClashLogSettings.retention(
                    from: GlobalConfig.appGroupDefaults
                ).title,
                networkQualitySummary: networkQuality.summary,
                stunSummary: stun.summary,
                proxyShareStatus: proxyShare.phase.title,
                proxyShareEnabled: proxyShare.status.enabled
            ),
            more: ClashMoreSnapshot(
                about: ClashAboutSnapshot(
                    appVersion: info.appVersion,
                    buildNumber: info.buildNumber,
                    sourceRevision: info.sourceRevision,
                    coreVersion: info.coreVersion
                ),
                 
                 
                 
                 
                 
                overrideCounts: OverrideEntryCount.moreCounts(
                    in: currentProfile.map { profiles.settingsProfile(for: $0) }?
                        .override.patchJSON ?? ""
                ),
                 
                 
                attention: legacySettingsAttention?.snapshot
                    ?? (FlClashRuntimeConfig.movedIntoConfigurationsNoticePending() ? .settingsMovedIntoConfigurations : nil)
            ),
            capabilities: AppleClientCapabilities([
                .home: .available,
                .profiles: .available,
                .proxies:
                    profile == nil
                        ? .unavailable(.requiresProfile)
                        : .available,
                .activity:
                    command.isConnected
                        ? .available
                        : .unavailable(.requiresConnection),
                .rules:
                    profile == nil
                        ? .unavailable(.requiresProfile)
                        : .available,
                .dns:
                    profile == nil
                        ? .unavailable(.requiresProfile)
                        : .available,
                .utilities: .available,
                .more: .available,
                .configuration:
                    profile == nil
                        ? .unavailable(.requiresProfile)
                        : .available,
                .connection:
                    profile == nil
                        ? .unavailable(.requiresProfile)
                        : .available,
                .profileSelection:
                    profiles.profiles.isEmpty
                        ? .unavailable(.requiresProfile)
                        : .available,
                .outboundMode:
                    profile == nil
                        ? .unavailable(.requiresProfile)
                        : .available,
            ])
        )
        if onlyIfChanged, let shown = snapshotGate.latest, value.drawsTheSame(as: shown) {
            ClashPerf.count("scene.snapshot.unchanged")
            return
        }
        self.revision = revision
        publish(value)
    }

     
     
     
     
     
    static func deleteSubtitle(
        _ profile: Profile, canDelete: Bool, isCurrent: Bool
    ) -> ClashDisplayText {
        if profile.id == LocalDefaultProfileProvisioner.profileID {
            return "Clash keeps Direct as a safe system fallback"
        }
        if canDelete, isCurrent { return "Clash returns to its built-in profile" }
        return canDelete
            ? "Remove this profile from Clash"
            : "Switch to another profile before deleting"
    }

    private func profileSnapshot(
        _ profile: Profile
    ) -> ClashProfileSnapshot? {
        guard let id = try? ClashClientKit.Profile.ID(profile.id)
        else { return nil }
        let source: ClashProfileSourceKind
        let sourceSummary: ClashDisplayText
        switch profile.source {
        case .url:
            source = .remote
            sourceSummary = "Profile URL"
        case .file(let name):
            source = .file
            sourceSummary = .copy(name)
        case .clipboard:
            source = .clipboard
            sourceSummary = "Local profile"
        }
        let isCurrent = profile.id == profiles.activeProfileID
        let canDeleteProfile = ProfileCenterPolicy.canDelete(
            profileID: profile.id,
            activeProfileID: profiles.activeProfileID,
            profiles: profiles.profiles
        )
        return ClashProfileSnapshot(
            id: id,
            label: profile.label,
            source: source,
            sourceSummary: sourceSummary,
             
             
             
             
             
            subscription: profile.subscriptionInfo.map {
                ClashProfileSubscriptionSnapshot(
                    uploadBytes: $0.upload, downloadBytes: $0.download, totalBytes: $0.total,
                    expiration: $0.expire > 0 ? Date(timeIntervalSince1970: TimeInterval($0.expire)) : nil
                )
            },
            lastUpdatedAt: profile.lastUpdatedAt,
            autoUpdate: profile.autoUpdate,
            updateIntervalHours: profile.updateIntervalHours,
            isCurrent: isCurrent,
            isBusy: profile.id == profiles.busyProfileID,
            canEditSource: true,
             
             
             
             
             
            canDelete: canDeleteProfile,
            deleteSubtitle: Self.deleteSubtitle(
                profile, canDelete: canDeleteProfile, isCurrent: isCurrent
            ),
            runtimeSummary:
                isCurrent ? "Active runtime" : "Saved profile",
             
             
             
            heldBackUpdates: (profile.suppressedUpdates ?? []).map {
                ClashProfileHeldBackUpdate(
                    keyPath: $0.keyPath,
                    change: ClashProfileHeldBackUpdate.Change(rawValue: $0.change.rawValue) ?? .changed,
                    newValue: $0.newValue,
                    appValue: $0.appValue
                )
            }
        )
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private var egressSnapshot: ClashHomeEgressSnapshot {
        let connected = vpn.status == "connected"
        let address = stats.egressIP
        let hasResult =
            connected
            && !address.isEmpty
            && address != "—"
            && address != "checking…"
            && address != "VPN not connected"
            && !address.hasPrefix("error")
        let detail = [stats.egressCountryName, stats.egressISP]
            .filter { !$0.isEmpty && $0 != "—" }
            .joined(separator: " · ")
        return ClashHomeEgressSnapshot(
            address: hasResult ? address : nil,
            flag: hasResult
                ? EgressLookupResult.flagEmoji(
                    countryCode: stats.egressCountryCode
                )
                : "",
            detail: hasResult ? detail : "",
            canRefresh: connected,
            isChecking: connected && address == "checking…"
        )
    }

     
     
     
    private var locale: Locale { preferences.language.locale }

     
     
     
     
     
     
     
     
     
    private func perform(_ command: ClashHomeCommand) async {
        switch command {
        case .performPrimaryAction(let action):
            await performPrimaryAction(action)
        case .openProfiles:
             
             
             
             
             
             
            break
        case .openProxies:
             
            if self.command.isConnected, currentOutboundMode == .global, ClashHomeGlobalExit(nodes.globalExit) != nil {
                openGLOBALToChooseANode()
            } else {
                navigationRequest = .proxies
            }
        case .openRules:
            navigationRequest = .rules
        case .openRuntimeConfiguration:
            navigationRequest = .runtimeConfiguration
        case .setCards(let cards):
            HomeFavoriteCardPreferences().save(
                ClashHomeCatalog.normalized(cards)
            )
            refreshSnapshot()
        case .setTrafficScope(let scope):
            let onlyProxy = scope == .proxiedOnly
            guard onlyProxy != TrafficStatisticsSettings.onlyProxy() else {
                return
            }
            TrafficStatisticsSettings.setOnlyProxy(onlyProxy)
             
            self.command.applyTrafficStatisticsPreference()
            refreshSnapshot()
        case .refreshExternalIP:
            await stats.checkEgressIP()
            refreshSnapshot()
             
             
            if stats.egressIP.hasPrefix("error") || stats.egressIP == "unexpected response" {
                 
                let reason = stats.egressIP.hasPrefix("error")
                    ? stats.egressIP.dropFirst("error".count).trimmingCharacters(in: CharacterSet(charactersIn: ": ").union(.whitespaces))
                    : stats.egressIP
                feedback.say(.error(title: ClashFeedbackCopy.couldNotCheckExternalIP, message: reason.isEmpty ? nil : .verbatim(reason),
                                     accessibilityIdentifier: "feedback.home.egress.failed"),
                              operation: "home.egress")
            } else {
                 
                feedback.withdraw("home.egress")
            }
        case .refreshLANIP:
            lanAddress = LANAddressInventory.current().first
        case .showConnectionIssue:
             
             
             
            break
        case .openOnDemand:
             
             
             
             
            break
        case .resetVPNProfile:
             
             
             
             
             
            _ = await vpn.resetSystemVPNProfile()
            refreshSnapshot()
        }
    }

    private func performPrimaryAction(_ action: ClashHomePrimaryAction) async {
        switch action {
        case .openProfiles:
            navigationRequest = .profiles
        case .connect, .retry:
            await performConnection(.connect)
        case .cancel:
            await performConnection(.disconnect) { [weak self] in
                self?.profiles.cancelActivation()
            }
        case .disconnect:
            await performConnection(.disconnect)
        case .retryProxy:
            await vpn.forceRestart()
            rebind()
        case .none:
            break
        }
    }

    private func rebind() {
         
         
         
         
         
         
         
        command.bind(sessionProvider: { [weak vpn] in vpn?.session })
        command.bind(session: vpn.session)
        command.sync(vpnStatus: vpn.status)
        stats.bind(session: vpn.session, command: command)
        nodes.bind(command: command)
        stun.bind(command: command)
        proxyShare.bind(command: command)
         
         
        LocalNetworkPermission.clearPublicationMirror(in: UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite))
         
         
         
        proxyShare.bind(profileYAML: { [weak self] in
            guard let self,
                  let active = self.profiles.profiles.first(where: { $0.id == self.profiles.activeProfileID })
            else { return nil }
            return self.profiles.effectiveYAMLIfReady(for: active)
        }, lanListenerPermitted: {
            LocalNetworkPermission.isPermitted(UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite))
        })
         
         
        proxyShare.bind(kernelShare: profiles.kernelLANShareBinding())
    }

     
     
     
    func pooledDetailOverlay(
        for root: ClashRootDestination?
    ) -> AnyView {
        endChoosingInGLOBALIfSwitchedAway(to: root)
        return AnyView(
            ZStack {
                ClashMacPooledRootSlot(
                    destination: .proxies,
                    visible: root == .proxies,
                    channels: proxiesChannels,
                    foldStateSink: proxiesFoldStateSink,
                    background: ClashMacPlatformPresentation.palette.canvas,
                    content: { [weak self] in
                        guard let self else { return AnyView(EmptyView()) }
                        return AnyView(
                            ClashMacFrozenPoolContent(
                                freeze: ClashMacPoolFreeze(
                                     
                                     
                                     
                                     
                                    frozen: root != .proxies
                                        || self.nodes.isTestingLatency,
                                    epoch: self.nextPoolEpoch()
                                )
                            ) {
                                 
                                 
                                 
                                 
                                 
                                 
                                ClashDeferredPageContent {
                                SessionProxiesRailRoot(
                                    vpn: self.vpn,
                                    command: self.command,
                                    nodes: self.nodes,
                                    profiles: self.profiles,
                                    profileRefreshToken:
                                        self.profileRefreshToken,
                                    avoidsLiveProviderStore:
                                        false,
                                    stagedGroup: Binding(
                                        get: { [weak self] in
                                            self?.stagedProxyGroup
                                        },
                                        set: { [weak self] in
                                            self?.stagedProxyGroup = $0
                                        }
                                    ),
                                    stagedOpening: Binding(
                                        get: { [weak self] in
                                            self?.stagedProxyOpening ?? .browsing
                                        },
                                        set: { [weak self] in
                                            self?.stagedProxyOpening = $0
                                        }
                                    )
                                )
                                } placeholder: {
                                    ClashMacPlatformPresentation.palette
                                        .canvas.ignoresSafeArea()
                                }
                            }
                            .equatable()
                        )
                    }
                )
                .allowsHitTesting(root == .proxies)

                ClashMacPooledRootSlot(
                    destination: .rules,
                    visible: root == .rules,
                    channels: rulesChannels,
                    foldStateSink: rulesFoldStateSink,
                    background: ClashMacPlatformPresentation.palette.canvas,
                    content: { [weak self] in
                        guard let self else { return AnyView(EmptyView()) }
                        return AnyView(
                            ClashMacFrozenPoolContent(
                                freeze: ClashMacPoolFreeze(
                                    frozen: root != .rules,
                                    epoch: self.nextPoolEpoch()
                                )
                            ) {
                                ClashMacConnectionStateContent(
                                    initialValue: self.command.isConnected,
                                    updates: self.command.$isConnected.eraseToAnyPublisher()
                                ) { connected in
                                    SessionRulesRailRoot(
                                        command: self.command,
                                        canInspectActiveRules: connected,
                                        profiles: self.profiles,
                                        openProxiesGroup: { [weak self] group in
                                            guard let self else { return }
                                             
                                             
                                             
                                             
                                            self.stagedProxyGroup = group
                                            self.proxiesChannels
                                                .requestOpenGroup(group)
                                            self.navigationRequest = .proxies
                                        }
                                    )
                                }
                            }
                            .equatable()
                        )
                    }
                )
                .allowsHitTesting(root == .rules)
            }
        )
    }

     
     

     
     
     
     
     
     
     
     
     
     
     
     
    private func prewarmEditorPreparations() {
        guard let profile = currentProfile, !profiles.hasLargeSource(profile) else { return }
        let raw = profiles.runtimeSourceYAML(for: profile)
        Task { @MainActor in
            await ProfileProxyChainsView.prewarm(
                profile: profile, rawYAML: raw
            )
            if let raw {
                await ProfilesViewModel.prewarmProviderDraft(
                    profile: profile, raw: raw
                )
            }
             
             
             
             
             
            await ProfileDNSSettingsAdapter.prewarm(
                profile: profile,
                sourceYAML: self.profiles.uiProjectedYAML(for: profile),
                sidecar: ProfileDNSSettingsAdapter.sidecarYAML(
                    profileID: profile.id
                )
            )
        }
    }

     
     
     
     
     
    private let editorPrewarm = ClashMacQuietPeriod(seconds: 2)

    private func activeRuntimeDidChange() {
        profileRefreshToken &+= 1
         
         
         
        proxiesChannels.contentGeneration &+= 1
        nodes.noteRouteChanged()
         
         
        nodeListRereads.ask { [nodes] in await nodes.refresh() }
        editorPrewarm.request { [weak self] in
            self?.prewarmEditorPreparations()
        }
        recomputeHomeRuleTally()
        refreshSnapshot()
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    private var homeConfigTally: ProfileConfigTally?
    private var homeRuleTargets: [String] = []
     
     
    private var homeFinalRuleTarget: String?
     
     
     
     
     
     
    private var homeTallyGeneration: UInt64 = 0
    private var homeTallyLanded: UInt64 = 0

     
     
     
     
     
     
     
     
    private var homeProxyCount: HomeProxiesCardPolicy.Count {
        let inline = homeConfigTally?.proxies
         
         
         
        return HomeProxiesCardPolicy.count(inline: inline, providerNodes: nodes.providerNodeTotal ?? 0,
                                           notDownloadedProviders: notDownloadedProxyProviders)
    }

     
     
    private var notDownloadedProxyProviders = 0

     
     
    private var globalGroupNode: String? {
        let name = ProxyBrowsingVisibility.kernelGlobalGroupName
        if let running = nodes.groups.first(where: { $0.name == name })?.now, !running.isEmpty {
            return running
        }
        return currentProfile?.selectedMap[name]
    }

    private func recomputeHomeRuleTally() {
        recomputeHomeRuleTally(summaryNodes: command.nodeSummary?.nodes)
    }

     
     
     
    private func recomputeHomeRuleTally(summaryNodes: Int?) {
         
        homeTallyGeneration &+= 1
        let generation = homeTallyGeneration
        let profile = currentProfile
         
        let runningNodes = command.isConnected ? summaryNodes : nil
         
         
         
         
         
         
         
        Task { @MainActor [weak self] in
            guard let self else { return }
            var projected: String?
            if let profile { projected = await self.profiles.loadEffectiveYAML(for: profile) }
             
             
            let publication = profile.flatMap { profile in
                profile.activeRevision.map { ActiveConfigurationPointer(profileID: profile.id, revision: $0) }
            }
             
             
            var libraryNodes = runningNodes
            if libraryNodes == nil, let profile,
               let library = projected.flatMap({ ConfigTransforms.nodeLibraryPath(in: $0) }) {
                let id = profile.id, workingDir = self.profiles.workingDir
                libraryNodes = await Task.detached(priority: .userInitiated) {
                    ClashMacHomeTally.libraryNodes(profileID: id, library: library, workingDir: workingDir,
                                                   publication: publication)
                }.value
            } else if libraryNodes != nil {
                libraryNodes = await Task.detached(priority: .userInitiated) {
                    ModuleRouteHiding.nodeCount(runningNodes, of: publication)
                }.value
            }
            self.countHomeRules(projected, libraryNodes: libraryNodes, publication: publication, generation: generation)
        }
    }

    private func countHomeRules(_ projected: String?, libraryNodes: Int?, publication: ActiveConfigurationPointer?,
                                generation: UInt64) {
        let store = profiles.resourceStoreForHomeTally
         
         
         
         
        let container = profiles.appGroupContainer
        Task.detached(priority: .userInitiated) { [weak self] in
            let notDownloaded = HomeProxiesCardPolicy.notDownloadedProxyProviders(
                in: (try? store?.activeProvidersDirectory()).flatMap { ProviderCatalog.load(providersDir: $0) },
                state: container.flatMap {
                    ProviderRefreshState.read(workingDirectory: $0.appendingPathComponent("working"))
                })
            let tally = ClashMacHomeTally.make(projected: projected, libraryNodes: libraryNodes, publication: publication)
            let overview = RulesOverviewModel.make(sourceYAML: projected)
            let targets = ClashMacHomeTally.ruleTargets(of: overview)
            let finalRuleTarget = HomeNamedRoute.finalRuleTarget(of: overview)
            await MainActor.run {
                 
                 
                 
                 
                guard let self, generation > self.homeTallyLanded else { return }
                self.homeTallyLanded = generation
                self.homeConfigTally = tally
                self.homeRuleTargets = targets
                self.homeFinalRuleTarget = finalRuleTarget
                self.notDownloadedProxyProviders = notDownloaded
                self.refreshSnapshot()
            }
        }
    }

    private func observeRuntimeChanges() {
         
         
         
         
         
         
         
         
        nodes.objectWillChange.sink { [weak self] _ in
            self?.sceneRefresh.ask(drawnOnlyThroughSnapshot: true)
        }
        .store(in: &cancellables)
         
         
         
         
         
         
         
        for publisher in [
            startupOutcome.objectWillChange,
            vpn.objectWillChange,
            profiles.objectWillChange,
            connections.objectWillChange,
            networkQuality.objectWillChange,
            stun.objectWillChange,
             
             
             
             
            stats.objectWillChange,
            proxyShare.objectWillChange,
            preferences.objectWillChange,
             
             
             
             
             
             
             
            profileImports.objectWillChange,
        ] {
            publisher.sink { [weak self] _ in
                self?.sceneRefresh.ask()
            }
            .store(in: &cancellables)
        }

        command.$traffic
            .sink { [weak self] traffic in
                 
                 
                guard let self, productIsVisible else { return }
                trafficFeed.traffic = trafficSnapshot(traffic)
            }
            .store(in: &cancellables)

         
         
         
         
         
        let homeLayout = { UserDefaults.standard.string(forKey: ClashHomeOutboundModeStyle.storageKey) }
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: UserDefaults.standard)
            .map { _ in homeLayout() }
            .prepend(homeLayout())
            .removeDuplicates().dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.command.applyTrafficStatisticsPreference()
                self?.refreshSnapshot()
            }
            .store(in: &cancellables)

         
         
        command.$nodeSummary.map { $0?.nodes }.removeDuplicates().dropFirst()
            .sink { [weak self] nodes in self?.recomputeHomeRuleTally(summaryNodes: nodes) }
            .store(in: &cancellables)

         
         
         
         
        command.$runtimeDiagnostics
            .map(ClashCommandClient.coreSession(of:))
            .removeDuplicates()
            .compactMap { $0 }
            .sink { [weak self] _ in
                guard let nodes = self?.nodes else { return }
                Task { await nodes.restoreAutomaticPins() }
            }
            .store(in: &cancellables)

        for publisher in [
            command.$isConnected.map { _ in () }.eraseToAnyPublisher(),
            command.$mode.map { _ in () }.eraseToAnyPublisher(),
            command.$lastError.map { _ in () }.eraseToAnyPublisher(),
            command.$rules.map { _ in () }.eraseToAnyPublisher(),
            command.$runtimeDiagnostics.map { _ in () }.eraseToAnyPublisher(),
            command.$proxiesData.map { _ in () }.eraseToAnyPublisher(),
            command.$peerCoreVersion.map { _ in () }.eraseToAnyPublisher(),
            command.$peerCapabilities.map { _ in () }.eraseToAnyPublisher(),
            command.$previousGoCrashReport.map { _ in () }.eraseToAnyPublisher(),
            command.$previousOOMEvidence.map { _ in () }.eraseToAnyPublisher(),
            command.$isCollectingMemory.map { _ in () }.eraseToAnyPublisher(),
            command.$memoryActionMessage.map { _ in () }.eraseToAnyPublisher(),
             
             
             
             
             
            command.logCountPublisher.map { _ in () }.eraseToAnyPublisher(),
        ] {
            publisher.sink { [weak self] in
                self?.sceneRefresh.ask()
            }
            .store(in: &cancellables)
        }

         
         
        NotificationCenter.default.publisher(for: ClashThroughputUnit.didChangeNotification)
            .sink { _ in WidgetCenter.shared.reloadAllTimelines() }
            .store(in: &cancellables)

         
         
        profiles.$activeProfileID
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.connections.clearRequestHistory() }
            .store(in: &cancellables)

        vpn.$status
            .removeDuplicates()
            .sink { [weak self] status in
                guard let self else { return }
                ClashActivityIOSAdapter.tunnelIsUp = ["connected", "reasserting", "connecting"]
                    .contains(status.lowercased())
                 
                 
                 
                stats.tunnelStatusChanged(status)
                command.sync(vpnStatus: status)
                 
                 
                 
                 
                 
                 
                 
                WidgetCenter.shared.reloadAllTimelines()
                 
                 
                 
                 
                 
                syncConnectionsChannelState(status: status)
                if status == "disconnected" || status == "disconnecting" {
                     
                    connections.stop()
                    connections.tunnelDidStop()
                    menuBarTraffic.tunnelDidStop()
                }
                 
                 
                 
                 
                 
                guard status == "connected" || status == "disconnected" else { return }
                 
                 
                 
                stats.bind(session: vpn.session, command: command)
                nodes.noteRouteChanged()
            }
            .store(in: &cancellables)
         
         
         
        vpn.$status.removeDuplicates()
            .sink { [weak self] _ in self?.startupOutcome.refresh() }
            .store(in: &cancellables)

         
         
         
         
         
        nodes.$routeGeneration
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                 
                 
                 
                guard egressRecheck.routeMoved(channelUp: command.isConnected) else { return }
                Task { await self.stats.checkEgressIP() }
            }
            .store(in: &cancellables)

        command.$channelAttachFailed
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                 
                Task { @MainActor in self.syncConnections(commandConnected: self.command.isConnected) }
            }
            .store(in: &cancellables)

         
         
         
         
         
        NotificationCenter.default.publisher(for: .clashProviderContentChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self,
                      PublishedRuntimeHandover.readsNodesAgain(after: note, isConnected: command.isConnected)
                else { return }
                nodeListRereads.ask { [nodes] in await nodes.refresh() }
            }
            .store(in: &cancellables)

        command.$isConnected
            .removeDuplicates()
            .sink { [weak self] connected in
                guard let self else { return }
                syncConnections(commandConnected: connected)
                proxyShare.updateAPIAvailability(connected)
                if connected {
                    Task {
                        await self.nodes.refresh()
                        await self.proxyShare.refresh()
                    }
                }
            }
            .store(in: &cancellables)

         
         
         
         
         
         
        NotificationCenter.default.publisher(for: ClashLogSettings.levelDirectiveDidChange)
            .sink { [weak self] _ in
                guard let self else { return }
                command.refreshLogDisplayLevel()
                profiles.restageActiveRuntime()
            }
            .store(in: &cancellables)

         
         
         
         
         
         
         
         
         
        command.$isConnected.removeDuplicates()
            .sink { [weak self] connected in
                guard let self else { return }
                if egressRecheck.channelChanged(up: connected) {
                    Task { await self.stats.checkEgressIP() }
                }
            }
            .store(in: &cancellables)

         
         
         
         
         
         
        command.$isConnected.removeDuplicates()
            .sink { [weak self] connected in
                guard let self else { return }
                if connected {
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        self?.startPendingCompiles()
                    }
                } else {
                    command.stopPendingCompiles()
                }
            }
            .store(in: &cancellables)
         
         
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in Task { await self?.appCameToFront() } }
            .store(in: &cancellables)
         
         
         
        if !Self.withholdsTunnelHousekeeping {
            pendingCompileWatcher.start(directory: ProviderRefreshStateWatcher.stateDirectory) { [weak self] in
                guard let self, let container = ClashAppIdentifiers.appGroupContainer else { return }
                let state = ProviderRefreshState.read(
                    workingDirectory: container.appendingPathComponent("working", isDirectory: true))
                guard PendingProviderCompile.waits(in: state)
                        || !PendingProviderCompile.waitingForAPublication(in: state).isEmpty else { return }
                startPendingCompiles()
            }
        }
         
         
         
        if !Self.withholdsTunnelHousekeeping {
            ModulePageModel.shared.entrySource.$entry
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
            Task { await ModulePageModel.shared.reload() }
        }
    }

     
     
     
     
     
    func appCameToFront() async {
        guard !Self.withholdsTunnelHousekeeping else { return }
         
         
         
         
         
         
         
        if profiles.hasLoadedProfiles {
            await profiles.republishIfLibraryGone()
             
             
            profiles.recomposeIfModulesMovedSincePublication()
        }
        startPendingCompiles()
    }

     
     
    private var libraryGoneAnsweredAt: Date?

     
     
     
     
     
     
     
     
     
     
    private func installLibraryGoneAnswer() {
        vpn.libraryGoneHandler = { [weak self] record, stillWanted in
            guard let self, !Self.withholdsTunnelHousekeeping, stillWanted() else { return }
             
             
             
             
             
             
            guard profiles.hasLoadedProfiles else { return }
            if let last = libraryGoneAnsweredAt, Date().timeIntervalSince(last) < 60 { return }
            if await profiles.republishIfLibraryGone(record: record, stillWanted: stillWanted) {
                libraryGoneAnsweredAt = Date()
            }
        }
    }

     
     
     
    private func startPendingCompiles() {
        guard !Self.withholdsTunnelHousekeeping, command.isConnected,
              let container = ClashAppIdentifiers.appGroupContainer else { return }
        command.startPendingCompiles(container: container)
        profiles.publishWhatOnlyAPublicationTakes(container: container)
    }

     
     
     
    private static var withholdsTunnelHousekeeping: Bool {
        false || ClashMacAppGroupAccess.isWithheldFromThisProcess
    }
}

 
 
 
 
 
 
 
 
 
 
 
enum ClashMacOutboundModeResolution {
    static func resolve(vpnStatus: String, liveMode: String, saved: Profile.OutboundMode) -> Profile.OutboundMode {
        let tunnelUp = ["connected", "reasserting"].contains(vpnStatus.lowercased())
        if tunnelUp, liveMode != "—", let live = Profile.OutboundMode(rawValue: liveMode.lowercased()) {
            return live
        }
        return saved
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
private struct ClashMacPreferencesEnvironment: ViewModifier {
    @ObservedObject var preferences: AppPreferencesModel
     
     
    var presentsRestartPrompt = false


    @State private var offersLanguageRestart = false

    func body(content: Content) -> some View {
        content
            .tint(preferences.accent.color)
            .onAppear {
                applyAppearance(preferences.themeMode)
                installDetailCanvasFallback()
            }
            .onChange(of: preferences.themeMode) { mode in
                applyAppearance(mode)
            }
             
             
             
             
             
             
             
             
            .onChange(of: preferences.language) { _ in
                if presentsRestartPrompt {
                    offersLanguageRestart = true
                }
            }
            .alert(
                "Reopen Clash to change language?",
                isPresented: $offersLanguageRestart
            ) {
                Button("Reopen Now") {
                    relaunchForLanguageChange()
                }
                Button("Later", role: .cancel) {}
            } message: {
                Text(
                    "The tunnel stays connected. The new language takes effect when Clash reopens."
                )
            }
    }

     
     
     
    @MainActor
    private func installDetailCanvasFallback() {
        ClashRegularDetailCanvasFallback.color =
            ClashMacPlatformPresentation.palette.canvas
    }

    private func applyAppearance(_ mode: AppThemeMode) {
        NSApplication.shared.appearance = switch mode {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    private func relaunchForLanguageChange() {
         
         
         
         
        guard ClashMacQuit.nextTermination != .relaunchForLanguageChange
        else { return }
        ClashMacQuit.nextTermination = .relaunchForLanguageChange
         
         
        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        relauncher.arguments = [
            "-c",
            "sleep 0.6; /usr/bin/open \"\(Bundle.main.bundlePath)\"",
        ]
        try? relauncher.run()
        NSApplication.shared.terminate(nil)
    }
}

 
 
 
 
private struct ClashMacProductCommands: Commands {
     
     
     
     
     
     
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
         
         
         

        CommandGroup(replacing: .appInfo) {
            Button {
                open(.more(.about))
            } label: {
                Text(clash: .copy("About Clash"))
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button {
                open(.more(.root))
            } label: {
                Text(clash: .copy("Settings…"))
            }
            .keyboardShortcut(",", modifiers: .command)
        }

         
         
         
         
        CommandGroup(replacing: .newItem) {
            Button {
                Task { @MainActor in
                    guard let model = ClashMacSceneModel.current else { return }
                    model.focusMainWindow(openWindow)
                    model.requestNewConfiguration()
                }
            } label: {
                Text(clash: .copy("Add Profile"))
            }
            .keyboardShortcut("n", modifiers: [.command])
            sceneCommand(.copy("Create Nodes")) { $0.requestAddSource(purpose: .nodes) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            sceneCommand(.copy("Create Rules")) { $0.requestAddSource(purpose: .rules) }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            Button {
                Task { @MainActor in
                    guard let model = ClashMacSceneModel.current else { return }
                    model.focusMainWindow(openWindow)
                    model.requestUpdateAllSources()
                }
            } label: {
                 
                 
                Text(clash: .copy("Update All Providers"))
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
         
         
        CommandGroup(after: .toolbar) {
            ForEach(ClashMacConfigurationCenterSegment.allCases) { segment in
                sceneCommand(.copy(segment.title)) { $0.requestConfigurationCenter(segment) }
                    .keyboardShortcut(KeyEquivalent(Character(String(segment.rawValue + 1))), modifiers: [.command])
            }
        }
         
         
         
         
        CommandGroup(after: .pasteboard) {
            Divider()
             
             
            Button {
                 
                 
                let event = NSApp.currentEvent
                let keyWindow = NSApp.keyWindow
                Task { @MainActor in
                    guard let model = ClashMacSceneModel.current else { return }
                    guard model.deleteKeyBelongsToTheShownItem(event: event, keyWindow: keyWindow) else { return }
                    model.focusMainWindow(openWindow)
                    model.requestDeleteShownItem()
                }
            } label: {
                Text(clash: .copy("Delete"))
            }
            .keyboardShortcut(.delete, modifiers: [.command])
        }

        CommandGroup(replacing: .help) {}
    }

     
     
    private func sceneCommand(_ title: ClashDisplayText, _ request: @escaping @MainActor (ClashMacSceneModel) -> Void) -> some View {
        Button {
            Task { @MainActor in
                guard let model = ClashMacSceneModel.current else { return }
                model.focusMainWindow(openWindow)
                request(model)
            }
        } label: {
            Text(clash: title)
        }
    }

    private func open(_ destination: ClashMacSecondaryDestination) {
        Task { @MainActor in
            guard let model = ClashMacSceneModel.current else { return }
            model.focusMainWindow(openWindow)
            model.navigationRequest = destination
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
private struct ClashMacRuntimeConfigurationPage: View, Equatable {
    struct Inputs {
        var source: String?
        var snapshot: ProfileFinalConfigurationSnapshot
        var base: String?
        var comparison: String?
    }

    let profile: Profile
    let isActive: Bool
     
     
    let fetchTexts: @MainActor () async -> (source: String?, effective: String?, raw: String?)
     
     
     
     
     
    let fetchOmittedRules: () -> [String]
    let blockedRuleSets:
        (@Sendable () async -> [ProviderCompileVerdicts.Blocked])?

    @State private var inputs: Inputs?

    static func == (
        lhs: ClashMacRuntimeConfigurationPage,
        rhs: ClashMacRuntimeConfigurationPage
    ) -> Bool {
         
         
        lhs.profile == rhs.profile && lhs.isActive == rhs.isActive
    }

    var body: some View {
        Group {
            if let inputs {
                ProfileFinalConfigurationView(
                    title: "Runtime Configuration",
                    snapshot: inputs.snapshot,
                    sourceYAML: inputs.source,
                     
                     
                     
                    comparisonYAML: inputs.comparison,
                     
                     
                     
                     
                    baseYAML: inputs.base,
                    ownsNavigationContainer: false,
                    blockedRuleSets: blockedRuleSets,
                    textFirst: true
                )
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: profile) {
            let texts = await fetchTexts()
            let omittedRules = fetchOmittedRules()
             
             
             
            let captured = profile
             
             
             
             
            let omittedPersonalRules = await Task.detached(priority: .userInitiated) {
                texts.effective.map {
                    ProfileRuntimeConfigBuilder.personalRulesLeftOut(of: $0, profile: captured)
                } ?? []
            }.value
            async let baseTask: String? = Task.detached(
                priority: .userInitiated
            ) {
                texts.raw.flatMap {
                    RunningCoreDeviations.handedToCore(
                        profile: captured, sidecarYAML: $0
                    )
                }
            }.value
            async let snapshotTask = Task.detached(
                priority: .userInitiated
            ) {
                ProfileFinalConfigurationSnapshot.make(
                    sourceYAML: texts.source,
                    effectiveYAML: texts.effective,
                    omittedRules: omittedRules,
                    omittedPersonalRules: omittedPersonalRules
                )
            }.value
            inputs = await Inputs(
                source: texts.source,
                snapshot: snapshotTask,
                base: baseTask,
                comparison: texts.raw
            )
        }
    }
}

 
 
 
 
 
 
 
private struct ClashMacDeferredSourcePage: View, Equatable {
    let profile: Profile
     
    let fetch: () -> String?
    let content: (String?) -> AnyView

     
    @State private var text: String??

    static func == (
        lhs: ClashMacDeferredSourcePage,
        rhs: ClashMacDeferredSourcePage
    ) -> Bool {
        lhs.profile == rhs.profile
    }

    var body: some View {
        Group {
            if let text {
                content(text)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: profile) {
            text = .some(fetch())
        }
    }
}

 

 
 
 
 
 
 
 
 
 
 
 
 
 
 
extension ClashMacSceneModel {
    fileprivate func installStatusItem() {
        let controller = ClashMacStatusMenuController(
            snapshot: { [weak self] in
                self?.makeStatusMenuSnapshot() ?? .empty
            },
            actions: makeStatusMenuActions(),
            tunnelIsUp: { [weak self] in
                guard let self else { return false }
                return ClashMacQuit.tunnelIsUp(status: self.vpn.status)
            },
             
             
            latency: nodes.$delays
                .combineLatest(nodes.$testingNames)
                .map { [weak self] delays, testing in
                    self?.menuBarLatency(delays: delays, testing: testing) ?? [:]
                }
                .eraseToAnyPublisher(),
            testing: nodes.$isTestingLatency.eraseToAnyPublisher(),
            listenerUpdates: proxyShare.terminalListenerDidChange.eraseToAnyPublisher()
        )
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = controller.menu
        statusMenuController = controller
        statusItem = item
        statusItemTunnelStatus = vpn.status
        refreshStatusButton()
         
         
         
         
         
         
         
         
         
         
         
         
         
        Task { [weak self] in await self?.refreshVPNInstallation() }
        menuBarTraffic.$upLine
            .combineLatest(menuBarTraffic.$downLine)
            .dropFirst()
             
             
             
             
            .sink { [weak self] up, down in self?.refreshStatusButton(lines: (up, down)) }
            .store(in: &statusItemSubscriptions)
         
         
         
        vpn.$status
            .removeDuplicates()
            .dropFirst()
             
             
             
            .sink { [weak self] status in self?.refreshStatusButton(status: status) }
            .store(in: &statusItemSubscriptions)
    }

    private func refreshStatusButton(status: String? = nil, lines: (up: String, down: String)? = nil) {
         
         
         
         
         
         
         
         
         
        if let status { statusItemTunnelStatus = status }
        guard let button = statusItem?.button else { return }
        let showsSpeed = UserDefaults.standard.bool(forKey: ClashMacMenuBarSpeed.key)
        let lines = lines ?? (menuBarTraffic.upLine, menuBarTraffic.downLine)
         
         
        button.image = ClashMacStatusItemLabel.image(
            showsSpeed: showsSpeed,
            upLine: lines.up,
            downLine: lines.down,
            tunnelIsUp: ClashMacQuit.tunnelIsUp(status: statusItemTunnelStatus)
        )
        button.setAccessibilityLabel(ClashMacStatusItemLabel.accessibilityLabel(
            showsSpeed: showsSpeed,
            upLine: lines.up,
            downLine: lines.down
        ))
    }

    private func makeStatusMenuSnapshot() -> ClashMacStatusMenuSnapshot {
         
         
        let snapshot = latestSnapshot
        let listener = proxyShare.terminalListener
        return ClashMacStatusMenuSnapshot(
            phase: snapshot.connection.phase,
            primaryIntent: snapshot.connection.primaryIntent,
            outboundMode: currentOutboundMode,
            selectedRouteName: snapshot.connection.selectedRouteName,
            proxies: menuBarProxyCatalog,
            showsSpeedInMenuBar: UserDefaults.standard.bool(forKey: ClashMacMenuBarSpeed.key),
            hidesDockIcon: UserDefaults.standard.bool(forKey: ClashMacDockIcon.key),
            upLine: menuBarTraffic.upLine,
            downLine: menuBarTraffic.downLine,
            offersQuitLeavingTunnel: false,
            offersShellCommand: listener != nil,
            offersExternalShellCommand: listener?.host(forExternalMachine: true, addresses: proxyShare.reachableAddresses) != nil,
             
            prefersLoopbackShellCommand: false,
            runsPreviousRevision: runsPreviousRevision,
            runningPreviousProfileName: runningPreviousProfileName
        )
    }

     
     
     
     
    private func copyShellCommand(externalIP: Bool) {
        guard let listener = proxyShare.terminalListener else { return }
        guard let host = listener.host(forExternalMachine: externalIP, addresses: proxyShare.reachableAddresses) else { return }
        let text = ProxyEnvironmentCommand.text(
            shell: ProxyEnvironmentShell.remembered(in: .standard),
            endpoint: ProxyEnvironmentEndpoint(
                host: host,
                httpPort: listener.httpPort,
                socksPort: listener.socksPort,
                username: listener.username,
                password: proxyShare.terminalPassword(for: listener)
            )
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
         
         
        ClashMacMenuBarFeedback.confirm(ClashFeedbackCopy.copied("Terminal Command"), locale: preferences.language.locale)
    }

     
     
     
    static func scriptUpdateResult(_ summary: ScriptUpdateSummary) -> ClashFeedbackPresentation {
        let id = "scripts.update"
        if summary.changed.count + summary.unchanged.count + summary.failed.count == 1 {
            if let name = summary.changed.first { return ClashMacFeedbackSentences.updated(name, id: id) }
            if let name = summary.unchanged.first { return ClashMacFeedbackSentences.upToDate(name, id: id) }
            if let failure = summary.failed.first {
                return ClashMacFeedbackSentences.couldNotUpdate(failure.name, reason: failure.reason, id: id)
            }
        }
        let title = ClashFeedbackCopy.batch(updated: summary.changed.count, failed: summary.failed.count,
                                            unchanged: summary.unchanged.count)
        guard summary.failed.isEmpty else {
            let reasons = summary.failed.map { "\($0.name): \($0.reason)" }.joined(separator: "\n")
            return .warning(title: title, message: .verbatim(reasons), isBatchSummary: true,
                            accessibilityIdentifier: "feedback.\(id).summary")
        }
        return summary.changed.isEmpty
            ? .information(title: title, isBatchSummary: true, accessibilityIdentifier: "feedback.\(id).summary")
            : .success(title: title, isBatchSummary: true, accessibilityIdentifier: "feedback.\(id).summary")
    }

     
     
     
    fileprivate func makeStatusMenuActions() -> ClashMacStatusMenuActions {
        var actions = ClashMacStatusMenuActions.none
        actions.primary = { [weak self] in self?.performPrimaryActionFromMenu() }
        actions.cancelStart = { [weak self] in self?.cancelStart() }
        actions.setOutboundMode = { [weak self] mode in
            Task { await self?.changeOutboundMode(mode, from: .menu) }
        }
         
         
        actions.select = { [weak self] group, member in
            self?.pickFromMenu(group: group, member: member)
        }
        actions.currentMember = { [weak self] name in
            guard let self, self.command.isConnected else { return nil }
            return self.nodes.groups.first(where: { $0.name == name })?.now
        }
         
        actions.testGroup = { [weak self] name in
            guard let self, ClashSystemVPNPolicy.isActive(self.vpn.status),
                  let group = self.nodes.groups.first(where: { $0.name == name }) else { return false }
            Task { await self.nodes.test(group: group) }
            return true
        }
        actions.setShowsSpeedInMenuBar = { [weak self] shows in
            UserDefaults.standard.set(shows, forKey: ClashMacMenuBarSpeed.key)
            self?.syncStatusDemand()
            self?.refreshStatusButton()
        }
        actions.setHidesDockIcon = { hides in
            UserDefaults.standard.set(hides, forKey: ClashMacDockIcon.key)
            ClashMacDockIcon.apply(hidesIcon: hides)
        }
         
        actions.openSettings = { [weak self] in
            self?.openMainWindow(from: "menu.settings")
            self?.navigationRequest = .more(.root)
        }
        actions.openApp = { [weak self] in self?.openMainWindow(from: "menu.open") }
        actions.openGroup = { [weak self] group in self?.openProxiesGroup(group) }
        actions.quitLeavingTunnel = {
            ClashMacQuit.nextTermination = .readerQuitLeavingTunnelRunning
            NSApplication.shared.terminate(nil)
        }
        actions.quit = { NSApplication.shared.terminate(nil) }
        actions.copyShellCommand = { [weak self] externalIP in
            self?.copyShellCommand(externalIP: externalIP)
        }
        return actions
    }
}

 
 
 
enum ClashMacLibraryBridge {
    @MainActor static func apply(_ snapshot: ConfigurationLibrarySnapshot) {
        ClashMacSceneModel.current?.configurationLibrary.apply(snapshot)
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
private struct ClashMacLANSharePage: View {
    @ObservedObject var profiles: ProfilesViewModel
    let proxyShare: ProxyShareModel
    let profileID: String
    let rows: ProxyShareSettingsRows

    var body: some View {
        if profiles.activeProfileID == profileID {
            ProxyShareView(model: proxyShare).equatable().environment(\.proxyShareSettingsRows, rows)
        } else {
            ProxyShareMacConfigurationPage(profiles: profiles, profileID: profileID)
                .environment(\.proxyShareSettingsRows, rows)
        }
    }
}

 
private struct ClashMacActiveLANShareRows: View {
    @ObservedObject var profiles: ProfilesViewModel
    let rows: (ClashClientKit.Profile.ID) -> AnyView

    var body: some View {
        if let raw = profiles.activeProfileID, let id = try? ClashClientKit.Profile.ID(raw) {
            rows(id)
        }
    }
}

 
struct ClashMacOriginalEditRefusal: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

 
 
 
 
 
 
 
 
private struct ClashMacOriginalNodeForm: View {
    let profiles: ProfilesViewModel
    let profileID: String
     
    let node: ClashMacOriginalNode?
    let locale: Locale
    let written: @MainActor () async -> Void
    let done: @MainActor () -> Void
    @State private var loaded: Loaded?
    @State private var failure: String?

    struct Loaded {
        let record: ProxyNodeRecord
        let candidates: DialerProxyCandidates
    }

    var body: some View {
        ClashFeatureNavigationContainer {
            if let loaded {
                ProxyNodeDetailsView(
                    record: loaded.record,
                    retest: {},
                    saveNode: { original, edited in try await save(original, edited) },
                    allowsRename: node == nil,
                    showsTesting: false,
                    isNew: node == nil,
                    dialerRouting: .payloadField,
                    dialerCandidates: { loaded.candidates },
                    onDone: { done() },
                    commitTitle: "Save"
                )
            } else if let failure {
                VStack(spacing: 12) {
                    Text(verbatim: failure).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button { done() } label: { Text(clash: .copy("Close")) }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let page = try await profiles.loadConfigurationEditorPage(profileID: profileID)
            let options = RulePolicyOptions.make(document: page.document)
            let name = node?.name ?? ""
            let candidates = DialerProxyCandidates(groups: options.groups.filter { $0.name != name },
                                                   proxies: options.proxies.filter { $0.name != name })
            guard let node else {
                loaded = Loaded(record: CustomNodesView.newNodeTemplate, candidates: candidates)
                return
            }
             
             
            guard let found = ClashMacOriginalNodes.value(of: node, in: page.document),
                  let record = CustomNodesView.record(fromNodeJSON: found.value.serialized()) else {
                failure = ClashCopy.string("Change this one in the source.", locale: locale)
                return
            }
            loaded = Loaded(record: record, candidates: candidates)
        } catch is CancellationError {
        } catch {
            failure = ClashErrorCopy.message(error, locale: locale)
        }
    }

    private func save(_ original: String, _ edited: String) async throws {
        let page = try await profiles.loadConfigurationEditorPage(profileID: profileID)
        let steps: [ConfigurationTextStep]
        if let node {
            guard let found = ClashMacOriginalNodes.value(of: node, in: page.document) else {
                throw ClashMacOriginalEditRefusal(message: ClashCopy.string("Change this one in the source.", locale: locale))
            }
            steps = try OriginalListEdits.nodeEdits(written: found.value, formOriginalJSON: original, formEditedJSON: edited,
                                                    at: [.key("proxies"), .index(found.index)])
        } else {
            let item = OriginalListEdits.handWrittenOrder(try OrderedJSON.parse(edited))
            guard case .string(let name)? = item.node(at: ["name"]), !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw ClashMacOriginalEditRefusal(message: ClashCopy.string("Give the node a name.", locale: locale))
            }
            let nodes = ClashMacOriginalNodes.nodes(in: page.document)
            guard nodes?.contains(where: { $0.name == name }) != true else {
                throw ClashMacOriginalEditRefusal(message: ClashCopy.string(
                    for: .format("A node named “%@” is already in this configuration.", [name]), locale: locale))
            }
            steps = [OriginalListEdits.appending(item, toListOf: nodes?.count, at: "proxies")]
        }
        guard !steps.isEmpty else { return }
        try await ClashMacSceneModel.writeOriginal(profiles: profiles, id: profileID, steps: steps, locale: locale)
        await written()
    }
}

private struct ClashMacDialerCandidatesHost<Content: View>: View {
    let load: @MainActor () async -> DialerProxyCandidates
    @ViewBuilder let content: (@escaping () -> DialerProxyCandidates) -> Content
    @State private var candidates = DialerProxyCandidates.empty

    var body: some View {
        content { candidates }
            .task { candidates = await load() }
    }
}

struct ClashMacImportRequest: Identifiable {
    let purpose: ClashMacSourceImportPurpose
    var tab: ClashMacSourceImportSheet.Tab = .link
     
    var mergeIntoSourceID: String? = nil
    var id: String { (purpose == .rules ? "rules" : "nodes") + "-\(tab.rawValue)" + (mergeIntoSourceID.map { "-into-" + $0 } ?? "") }
}

 
struct ClashMacChainRequest: Identifiable {
    let existingID: String?
    var id: String { existingID ?? "new" }
}

 
struct ClashMacInspectedNode: Identifiable {
    let node: ClashMacSourceNode
    var id: String { "\(node.index)-" + node.name }
}

 
 
struct ClashMacEditingNode: Identifiable {
    let source: ConfigurationSourceRecord
    let node: ClashMacSourceNode
    let record: ProxyNodeRecord
    var id: String { source.id + "#\(node.index)" }
}

 
 
 
 
 
 
 
 
struct ClashMacRuntimePreviewHost: View {
    @ObservedObject var profiles: ProfilesViewModel
    let profileID: String
    let label: String

    var body: some View {
        ProfilePreviewView(title: .verbatim(label)) { [profiles] in
            try await profiles.loadSavedConfigurationPreview(for: profileID)
        }
        .id(profiles.savedConfigurationGeneration)
    }
}

struct ClashMacRuntimePreviewRequest: Hashable, Codable {
    let profileID: String
}

 
 
 
 
struct ClashMacWindowFeedbackHost<Content: View>: View {
    @StateObject private var center = ClashMacFeedback.makeCenter()
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.clashFeedback, center)
            .safeAreaInset(edge: .top, spacing: 0) { ClashMacFeedbackBar(center: center) }
    }
}

struct ClashMacScriptEditorRequest: Hashable, Codable {
    let scriptID: String
}

 
 
 
 
 
 
 
private struct ClashMacConfigurationPageKey: Equatable {
    let profile: ClashProfileSnapshot
    let sources: [ConfigurationSourceRecord]
    let shelves: [ClashMacRuleLibraryShelf]
    let recipe: ConfigurationRecipe?
    let profileURL: String?
    let outlineScheme: ClashMacOutlineScheme?
    let schemeUsage: [String: Int]
    let schemeChoices: [ConfigurationRuleScheme]
    let generation: UInt64
    let isUpdatingSource: Bool
    let updateError: String?
    let edits: Bool
    let linkSharedBy: Int
}

private struct ClashMacFollowsProfilesPage<Content: View>: View {
    let profiles: ProfilesViewModel
    @ViewBuilder let content: () -> Content
    @State private var generation = 0

    var body: some View {
        let _ = generation
        content()
            .onReceive(profiles.$profiles.dropFirst()) { _ in generation &+= 1 }
    }
}

 
private struct ClashMacUpdateFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
private struct ClashMacCentrePresentations: ViewModifier {
    @ObservedObject var model: ClashMacSceneModel
    let actions: ClashMacConfigurationCenterListActions

    func body(content: Content) -> some View {
        content
            .sheet(item: model.configurationCenterImportBinding) { request in
                model.importSheet(request)
                    .clashModalPresentation(.fitted)
                    .environment(\.clashPresentsPanelsAsNativeSheets, true)
            }
            .sheet(isPresented: model.showsConfigurationWizardBinding) {
                model.configurationWizardSheet()
                    .clashModalPresentation(.fitted)
                    .environment(\.clashPresentsPanelsAsNativeSheets, true)
            }
            .sheet(item: model.configurationCenterEditingSchemeBinding) { selection in
                model.ruleEditorSheet(selection)
                    .clashModalPresentation(.fitted)
                    .environment(\.clashPresentsPanelsAsNativeSheets, true)
            }
            .sheet(item: model.configurationCenterChainBinding) { request in
                model.chainSheet(request)
                    .clashModalPresentation(.fitted)
                    .environment(\.clashPresentsPanelsAsNativeSheets, true)
            }
    }
}

 
 
enum ClashMacCentreWindowSheet: Identifiable {
    case importing(ClashMacImportRequest)
    case wizard

    var id: String {
        switch self {
        case .importing(let request): "import-" + request.id
        case .wizard: "wizard"
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
private struct ClashMacCentreWindowSheets: ViewModifier {
    @ObservedObject var model: ClashMacSceneModel

    func body(content: Content) -> some View {
        content
            .sheet(item: model.configurationCenterWindowSheetBinding) { sheet in
                Group {
                    switch sheet {
                    case .importing(let request): model.importSheet(request)
                    case .wizard: model.configurationWizardSheet()
                    }
                }
                .clashModalPresentation(.fitted)
                .environment(\.clashPresentsPanelsAsNativeSheets, true)
            }
    }
}

extension ProfilesViewModel {
     
     
     
     
     
     
    func composingOffTheOriginal(_ id: String, onto scheme: String) async throws {
        try await setUsesOriginalConfiguration(id, enabled: false)
        guard let library = configurationLibraryStore else { return }
        let now = try await Task.detached(priority: .userInitiated) { try library.snapshot() }.value
        guard now.recipes.first(where: { $0.id == id })?.ruleSchemeID != scheme else { return }
        try await switchConfigurationScheme(id, to: scheme)
    }

     
     
     
     
     
     
     
     
    func editingOriginalOffItsLink<Result>(_ id: String, _ edit: () async throws -> Result) async throws -> Result {
        do {
            return try await edit()
        } catch OriginalEditingError.followsSubscription {
            detachingLinkOriginals.insert(id)
            defer { detachingLinkOriginals.remove(id) }
            return try await edit()
        }
    }
}

 
 
 
 
 
 
 
 
enum ClashMacPastedSource {
    static func payload(label: String, text: String, resources: [ExternalResourceImportFile],
                        nodesOnly: Bool) throws -> ConfigurationSourcePayload {
        let original = Data(text.utf8)
        let yaml = try ProxyImportBridge.derivedSubscriptionYAML(from: original, nodesOnly: nodesOnly)
        if let node = try ConfigurationCenterSourceBridge.nodeMaterialPayload(label: label, yaml: yaml) { return node }
        return try ConfigurationCenterSourceBridge.payload(label: label.isEmpty ? "Configuration" : label,
            origin: .file("Configuration.yaml"), original: original, yaml: yaml, resources: resources)
    }
}

 
 
 
 
 
enum ClashMacCustomRuleGroups {
    static func from(_ summary: NodeSummary) -> [String] {
        let listed = summary.groups.values
            .filter { !$0.hidden && $0.name != ProxyBrowsingVisibility.kernelGlobalGroupName }
            .map(\.name)
        let known = Set(listed)
        var seen = Set<String>()
        let ordered = (summary.groupOrder ?? []).filter { known.contains($0) && seen.insert($0).inserted }
        return ordered + listed.filter { !seen.contains($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

 
enum ClashMacRuntimeConfigurationTexts {
     
     
     
     
     
     
     
     
     
    @MainActor
    static func texts(
        large: Bool,
        effective: @MainActor () async -> String?,
        source: @MainActor () async -> String?,
        captured: @escaping @Sendable () -> String?
    ) async -> (source: String?, effective: String?, raw: String?) {
        let effective = await effective()
        if large { return (nil, effective, nil) }
         
         
         
        let source = await source()
        let captured = await Task.detached(priority: .userInitiated) { captured() }.value
        return (captured ?? source, effective, source)
    }
}

 
 
 
 
enum ClashMacOriginalRules {
     
     
     
     
     
     
     
     
    static func documentWithoutKeptRules(profileID: String, store: ConfigurationLibraryStore?) async -> OrderedJSON? {
        guard let store else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> OrderedJSON? in
            guard let snapshot = try? store.snapshot(),
                  let kept = keptSource(profileID: profileID, in: snapshot),
                  let payload = try? store.payload(kept.reference) else { return nil }
            return try? OrderedJSON.parse(payload.documentJSON)
        }.value
    }

     
     
     
     
    static func editorDraft(of page: ProfilesViewModel.ConfigurationEditorPage, id: String) throws -> ConfigurationRuleDraft {
        let edited = page.keptRules == nil ? page.document : page.document.settingTopLevel("rules", to: .array([]))
        return try ConfigurationRuleDraft(originalDocument: edited, id: id, label: page.label)
    }

     
     
     
     
     
     
    static func savedSteps(_ draft: ConfigurationRuleDraft, over before: OrderedJSON,
                           kept: ProfilesViewModel.ConfigurationEditorPage.KeptRules?,
                           locale: Locale) async throws -> [ConfigurationTextStep] {
        let after: OrderedJSON
        if let kept {
            after = draft.currentDocument().removingTopLevel("rules")
            try await refuseTakingAwayWhatKeptRulesUse(from: before, to: after, keptAt: kept.file, locale: locale)
        } else {
            after = try draft.document()
        }
        return ConfigurationDocumentEdits.edits(from: before, to: after).flatMap(textSteps)
    }

     
    static func textSteps(_ edit: ConfigurationPageEdit) -> [ConfigurationTextStep] {
        func keys(_ path: [String]) -> [ConfigurationTextPathStep] { path.map { .key($0) } }
        switch edit {
        case .set(let path, let value):
            return [ConfigurationTextStep(path: keys(path), edit: .set(json: value.serialized()))]
        case .remove(let path):
            return [ConfigurationTextStep(path: keys(path), edit: .delete)]
        case .insert(let path, let index, let value):
            return [ConfigurationTextStep(path: keys(path) + [.index(index)], edit: .insert(json: value.serialized()))]
        case .replace(let path, let index, let value):
            return [ConfigurationTextStep(path: keys(path) + [.index(index)], edit: .set(json: value.serialized()))]
        case .delete(let path, let offsets):
            return offsets.reversed().map { ConfigurationTextStep(path: keys(path) + [.index($0)], edit: .delete) }
        case .insertKey(let path, let key, let value, let before):
            if let before { return [ConfigurationTextStep(path: keys(path) + [.key(before)], edit: .insertBefore(key: key, json: value.serialized()))] }
            return [ConfigurationTextStep(path: keys(path) + [.key(key)], edit: .insert(json: value.serialized()))]
        case .move(let path, let from, let to):
             
            var steps: [ConfigurationTextStep] = []
            var target = to
            for source in from.sorted() {
                let destination = source < target ? target - 1 : target
                steps.append(ConfigurationTextStep(path: keys(path) + [.index(source)], edit: .move(to: destination)))
                if source >= target { target += 1 }
            }
            return steps
        case .renameKey(let path, let from, let to):
            return [ConfigurationTextStep(path: keys(path) + [.key(from)], edit: .rename(to: to))]
        case .moveKeys:
            return []
        }
    }

     
     
     
     
    static func namesGone(from before: OrderedJSON, to after: OrderedJSON) -> [(name: String, ruleSet: Bool, renamed: Bool)] {
        func listed(_ document: OrderedJSON, _ key: String) -> [(name: String, rest: OrderedJSON)] {
            guard case .array(let items)? = document.topLevelValue(key) else { return [] }
            return items.compactMap {
                if case .string(let name)? = $0.topLevelValue("name") { return (name, $0.removingTopLevel("name")) }
                return nil
            }
        }
        func keys(_ document: OrderedJSON, _ key: String) -> [(name: String, rest: OrderedJSON)] {
            guard case .object(let entries)? = document.topLevelValue(key) else { return [] }
            return entries.map { ($0.key, $0.value) }
        }
        func gone(_ read: (OrderedJSON) -> [(name: String, rest: OrderedJSON)], ruleSet: Bool = false)
            -> [(name: String, ruleSet: Bool, renamed: Bool)] {
            let old = read(before), new = read(after)
            let had = Set(old.map(\.name)), has = Set(new.map(\.name))
            return old.enumerated().filter { !has.contains($0.element.name) }.map { place, entry in
                let renamed = place < new.count && !had.contains(new[place].name) && new[place].rest == entry.rest
                return (entry.name, ruleSet, renamed)
            }
        }
        return gone { listed($0, "proxy-groups") }
            + gone({ keys($0, "rule-providers") }, ruleSet: true)
            + gone { keys($0, "sub-rules") }
            + gone { listed($0, "proxies") }
    }

     
     
     
     
     
     
     
    static func refuseTakingAwayWhatKeptRulesUse(from before: OrderedJSON, to after: OrderedJSON,
                                                 keptAt file: URL, locale: Locale) async throws {
        let gone = namesGone(from: before, to: after)
        guard !gone.isEmpty else { return }
        let used = try await Task.detached(priority: .userInitiated) { () -> (String, Bool, [String])? in
            let catalog = try PublishedRules.open(sourceAt: file)
            defer { catalog.close() }
            for (name, ruleSet, renamed) in gone {
                let uses = ruleSet ? try OriginalListEdits.keptUses(ofRuleSet: name, in: catalog)
                    : try OriginalListEdits.keptUses(of: name, in: catalog)
                if !uses.isEmpty { return (name, renamed, uses) }
            }
            return nil
        }.value
        guard let (name, renamed, uses) = used else { return }
        let sentence = renamed
            ? ClashCopy.string(for: .copy("Rules in this configuration's file use this name. Change it in the file, then import it again."), locale: locale)
            : ClashCopy.string(for: .format("“%@” is still in use. Change these first.", [name]), locale: locale)
        throw ClashMacOriginalEditRefusal(message: ([sentence] + uses).joined(separator: "\n"))
    }

     
    static func keepsRules(profileID: String, in snapshot: ConfigurationLibrarySnapshot) -> Bool {
        keptSource(profileID: profileID, in: snapshot) != nil
    }

     
     
    private static func keptSource(profileID: String, in snapshot: ConfigurationLibrarySnapshot)
        -> (source: ConfigurationSourceRecord, reference: ConfigurationSourceVersion)? {
        guard let recipe = snapshot.recipes.first(where: { $0.id == profileID }),
              recipe.preservesOriginal == true else { return nil }
        let source = snapshot.sources.first { ConfigurationSourceVersion($0) == recipe.ruleSource }
            ?? snapshot.sources.first { $0.id == recipe.ruleSource.id }
        guard let source, source.rulesWrittenInOriginal == true else { return nil }
        return (source, recipe.ruleSource)
    }
}

 
 
 
 
 
 
enum ClashMacHomeTally {
     
     
     
     
     
    static func ruleTargets(of overview: RulesOverviewModel) -> [String] {
        overview.buckets.prefix(3).map { "\($0.target) \($0.count)" }
    }

     
     
    static func make(projected: String?, libraryNodes: Int?,
                     publication: ActiveConfigurationPointer? = nil) -> ProfileConfigTally? {
        guard let tally = ProfileConfigTally.make(sourceYAML: projected) else { return nil }
        guard let projected, ConfigTransforms.nodeLibraryPath(in: projected) != nil else {
            return tally.leavingOutTheEngine(of: publication)
        }
        guard let libraryNodes else { return tally }
        return tally.counting(proxies: libraryNodes)
    }

     
     
     
     
     
     
    static func libraryNodes(
        profileID: String, library: String, workingDir: URL?,
        publication: ActiveConfigurationPointer? = nil,
        published: (String) -> Int? = { OfflineProxyCatalogLoader.publishedNodeCount(profileID: $0) }
    ) -> Int? {
        let source = workingDir?.appendingPathComponent("store/\(profileID)/source.yaml")
        let attributes = source.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path) }
         
         
        let engines = ModuleRouteHiding.enginesAmongNodes(of: publication)
        let stamp = [profileID, library, "\(engines)",
                     "\((attributes?[.size] as? NSNumber)?.intValue ?? -1)",
                     "\((attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"]
            .joined(separator: "|")
        lock.lock()
        let kept = counted?.stamp == stamp ? counted?.nodes : nil
        lock.unlock()
        if let kept { return kept }
        guard let nodes = published(profileID).map({ max(0, $0 - engines) }) ?? source
            .flatMap({ try? String(contentsOf: $0, encoding: .utf8) })
            .flatMap({ ConfigurationSections.entryCount(ofSection: "proxies", in: $0) })
        else { return nil }
        lock.lock()
        counted = (stamp, nodes)
        lock.unlock()
        return nodes
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var counted: (stamp: String, nodes: Int)?
}

@MainActor
enum ClashMacWindowFacts {
     
     
    static func line(_ window: NSWindow?, application: NSApplication = .shared) -> String {
         
         
         
         
        let shown = application.windows.filter { $0.isVisible && $0.level == .normal && $0.canBecomeKey }.count
        var facts = #"policy=\#(application.activationPolicy().rawValue) active=\#(application.isActive)"#
            + #" hidden=\#(application.isHidden) shownWindows=\#(shown)"#
        guard let window else { return facts + #" main=none"# }
        let frame = window.frame
        let screen = window.screen.map { #"\#($0.localizedName) \#(NSStringFromRect($0.frame))"# } ?? #"none"#
        let onAnyScreen = NSScreen.screens.contains { $0.frame.intersects(frame) }
        facts += #" main=\#(NSStringFromRect(frame)) visible=\#(window.isVisible) key=\#(window.isKeyWindow)"#
            + #" mini=\#(window.isMiniaturized) onActiveSpace=\#(window.isOnActiveSpace)"#
            + #" occluded=\#(!window.occlusionState.contains(.visible)) screen=\#(screen) onAnyScreen=\#(onAnyScreen)"#
        return facts
    }
}

 
 
 
 
 
 
 
enum ClashMacModulesNotice {
    static func profileID(_ raw: String, in profiles: [Profile]) -> ClashClientKit.Profile.ID? {
        guard let id = try? ClashClientKit.Profile.ID(raw), profiles.contains(where: { $0.id == id.rawValue }) else { return nil }
        return id
    }
}

 
 
 
 
private struct ClashMacModulesNoticePage: View {
    private final class Made: ObservableObject {
        let actions: ClashMacSettingsSectionActions?
        init(_ actions: ClashMacSettingsSectionActions?) { self.actions = actions }
    }

    let section: ConfigurationOutlineSection
    @StateObject private var made: Made

    init(section: ConfigurationOutlineSection, make: @escaping @MainActor () -> ClashMacSettingsSectionActions?) {
        self.section = section
        _made = StateObject(wrappedValue: Made(make()))
    }

    var body: some View {
        if let actions = made.actions {
            ClashMacSettingsChapterPage(section: section, actions: actions)
        } else {
            ClashOpeningCancelButton()
        }
    }
}
