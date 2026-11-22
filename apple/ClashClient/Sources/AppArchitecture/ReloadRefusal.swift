import ClashClientUI
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
     
     
     
     
    static let configurationMessage = ClashHomeConnectionIssue.configurationRefusalRow
     
    static let startMessage = "The core couldn’t start: %@"

     
    let message: String
     
    let words: String
     
     
     
     
    var profileID: String? = nil
     
     
     
    var revision: String? = nil

     
    var requested: StartupOutcomeRecord.Revision? {
        guard let profileID, let revision else { return nil }
        return StartupOutcomeRecord.Revision(profileID: profileID, revision: revision)
    }

    static func isLead(_ message: String) -> Bool {
        message == configurationMessage || message == startMessage
    }

     
     
    func isAbout(selected: String?) -> Bool {
        guard let profileID else { return true }
        return profileID == selected
    }

     
     
     
     
     
     
    static func from(error: NSError?, record: StartupOutcomeRecord?, issuedAt: Date? = nil) -> CoreStartRefusal? {
        guard let error, error.domain == ClashTunnelStart.startErrorDomain,
              error.code == ClashTunnelStart.StartErrorCode.coreRefused.rawValue,
              let record, record.outcome == .refused, issuedAt.map(record.answersStart(issuedAt:)) ?? true
        else { return nil }
        return named(by: record)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    static func from(record: StartupOutcomeRecord?, sameAs reason: String?) -> CoreStartRefusal? {
        guard let record, let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines),
              reason == record.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        return named(by: record)
    }

     
     
    private static func named(by record: StartupOutcomeRecord) -> CoreStartRefusal? {
        guard record.operation == "start", record.outcome == .refused || record.outcome == .backedOff,
              let words = record.message?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty,
              !NodeLibraries.isUnavailable(words)
        else { return nil }
        let asked = record.requested.flatMap { $0.profileID.isEmpty ? nil : $0 }
        return CoreStartRefusal(message: record.errorClass == .config ? configurationMessage : startMessage,
                                words: String(words.prefix(512)),
                                profileID: asked?.profileID, revision: asked?.revision)
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct OnDemandRefusalPause: Equatable, Sendable {
     
    enum Refusal: Equatable, Sendable {
         
         
         
        case configuration
         
        case other
         
        case none
    }

     
     
     
    static let note = "Connect On Demand is paused. It resumes the next time you connect."

     
     
     
     
    enum Cause: String, Equatable, Sendable {
        case configuration
        case memory
    }

     
     
    static let memoryNote = "Connect On Demand is paused so the VPN doesn't keep disconnecting. It resumes the next time you connect."

     
     
    let profileID: String
    let revision: String
    var cause: Cause = .configuration
     
     
    var footprintBytes: Int64? = nil
     
     
     
    var stoppedWhileUp: Bool = true

     
     
     
    static let defaultsKey = "onDemand.pausedForRefusal"

    static func load(from defaults: UserDefaults) -> OnDemandRefusalPause? {
        guard let stored = defaults.dictionary(forKey: defaultsKey),
              let profileID = stored["profileID"] as? String,
              let revision = stored["revision"] as? String
        else { return nil }
         
        let cause = (stored["cause"] as? String).flatMap(Cause.init(rawValue:)) ?? .configuration
        return OnDemandRefusalPause(profileID: profileID, revision: revision, cause: cause,
                                    footprintBytes: (stored["footprintBytes"] as? NSNumber)?.int64Value,
                                    stoppedWhileUp: stored["stoppedWhileUp"] as? Bool ?? true)
    }

    func save(to defaults: UserDefaults) {
        var stored: [String: Any] = ["profileID": profileID, "revision": revision]
        if cause != .configuration { stored["cause"] = cause.rawValue }
        if let footprintBytes { stored["footprintBytes"] = NSNumber(value: footprintBytes) }
        if !stoppedWhileUp { stored["stoppedWhileUp"] = false }
        defaults.set(stored, forKey: Self.defaultsKey)
    }

    static func clear(in defaults: UserDefaults) {
        guard defaults.object(forKey: defaultsKey) != nil else { return }
        defaults.removeObject(forKey: defaultsKey)
    }

     
     
    func isAbout(_ refused: StartupOutcomeRecord.Revision?) -> Bool {
        guard let refused else { return false }
        return refused.profileID == profileID && refused.revision == revision
    }

     
     
     
     
     
    static let loopRecordFreshness: TimeInterval = 180

     
     
     
     
     
     
     
     
    static func pause(for record: StartupOutcomeRecord?, published: ActiveConfigurationPointer?,
                      onDemandEnabled: Bool, readerIsStopping: Bool,
                      notOlderThan: TimeInterval? = nil, now: Date = Date()) -> OnDemandRefusalPause? {
         
         
        guard onDemandEnabled, !readerIsStopping, refusal(in: record) == .configuration,
              let requested = record?.requested, speaksOf(record, published: published)
        else { return nil }
        if let notOlderThan {
            guard let at = record?.at else { return nil }
            let age = now.timeIntervalSince(at)
            guard age < notOlderThan, -age < notOlderThan else { return nil }
        }
        return OnDemandRefusalPause(profileID: requested.profileID, revision: requested.revision)
    }

     
     
     
    func stands(given record: StartupOutcomeRecord?) -> Bool {
        Self.refusal(in: record) == .configuration && isAbout(record?.requested)
    }

    static func refusal(in record: StartupOutcomeRecord?) -> Refusal {
        guard let record, record.operation == "start", record.outcome == .refused else { return .none }
         
         
        if NodeLibraries.isUnavailable(record.message) { return .other }
        return record.errorClass == .config ? .configuration : .other
    }

     
     
    static func speaksOf(_ record: StartupOutcomeRecord?, published: ActiveConfigurationPointer?) -> Bool {
        guard let requested = record?.requested, let published else { return false }
        return requested.profileID == published.profileID && requested.revision == published.revision
    }

     
     
    func logLine(profileName: String?, after trigger: String) -> String {
        let name = profileName ?? "?"
        if cause == .memory {
            let used = footprintBytes.map(String.init) ?? "?"
            return "vpn on-demand paused: iOS stopped the tunnel for memory, On Demand would start it into the same again  profile=\(name) id=\(profileID) revision=\(revision) footprintBytes=\(used) after=\(trigger)"
        }
        return "vpn on-demand paused: the core refuses this configuration, nothing to fall back to  profile=\(name) id=\(profileID) revision=\(revision) after=\(trigger)"
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
