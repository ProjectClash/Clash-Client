import AppIntents
import ClashClientUI
import NetworkExtension
import UniformTypeIdentifiers
import WidgetKit

 
 
 
 
 
 
 
 
 
 
@available(iOS 16.0, *)
enum ClashTunnelShortcut {
     
     
     
     
     
     
     
     
     
    static func sentence(on: Bool) -> LocalizedStringResource {
        on ? "Clash VPN is on." : "Clash VPN is off."
    }

    static func drive(
        _ action: ClashSystemRoute.VPNAction,
        _ act: () async -> Bool
    ) async throws {
        if await act() { return }
        ClashSystemActionDispatch.enqueue(.vpn(action))
        throw ClashTunnelIntentError.configurationUnreachable
    }
}

@available(iOS 16.0, *)
enum ClashTunnelIntentError: LocalizedError {
    case configurationUnreachable

    var errorDescription: String? {
        String(localized: "Clash could not reach its VPN configuration. Open Clash once, then run the shortcut again.")
    }
}

@available(iOS 16.0, *)
struct ConnectClashIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Clash"
    static let description = IntentDescription("Start the installed Clash VPN profile.")
    static var openAppWhenRun: Bool { false }
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @available(iOS 26.0, macOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult {
        try await ClashTunnelShortcut.drive(.connect) {
            await ClashVPNControlDriver.apply(connect: true)
        }
        return .result()
    }
}

@available(iOS 16.0, *)
struct DisconnectClashIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Clash"
    static let description = IntentDescription("Stop the active Clash VPN profile.")
    static var openAppWhenRun: Bool { false }
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @available(iOS 26.0, macOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult {
        try await ClashTunnelShortcut.drive(.disconnect) {
            await ClashVPNControlDriver.apply(connect: false)
        }
        return .result()
    }
}

@available(iOS 16.0, *)
struct ToggleClashIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Clash VPN"
    static let description = IntentDescription("Start or stop Clash based on its current state.")
    static var openAppWhenRun: Bool { false }
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @available(iOS 26.0, macOS 26.0, *)
    static var supportedModes: IntentModes { .background }

     
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        var applied: Bool?
        try await ClashTunnelShortcut.drive(.toggle) {
            applied = await ClashVPNControlDriver.toggle()
            return applied != nil
        }
        return .result(value: applied ?? false)
    }
}

 
 
@available(iOS 16.0, *)
struct GetClashVPNStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Clash VPN Status"
    static let description = IntentDescription("Reports whether the installed Clash VPN profile is connected.")
    static var openAppWhenRun: Bool { false }
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @available(iOS 26.0, macOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let live = await ClashVPNControlDriver.isActive()
        let on = live ?? ClashSystemActionDispatch.handoff.isVPNSnapshotActive
        return .result(
            value: on,
            dialog: IntentDialog(ClashTunnelShortcut.sentence(on: on))
        )
    }
}

@available(iOS 16.0, *)
enum ClashRoutingModeIntentValue: String, AppEnum {
    case rule
    case global
    case direct

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Routing Mode"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .rule: "Rule",
        .global: "Global",
        .direct: "Direct",
    ]

    var route: ClashSystemRoute {
        .mode(ClashSystemRoute.RoutingMode(rawValue: rawValue)!)
    }

     
    var widgetMode: ClashWidgetMode {
        ClashWidgetMode(rawValue: rawValue)!
    }
}

 
 
 
 
 
 
 
 
@available(iOS 16.0, *)
struct SetClashRoutingModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Clash Routing Mode"
    static let description = IntentDescription("Switch Clash between Rule, Global, and Direct routing.")
    static var openAppWhenRun: Bool { false }
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @available(iOS 26.0, macOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Mode")
    var mode: ClashRoutingModeIntentValue

    static var parameterSummary: some ParameterSummary {
        Summary("Set Clash to \(\.$mode)")
    }

     
     
     
     
    func perform() async throws -> some IntentResult {
        try await ClashModeShortcut.set(mode.widgetMode)
        return .result()
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@available(iOS 16.0, *)
enum ClashModeShortcut {
     
     
    static var store: () -> ClashWidgetMailboxStore = { ClashWidgetFactsPublisher.store }

     
    static var status: () async -> NEVPNStatus? = { await ClashVPNControlDriver.currentStatus() }

     
    static var switchRunningTunnel: (ClashWidgetMode) async -> Bool = { mode in
        guard let session = await ClashVPNControlDriver.providerSession(),
              let reply = await ClashClient(session: session).setMode(mode.rawValue),
              let answer = (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any] else { return false }
        return answer[#"error"#] == nil
    }

     
     
     
     
    static var runningGlobalStep: () async -> ClashTunnelOutboundMode.GlobalSwitchStep = {
        guard let session = await ClashVPNControlDriver.providerSession() else { return .notKnown }
        let client = ClashClient(session: session)
        return await ClashTunnelOutboundMode.readGlobalStep(
            summary: { await client.send([#"cmd"#: #"proxiesSummary"#]).map { String(decoding: $0, as: UTF8.self) } },
            members: { group in
                await client.send([#"cmd"#: #"groupMembers"#, #"group"#: group, #"limit"#: ClashTunnelOutboundMode.membersRead])
                    .map { String(decoding: $0, as: UTF8.self) }
            }
        )
    }

     
     
     
    static var storedGlobalChoice: () -> ClashTunnelOutboundMode.StoredGlobalChoice? = {
        NodeProfilePreferencesStore.live()?.load().map {
            .init(selectedMap: $0.selectedMap, currentGroupName: $0.currentGroupName,
                  globalPickedByReader: $0.globalPickedByReader)
        }
    }

     
     
    static var announce: () -> Void = {
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: .clashModeChosenElsewhere, object: nil)
    }

     
    static var log: (String) -> Void = { line in
        ClashLogStore.shared.append(#"shortcut: "# + line, stream: .app, level: .info)
    }

     
     
    static var settleNanoseconds: UInt64 = 10_000_000_000
    static var pollNanoseconds: UInt64 = 100_000_000

     
    private static func settledStatus() async -> NEVPNStatus? {
        var current = await status()
        var waited: UInt64 = 0
        while current == .connecting, waited < settleNanoseconds {
            try? await Task.sleep(nanoseconds: pollNanoseconds)
            waited += pollNanoseconds
            current = await status()
        }
        return current
    }

     
     
     
     
     
     
     
     
     
     
    static func set(_ mode: ClashWidgetMode) async throws {
        let word = mode.rawValue
        let current = await settledStatus()
        let running = current == .connected || current == .reasserting
        if mode == .global {
            if running {
                switch await runningGlobalStep() {
                case .switchNow:
                    break
                case .ask(let exit):
                    log(#"mode global not set: GLOBAL ends on \#(exit.rawValue)"#)
                    throw ClashModeShortcutError.globalWithoutProxy(exit)
                case .refuse:
                    log(#"mode global not set: GLOBAL lists nothing to choose"#)
                    throw ClashModeShortcutError.globalWithoutProxy(.other)
                case .notKnown:
                    log(#"mode global not set: GLOBAL could not be read"#)
                    throw ClashModeShortcutError.globalNotConfirmed
                }
            } else if case .refuse(let exit) = store().readAppFacts()?.globalVerdict
                        ?? ClashTunnelOutboundMode.storedGlobalVerdict(storedGlobalChoice()) {
                 
                 
                 
                log(#"mode global not kept: GLOBAL's stored choice is \#(exit.rawValue)"#)
                throw ClashModeShortcutError.globalWithoutProxy(exit)
            }
        }
        do {
            try store().writeModeChoice(ClashWidgetModeChoice(mode: mode, at: Date()))
        } catch {
            log(#"mode \#(word) not saved: \#(error.localizedDescription)"#)
            throw ClashModeShortcutError.notSaved
        }
        announce()
        guard running else {
            let state = current.map { String($0.rawValue) } ?? #"none"#
            log(#"mode \#(word) saved; no tunnel running (status \#(state)), the next connect uses it"#)
            return
        }
        guard await switchRunningTunnel(mode) else {
            log(#"mode \#(word) saved; the running tunnel did not switch"#)
            throw ClashModeShortcutError.runningTunnelNotSwitched
        }
        log(#"mode \#(word) saved and switched on the running tunnel"#)
    }
}

 
 
 
 
 
 
@available(iOS 16.0, *)
enum ClashModeShortcutError: Error, LocalizedError, CustomLocalizedStringResourceConvertible, Equatable {
    case notSaved
    case runningTunnelNotSwitched
     
    case globalWithoutProxy(ClashTunnelOutboundMode.GlobalExit)
     
    case globalNotConfirmed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notSaved:
            return "Clash could not save the routing mode. Open Clash, then run the shortcut again."
        case .runningTunnelNotSwitched:
            return "Clash could not switch the running VPN. Open Clash to switch it."
         
         
         
        case .globalWithoutProxy(let exit):
            return LocalizedStringResource(stringLiteral: ClashTunnelOutboundMode.notTurnedOnKey(exit))
        case .globalNotConfirmed:
            return LocalizedStringResource(stringLiteral: ClashTunnelOutboundMode.notTurnedOnKey(nil))
        }
    }

    var errorDescription: String? {
        switch self {
        case .notSaved:
            return String(localized: "Clash could not save the routing mode. Open Clash, then run the shortcut again.")
        case .runningTunnelNotSwitched:
            return String(localized: "Clash could not switch the running VPN. Open Clash to switch it.")
        case .globalWithoutProxy(let exit):
            return String(localized: String.LocalizationValue(stringLiteral: ClashTunnelOutboundMode.notTurnedOnKey(exit)))
        case .globalNotConfirmed:
            return String(localized: String.LocalizationValue(stringLiteral: ClashTunnelOutboundMode.notTurnedOnKey(nil)))
        }
    }
}

extension Notification.Name {
     
    static let clashModeChosenElsewhere = Notification.Name(#"ClashModeChosenElsewhere"#)
}

@available(iOS 16.0, *)
struct ImportClashConfigurationIntent: AppIntent {
    static let title: LocalizedStringResource = "Import Clash Configuration"
    static let description = IntentDescription("Import one or more YAML configurations into Clash.")
    static var openAppWhenRun: Bool { true }
    @available(iOS 26.0, macOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(
        title: "Configuration Files",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var files: [IntentFile]

    static var parameterSummary: some ParameterSummary {
        Summary("Import \(\.$files) into Clash")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !files.isEmpty else { return .result(dialog: "No configuration files were provided.") }
        guard let inbox = ProfileShareInbox() else { throw ProfileShareInboxError.unavailable }
        for file in files {
            guard ProfileShareInboxAdmission.accepts(file.data) else {
                throw ProfileInstallLinkError.unsupportedFile
            }
            try inbox.enqueue(file.data)
        }
        ClashSystemActionDispatch.enqueue(.open(.profiles))
        return .result(dialog: "Opening Clash to validate and import the configuration.")
    }
}

@available(iOS 16.0, *)
struct ClashAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
         
         
         
        AppShortcut(
            intent: ConnectClashIntent(),
            phrases: ["Start \(.applicationName)"],
            shortTitle: "Start Clash",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: DisconnectClashIntent(),
            phrases: ["Stop \(.applicationName)"],
            shortTitle: "Stop Clash",
            systemImageName: "power"
        )
        AppShortcut(
            intent: ToggleClashIntent(),
            phrases: ["Toggle \(.applicationName) VPN"],
            shortTitle: "Toggle Clash",
            systemImageName: "arrow.triangle.swap"
        )
        AppShortcut(
            intent: GetClashVPNStatusIntent(),
            phrases: ["Is \(.applicationName) connected"],
            shortTitle: "Get VPN Status",
            systemImageName: "bolt.horizontal.circle"
        )
        AppShortcut(
            intent: SetClashRoutingModeIntent(),
            phrases: ["Set routing mode in \(.applicationName)"],
            shortTitle: "Set Routing Mode",
            systemImageName: "arrow.triangle.branch"
        )
        AppShortcut(
            intent: ImportClashConfigurationIntent(),
            phrases: ["Import configuration into \(.applicationName)"],
            shortTitle: "Import Configuration",
            systemImageName: "square.and.arrow.down"
        )
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
enum ProfileShareInboxAdmission {
    static func accepts(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= ProfileShareInbox.defaultMaximumBytes,
              let text = String(data: data, encoding: .utf8) else { return false }
        do {
            try ConfigTransforms.validateSource(text)
            return true
        } catch {
            return false
        }
    }
}
