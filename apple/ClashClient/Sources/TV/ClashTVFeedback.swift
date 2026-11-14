import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ClashTVFeedback {
     
     
     
     
     
     
     
    static let lifetime = ClashFeedbackLifetime(
        reading: .init(base: 0.5, perCharacter: 0.06, minimum: 4, maximum: 8),
        undo: nil,
        warning: nil,
        error: nil,
        withAction: nil,
        batchSummary: nil
    )

     
     
     
     
     
     
     
     
     
    static let bannerLifetime = ClashFeedbackLifetime(
        reading: lifetime.reading,
        undo: nil,
        warning: nil,
        error: nil,
        withAction: nil,
        batchSummary: nil
    )

     
     
    enum Operation: Hashable {
         
        var isAboutProfile: Bool {
            switch self {
            case .update, .use: true
            default: false
            }
        }

        case connect
        case reinstall
        case use
        case add
        case remove
        case restore
        case update(ClashTVSubscription.ID)
        case script(ClashTVSubscription.ID)
        case mode
        case pin
        case unpin
        case test
        case ipStack
        case autoConnect
        case share
        case remoteControl
        case remoteControlPort
        case remoteControlCertificate

        var key: String {
            switch self {
            case .connect: "connect"
            case .reinstall: "reinstall"
            case .use: "use"
            case .add: "add"
            case .remove: "remove"
            case .restore: "restore"
            case .update(let id): "update:\(id.absoluteString)"
            case .script(let id): "script:\(id.absoluteString)"
            case .mode: "mode"
            case .pin: "pin"
            case .unpin: "unpin"
            case .test: "test"
            case .ipStack: "ipStack"
            case .autoConnect: "autoConnect"
            case .share: "share"
            case .remoteControl: "remoteControl"
            case .remoteControlPort: "remoteControl.port"
            case .remoteControlCertificate: "remoteControl.certificate"
            }
        }
    }

     
    enum Screen: Hashable {
        case home
        case welcome
        case subscriptions
        case subscription(ClashTVSubscription.ID)
        case script(ClashTVSubscription.ID)
        case rules(ClashTVSubscription.ID)
        case autoUpdate(ClashTVSubscription.ID)
        case edit(ClashTVSubscription.ID)
        case add
        case iCloudRestore
        case outboundMode
        case nodes
        case utilities
        case utilitiesDoor(ClashTVUtilitiesHub.Door)
        case connections
        case connectionDetail
        case more
        case moreDoor(ClashTVMoreHub.Door)
        case providers

        var key: String {
            switch self {
            case .home: "home"
            case .welcome: "welcome"
            case .subscriptions: "subscriptions"
            case .subscription(let id): "subscription:\(id.absoluteString)"
            case .script(let id): "script:\(id.absoluteString)"
            case .rules(let id): "rules:\(id.absoluteString)"
            case .autoUpdate(let id): "autoUpdate:\(id.absoluteString)"
            case .edit(let id): "edit:\(id.absoluteString)"
            case .add: "add"
            case .iCloudRestore: "iCloudRestore"
            case .outboundMode: "outboundMode"
            case .nodes: "nodes"
            case .utilities: "utilities"
            case .utilitiesDoor(let door): "utilities:\(door)"
            case .connections: "connections"
            case .connectionDetail: "connectionDetail"
            case .more: "more"
            case .moreDoor(let door): "more:\(door)"
            case .providers: "providers"
            }
        }

         
         
         
         
         
         
         
         
         
        func claims(_ operation: String) -> Bool {
            switch self {
            case .home:
                return ["connect", "reinstall", "use"].contains(operation)
            case .welcome:
                 
                return false
            case .subscriptions:
                 
                 
                return false
            case .subscription(let id):
                return operation == Operation.update(id).key || operation == Operation.script(id).key
            case .script(let id):
                return operation == Operation.update(id).key || operation == Operation.script(id).key
            case .outboundMode:
                return operation == "mode"
            case .nodes:
                return ["pin", "unpin", "test"].contains(operation)
            case .more:
                return operation == "autoConnect"
            case .moreDoor(let door):
                switch door {
                case .ipStack: return operation == "ipStack"
                case .proxyShare: return operation == "share"
                case .externalController: return operation.hasPrefix("remoteControl")
                default: return false
                }
            case .iCloudRestore:
                return operation == "restore"
            case .rules, .autoUpdate, .edit, .add, .utilities, .utilitiesDoor, .connections, .connectionDetail, .providers:
                return false
            }
        }
    }

     
     
     
     
     
     
     
     
     
     

     
     
     
     
     

     
     
     
    static let updatedIdentifier = "tvos.feedback.updated"

    static func updated(_ title: String) -> ClashFeedbackPresentation {
        .success(title: ClashFeedbackCopy.updated(title), accessibilityIdentifier: "tvos.feedback.updated")
    }

     
     
    static func upToDate(_ title: String) -> ClashFeedbackPresentation {
        .success(title: ClashFeedbackCopy.upToDate(title), accessibilityIdentifier: "tvos.feedback.upToDate")
    }

    static func updatedWithWarning(_ title: String, warning: String) -> ClashFeedbackPresentation {
        .warning(title: .format("Updated “%@” with a Warning", [title]), message: .verbatim(warning),
                 accessibilityIdentifier: "tvos.feedback.updatedWithWarning")
    }

    static func couldNotUpdate(_ title: String, reason: String) -> ClashFeedbackPresentation {
        .error(title: ClashFeedbackCopy.couldNotUpdate(title), message: .verbatim(reason),
               accessibilityIdentifier: "tvos.feedback.updateFailed")
    }

    static func scriptUpdated(_ title: String) -> ClashFeedbackPresentation {
        .success(title: .format("Updated the Script for “%@”", [title]), accessibilityIdentifier: "tvos.feedback.scriptUpdated")
    }

    static func couldNotUpdateScript(_ title: String, reason: String) -> ClashFeedbackPresentation {
        .error(title: .format("Couldn’t Update the Script for “%@”", [title]), message: .verbatim(reason),
               accessibilityIdentifier: "tvos.feedback.scriptFailed")
    }

     
     
     
    enum Busy { case connecting, disconnecting, updating, applying }

    static func busy(_ what: Busy) -> ClashFeedbackPresentation {
        let title: ClashDisplayText = switch what {
        case .connecting: "Connecting. Try again in a moment."
        case .disconnecting: "Disconnecting. Try again in a moment."
        case .updating: "Already updating. Try again in a moment."
        case .applying: "Applying a change. Try again in a moment."
        }
        return .information(title: title, accessibilityIdentifier: "tvos.feedback.busy")
    }

    static var connectToTest: ClashFeedbackPresentation {
        .information(title: "Connect to test latency.", accessibilityIdentifier: "tvos.feedback.connectToTest")
    }

     
     
    static func couldNotChangeMode(reason: String) -> ClashFeedbackPresentation {
        .error(title: ClashFeedbackCopy.modeNotChanged, message: .verbatim(reason),
               accessibilityIdentifier: "tvos.feedback.modeFailed")
    }

     
     
     
    static var modeRefused: ClashFeedbackPresentation {
        .error(title: ClashFeedbackCopy.modeNotChanged,
               message: .copy("The mode wasn't switched, so the one before is still in use."),
               accessibilityIdentifier: "tvos.feedback.modeFailed")
    }

     
     
     
    static func globalRefused(_ key: String) -> ClashFeedbackPresentation {
        .error(title: ClashFeedbackCopy.modeNotChanged, message: .copy(key),
               accessibilityIdentifier: "tvos.feedback.globalRefused")
    }

     
     
    static var globalNotConfirmed: ClashFeedbackPresentation {
        .error(title: ClashFeedbackCopy.modeNotChanged,
               message: .copy("Clash couldn't confirm what GLOBAL is set to, so Global mode wasn't turned on. Try again in a moment."),
               accessibilityIdentifier: "tvos.feedback.globalNotConfirmed")
    }

    static func couldNotUse(_ member: String, reason: String) -> ClashFeedbackPresentation {
        .error(title: ClashFeedbackCopy.couldNotSwitch(to: member), message: .verbatim(reason),
               accessibilityIdentifier: "tvos.feedback.pinFailed")
    }

    static func couldNotUnfix(_ group: String, reason: String) -> ClashFeedbackPresentation {
        .error(title: .format("Couldn’t Unfix “%@”", [group]), message: .verbatim(reason),
               accessibilityIdentifier: "tvos.feedback.unpinFailed")
    }

    static func testStopped(reason: String) -> ClashFeedbackPresentation {
        .error(title: "Latency Test Stopped", message: .verbatim(reason), accessibilityIdentifier: "tvos.feedback.testFailed")
    }

     
    static func disconnected(reason: String) -> ClashFeedbackPresentation {
        .error(title: "Clash Disconnected", message: .verbatim(reason), accessibilityIdentifier: "tvos.feedback.disconnected")
    }

    static func couldNotConnect(reason: String) -> ClashFeedbackPresentation {
        .error(title: "Couldn’t Connect", message: .verbatim(reason), accessibilityIdentifier: "tvos.feedback.connectFailed")
    }

    static func couldNotReinstall(reason: String) -> ClashFeedbackPresentation {
        .error(title: "Couldn’t Reinstall the VPN Profile", message: .verbatim(reason),
               accessibilityIdentifier: "tvos.feedback.reinstallFailed")
    }

    static func couldNotSwitchProfile(to title: String, reason: String) -> ClashFeedbackPresentation {
        .error(title: ClashFeedbackCopy.couldNotSwitch(to: title), message: .verbatim(reason),
               accessibilityIdentifier: "tvos.feedback.useFailed")
    }

    static func autoConnectNotSaved(reason: String) -> ClashFeedbackPresentation {
        .error(title: "Connect Automatically Not Changed", message: .verbatim(reason),
               accessibilityIdentifier: "tvos.feedback.autoConnectFailed")
    }

    static func autoConnectUnconfirmed(reason: String) -> ClashFeedbackPresentation {
        .warning(title: "Connect Automatically Not Confirmed Yet", message: .verbatim(reason),
                 accessibilityIdentifier: "tvos.feedback.autoConnectUnconfirmed")
    }

     
     
     
    static var ipStackAppliedWithRestart: ClashFeedbackPresentation {
        .success(title: "IP Stack changed. Clash is reconnecting.", accessibilityIdentifier: "tvos.feedback.ipStackApplied")
    }

     
     
    static func ipStackChangedNotRestarted(reason: String) -> ClashFeedbackPresentation {
        .warning(title: "IP Stack changed, but Clash didn’t reconnect.", message: .verbatim(reason),
                 accessibilityIdentifier: "tvos.feedback.ipStackNotRestarted")
    }

    static func couldNotApplyIPStack(reason: String) -> ClashFeedbackPresentation {
        .error(title: "Couldn’t Change IP Stack", message: .verbatim(reason), accessibilityIdentifier: "tvos.feedback.ipStackFailed")
    }

    static func sharingFailed(reason: String) -> ClashFeedbackPresentation {
        .error(title: "Couldn’t Start Sharing", message: .verbatim(reason), accessibilityIdentifier: "tvos.feedback.shareFailed")
    }

    static func stoppingSharingFailed(reason: String) -> ClashFeedbackPresentation {
        .error(title: "Couldn’t Stop Sharing", message: .verbatim(reason), accessibilityIdentifier: "tvos.feedback.shareStopFailed")
    }

    static func couldNotRestore(reason: String) -> ClashFeedbackPresentation {
        .error(title: "Couldn’t Restore from iCloud", message: .verbatim(reason), accessibilityIdentifier: "tvos.feedback.restoreFailed")
    }

     
     
    static func couldNotMakeCertificate(reason: String) -> ClashFeedbackPresentation {
        .error(title: "Couldn’t Make a Certificate", message: .verbatim(reason),
               accessibilityIdentifier: "tvos.feedback.certificateFailed")
    }

     
     
     
    static let portOutOfRange = ClashFeedbackPresentation.error(
        title: "Use a port from 1024 to 65535.", accessibilityIdentifier: "tvos.feedback.portProblem")

     
     
     
    static func alreadyAdded(_ title: String) -> ClashFeedbackPresentation {
        .information(title: .format("“%@” is already in the list. Its settings were updated.", [title]),
                     accessibilityIdentifier: "tvos.feedback.alreadyAdded")
    }

    static func restored(count: Int) -> ClashFeedbackPresentation {
        .success(title: count == 1 ? "Restored 1 Profile" : .format("Restored %@ Profiles", [count.formatted()]),
                 accessibilityIdentifier: "tvos.feedback.restored")
    }

     
     
     
     
    static var everyRow: [ClashDisplayText] {
        let n = "n", r = "r"
        let results: [ClashFeedbackPresentation] = [
            updated(n), updatedWithWarning(n, warning: r), couldNotUpdate(n, reason: r), scriptUpdated(n),
            couldNotUpdateScript(n, reason: r), busy(.connecting), busy(.disconnecting), busy(.updating), busy(.applying), connectToTest,
            disconnected(reason: r), ipStackChangedNotRestarted(reason: r),
            couldNotChangeMode(reason: r), modeRefused, globalNotConfirmed,
            globalRefused(ClashTunnelOutboundMode.nothingToChooseKey), globalRefused(ClashTunnelOutboundMode.globalNotLoadedKey),
            couldNotUse(n, reason: r), couldNotUnfix(n, reason: r), testStopped(reason: r),
            couldNotConnect(reason: r), couldNotReinstall(reason: r), couldNotSwitchProfile(to: n, reason: r),
            autoConnectNotSaved(reason: r), autoConnectUnconfirmed(reason: r), ipStackAppliedWithRestart,
            couldNotApplyIPStack(reason: r), sharingFailed(reason: r), stoppingSharingFailed(reason: r),
            couldNotRestore(reason: r), alreadyAdded(n), restored(count: 1), restored(count: 2),
            couldNotMakeCertificate(reason: r), portOutOfRange,
        ]
         
         
        return results.flatMap { [$0.title] + [$0.message].compactMap { $0 } }.filter {
            if case .verbatim = $0 { return false }
            return true
        }
    }



     

     
     
     
    static func spoken(_ presentation: ClashFeedbackPresentation) -> String {
         
         
        [text(presentation.title), presentation.message.map(text)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ": ")
    }

     
     
    static func text(_ row: ClashDisplayText) -> String {
        switch row {
        case .copy(let key):
            return key.localizedForTelevision
        case .verbatim(let words):
            return words
        case .format(let format, let arguments):
            return splice(format.localizedForTelevision, arguments)
        case .formatCopy(let format, let arguments):
            return splice(format.localizedForTelevision, arguments.map(\.localizedForTelevision))
        }
    }

    private static func splice(_ format: String, _ arguments: [String]) -> String {
        var pieces = ClashDisplayText.formatSegments(of: format)
        var line = pieces.removeFirst()
        for (index, piece) in pieces.enumerated() {
            line += index < arguments.count ? arguments[index] : ""
            line += piece
        }
        return line
    }
}

extension ClashTVProductState {
     
     
     
     
     
     
     
    mutating func post(
        _ presentation: ClashFeedbackPresentation,
        for operation: ClashTVFeedback.Operation,
        remembers: Bool = true,
        at moment: Date = Date()
    ) {
         
         
        let inPlace = feedbackPlace?.claims(operation.key) ?? false
         
         
         
         
        if !inPlace, presentation.kind == .success { return }
        feedback.show(presentation, screen: feedbackPlace?.key, operation: operation.key,
                      characters: ClashTVFeedback.spoken(presentation).count,
                      now: moment, lifetime: inPlace ? ClashTVFeedback.lifetime : ClashTVFeedback.bannerLifetime)
        guard remembers, presentation.kind == .error || presentation.kind == .warning else { return }
         
         
        note(problem: ClashTVFeedback.spoken(presentation), at: moment,
             aboutProfile: operation.isAboutProfile && presentation.kind == .error)
    }

     
     
     
    mutating func beginOperation() {
         
         
        feedback.clear()
    }

     
     
     
     
    mutating func enterFeedbackScreen(_ screen: ClashTVFeedback.Screen, from previous: ClashTVFeedback.Screen,
                                      now: Date = Date()) {
        feedbackPlace = screen
         
         
         
         
         
         
        for entry in [feedback.current, feedback.covered].compactMap({ $0 })
        where entry.screen == nil && entry.presentation.kind != .loading {
            let inPlace = entry.operation.map(screen.claims) ?? false
            feedback.update(entry.id, to: entry.presentation, screen: screen.key, now: now,
                            lifetime: inPlace ? ClashTVFeedback.lifetime : ClashTVFeedback.bannerLifetime)
        }
        guard previous != screen else { return }
        if let entry = feedback.current, let operation = entry.operation, screen.claims(operation),
           entry.deadline == nil, entry.presentation.kind != .loading {
            feedback.update(entry.id, to: entry.presentation, screen: screen.key, now: now,
                            lifetime: ClashTVFeedback.lifetime)
        }
        feedback.leaveScreen(previous.key)
    }

     
     
    mutating func settle(_ operation: ClashTVFeedback.Operation) {
        if let covered = feedback.covered, covered.operation == operation.key { feedback.dismiss(covered.id) }
        if let showing = feedback.current, showing.operation == operation.key { feedback.dismiss(showing.id) }
    }

     
    func feedback(for operations: [ClashTVFeedback.Operation]) -> ClashFeedbackPresentation? {
        guard let entry = feedback.current, let key = entry.operation,
              operations.contains(where: { $0.key == key }) else { return nil }
        return entry.presentation
    }
}

 
 
 
struct ClashTVFeedbackLine: View {
    let presentation: ClashFeedbackPresentation
     
     
     
     
     
    var compact = false

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: compact ? 0 : 4) {
                 
                 
                 
                 
                 
                 
                Text(clash: presentation.title)
                    .foregroundStyle(Color.primary)
                    .lineLimit(compact ? 1 : 2)
                    .minimumScaleFactor(0.75)
                if let message = presentation.message {
                    if compact {
                        Text(clash: message)
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text(clash: message)
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } icon: {
            Image(systemName: Self.symbol(presentation.kind))
                .foregroundStyle(Self.tint(presentation.kind))
        }
        .font(.body)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ClashTVFeedback.spoken(presentation))
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
    }

    static func symbol(_ kind: ClashFeedbackPresentation.Kind) -> String {
        switch kind {
        case .loading, .information: ClashSymbol.infoCircleFill.rawValue
        case .success: ClashSymbol.checkmarkCircleFill.rawValue
        case .warning: ClashSymbol.exclamationmarkTriangleFill.rawValue
        case .error: ClashSymbol.xmarkOctagonFill.rawValue
        }
    }

     
     
    static func tint(_ kind: ClashFeedbackPresentation.Kind) -> Color {
        switch kind {
        case .loading, .information, .success: .secondary
        case .warning: .orange
        case .error: .red
        }
    }
}

 
 
 
 
 
 
struct ClashTVFeedbackBanner: View {
    let presentation: ClashFeedbackPresentation

    var body: some View {
        ClashTVFeedbackLine(presentation: presentation, compact: true)
            .padding(.horizontal, 28)
             
             
            .padding(.vertical, 8)
             
             
            .frame(maxWidth: 600, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .allowsHitTesting(false)
            .focusable(false)
             
             
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tvos.feedback.banner")
    }
}
