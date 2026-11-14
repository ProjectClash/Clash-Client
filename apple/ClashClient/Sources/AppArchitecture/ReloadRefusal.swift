import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ReloadRefusal {

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func isRaceWithActivation(_ reason: String?) -> Bool {
        guard let reason, !reason.isEmpty else { return false }
        let text = reason.lowercased()
        return text.contains("silent") || text.contains("service not running")
    }
}

 
 
 
 
 
 
 
 
enum ReloadErrorClass: String, Equatable, Sendable {
     
    case config
     
    case memory
     
    case restart
     
    case committed
     
    case unknown

     
     
     
    var needsRestart: Bool {
        switch self {
        case .memory, .restart, .unknown: return true
        case .config, .committed: return false
        }
    }

     
     
     
    static func of(reply json: [String: Any]) -> ReloadErrorClass? {
        let named = (json["errorClass"] as? String)
            .flatMap { ReloadErrorClass(rawValue: $0.lowercased()) }
        if let named { return named }
        if json["error"] != nil || json["errorClass"] != nil { return .unknown }
        return nil
    }
}

 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class TunnelApplicationGate {
    private var held = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard held else {
            held = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

     
    func release() {
        if waiting.isEmpty {
            held = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}

 
 
 
enum HandoverRevision {
     
     
     
     
    static func superseded(_ expected: ActiveConfigurationPointer?, container: URL?) -> Bool {
        guard let expected, let container,
              let now = (try? ConfigResourceStore(containerURL: container))?.activeIdentityWithoutLock() else { return false }
        return now != expected
    }

     
     
     
    static func running(_ expected: ActiveConfigurationPointer?, container: URL?) -> StartupOutcomeRecord? {
        guard let expected, let record = StartupOutcomeRecord.read(from: container), let running = record.running,
              running.profileID == expected.profileID, running.revision == expected.revision else { return nil }
        return record
    }

     
     
     
     
    static func acknowledged(_ expected: ActiveConfigurationPointer?, container: URL?) -> Bool {
        expected == nil || running(expected, container: container) != nil
    }

     
     
    static func publishedNow(container: URL?) async -> (pointer: ActiveConfigurationPointer, intent: PlatformConfigIntent)? {
        guard let container else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> (pointer: ActiveConfigurationPointer, intent: PlatformConfigIntent)? in
            guard let store = try? ConfigResourceStore(containerURL: container),
                  let current = try? store.loadCurrent(), let yaml = current.text,
                  let json = PreflightService.intentApplication(finalYAML: yaml).intentJSON,
                  let intent = try? JSONDecoder().decode(PlatformConfigIntent.self, from: Data(json.utf8)) else { return nil }
            return (ActiveConfigurationPointer(profileID: current.profileID, revision: current.revision), intent)
        }.value
    }
}

enum TunnelApplyOutcome: Equatable, Sendable {
     
     
    case applied(warning: String?)
     
     
    case keptRunning(String)
     
    case restarted
     
    case savedForNext
     
     
    case failed(String)
     
     
     
    case pending

    var tunnelRunsTheNewConfiguration: Bool {
        switch self {
        case .applied, .restarted: return true
        case .keptRunning, .savedForNext, .failed, .pending: return false
        }
    }
}

 
enum ReloadVerdict: Equatable, Sendable {
     
     
    case applied(warning: String?)
     
    case keep(String)
     
    case restart(String)

    static func of(reply json: [String: Any]) -> ReloadVerdict {
        guard let named = ReloadErrorClass.of(reply: json) else { return .applied(warning: nil) }
        let sentence = json["error"] as? String ?? ""
        switch named {
        case .committed: return .applied(warning: json["warning"] as? String)
        case .config: return .keep(sentence)
        case .memory, .restart, .unknown: return .restart(sentence)
        }
    }
}

 
 
 
 
 
 
 
 
enum ReloadFollowUp: Equatable, Sendable {
     
    case applied(warning: String?)
     
    case keep(String)
     
     
    case restart(forNewSettings: Bool)
     
     
     
    case leaveDown

     
     
    static func after(_ asked: ActivationDecision, reloaded: Bool, verdict: ReloadVerdict?,
                      sessionUp: Bool, readerStopped: Bool, cancelled: Bool) -> ReloadFollowUp {
        if !reloaded, case .keep(let reason)? = verdict { return .keep(reason) }
        if reloaded, asked != .restart {
            if case .applied(let warning)? = verdict { return .applied(warning: warning) }
            return .applied(warning: nil)
        }
        guard !cancelled, !readerStopped, sessionUp else { return .leaveDown }
        return .restart(forNewSettings: asked == .restart)
    }
}

extension Notification.Name {
     
     
     
     
    static let clashTunnelOutcomeRecorded = Notification.Name("ClashTunnelOutcomeRecorded")
}

 
 
 
 
struct StartupOutcomeRecord: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case started, reloaded, recoveredFromLastKnownGood, refusedKeptRunning, refused, backedOff
        case unknown(String)

        init(_ raw: String) {
            switch raw {
            case "started": self = .started
            case "reloaded": self = .reloaded
            case "recoveredFromLastKnownGood": self = .recoveredFromLastKnownGood
            case "refusedKeptRunning": self = .refusedKeptRunning
            case "refused": self = .refused
            case "backedOff": self = .backedOff
            default: self = .unknown(raw)
            }
        }
    }

    struct Revision: Decodable, Equatable, Sendable {
        let profileID: String
        let revision: String
    }

     
     
     
     
    static let fileName = ClashTunnelStart.outcomeFileName

    let operation: String?
    let outcome: Outcome
    let errorClass: ReloadErrorClass?
     
    let message: String?
    let requested: Revision?
    let running: Revision?
     
    let at: Date?
     
     
     
    var userInitiated: Bool? = nil
     
     
     
    var quarantined: Revision? = nil

     
     
     
    var runsPreviousRevision: Bool {
        outcome == .recoveredFromLastKnownGood || outcome == .refusedKeptRunning
    }

     
     
    func homeShowsPreviousRevision(vpnStatus: String) -> Bool {
        runsPreviousRevision && ["connected", "reasserting"].contains(
            vpnStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static func read(from container: URL?) -> StartupOutcomeRecord? {
        guard let container,
              let data = try? Data(contentsOf: container.appendingPathComponent(fileName)),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let outcome = json["outcome"] as? String else { return nil }
        func revision(_ key: String) -> Revision? {
            guard let value = json[key] as? [String: Any],
                  let profileID = value["profileID"] as? String,
                  let revision = value["revision"] as? String else { return nil }
            return Revision(profileID: profileID, revision: revision)
        }
         
         
        let quarantined = json["quarantined"] as? [String: Any]
        return StartupOutcomeRecord(
            operation: json["operation"] as? String,
            outcome: Outcome(outcome),
            errorClass: (json["errorClass"] as? String).map { ReloadErrorClass(rawValue: $0) ?? .unknown },
            message: json["message"] as? String ?? quarantined?["message"] as? String,
            requested: revision("requested"),
            running: revision("running"),
            at: (json["at"] as? String).flatMap(Self.date),
            userInitiated: json["userInitiated"] as? Bool,
            quarantined: revision("quarantined")
        )
    }

    private static func date(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

     
     
     
    var warningForRunning: String? {
        guard requested == running, errorClass == .committed else { return nil }
        return message
    }

     
     
     
    func answersStart(issuedAt: Date) -> Bool {
        guard operation == "start", let at else { return false }
        return at.timeIntervalSince(issuedAt.addingTimeInterval(-1)) >= 0
    }

     
     
     
     
     
     
     
    static func settlement(of record: StartupOutcomeRecord?, issuedAt: Date, connected: Bool,
                           fallbackReason: String) -> TunnelApplyOutcome? {
        let own = record.flatMap { $0.answersStart(issuedAt: issuedAt) ? $0 : nil }
        guard connected else {
             
             
            if LibraryGoneRepublish.owes(own, answered: nil) {
                return .failed(String(localized: String.LocalizationValue(LibraryGoneRepublish.readerSentence)))
            }
            return .failed(own?.message ?? fallbackReason)
        }
        guard let own, own.outcome == .recoveredFromLastKnownGood else { return nil }
        return .keptRunning(own.message ?? "")
    }

     
     
     
    func runningProfileID(ifNot selected: String?) -> String? {
        guard let running = running?.profileID, running != selected else { return nil }
        return running
    }
}

 
 
 
 
 
struct CoreStartRefusal: Equatable, Sendable {
     
     
    static let configurationMessage = "The core rejected this configuration: %@"
     
    static let startMessage = "The core couldn’t start: %@"

     
    let message: String
     
    let words: String

    static func isLead(_ message: String) -> Bool {
        message == configurationMessage || message == startMessage
    }

     
     
     
     
     
     
    static func from(error: NSError?, record: StartupOutcomeRecord?, issuedAt: Date? = nil) -> CoreStartRefusal? {
        guard let error, error.domain == ClashTunnelStart.startErrorDomain,
              error.code == ClashTunnelStart.StartErrorCode.coreRefused.rawValue,
              let record, record.operation == "start", record.outcome == .refused,
              issuedAt.map(record.answersStart(issuedAt:)) ?? true,
              let words = record.message?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty,
              !NodeLibraries.isUnavailable(words)
        else { return nil }
        return CoreStartRefusal(message: record.errorClass == .config ? configurationMessage : startMessage,
                                words: String(words.prefix(512)))
    }
}

 
 
 
 
@MainActor
final class StartupOutcomeWatcher: ObservableObject {
    @Published private(set) var record: StartupOutcomeRecord?
    private let read: () -> StartupOutcomeRecord?
    private let center: NotificationCenter
    private var observer: NSObjectProtocol?

    init(center: NotificationCenter = .default,
         read: @escaping () -> StartupOutcomeRecord? = {
             StartupOutcomeRecord.read(from: ClashAppIdentifiers.appGroupContainer)
         }) {
        self.read = read
        self.center = center
        record = read()
        observer = center.addObserver(forName: .clashTunnelOutcomeRecorded, object: nil, queue: nil) { [weak self] _ in
             
             
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.refresh() }
            } else {
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    deinit {
        if let observer { center.removeObserver(observer) }
    }

    func refresh() {
        let next = read()
        if next != record { record = next }
    }
}
