import Foundation

 
 
 
 
 
 
 
 
 
struct ClashTVRefusalPause: Equatable {
     
    enum Refusal: Equatable {
         
         
        case configuration
         
        case other
         
        case none
    }

     
    let profileID: String
    let revision: String

     
     
     
    static let defaultsKey = "onDemand.pausedForRefusal"

     
     
     
     
    static let loopRecordFreshness: TimeInterval = 600

     
    static var pausedNote: String {
        String(localized: "Connect Automatically is paused. It resumes the next time you connect.")
    }

     
    static let wordsLimit = 512

    static func refusal(in record: ClashStartupOutcomeRecord?) -> Refusal {
        guard let record, record.operation == "start", record.outcome == .refused else { return .none }
         
         
        if NodeLibraries.isUnavailable(record.message) { return .other }
        return record.errorClass == "config" ? .configuration : .other
    }

     
     
     
     
     
    static func pause(for record: ClashStartupOutcomeRecord?, published: ActiveConfigurationPointer?,
                      onDemandEnabled: Bool, tunnelUp: Bool, readerIsStopping: Bool,
                      notOlderThan: TimeInterval?, now: Date) -> ClashTVRefusalPause? {
        guard onDemandEnabled, !tunnelUp, !readerIsStopping, refusal(in: record) == .configuration,
              let requested = record?.requested, let published,
              requested.profileID == published.profileID, requested.revision == published.revision
        else { return nil }
        if let notOlderThan {
            guard let at = record?.at else { return nil }
            let age = now.timeIntervalSince(at)
            guard age < notOlderThan, -age < notOlderThan else { return nil }
        }
        return ClashTVRefusalPause(profileID: requested.profileID, revision: requested.revision)
    }

    func isAbout(_ revision: ClashStartupOutcomeRecord.Revision?) -> Bool {
        guard let revision else { return false }
        return revision.profileID == profileID && revision.revision == self.revision
    }

     
     
    func stands(given record: ClashStartupOutcomeRecord?) -> Bool {
        Self.refusal(in: record) == .configuration && isAbout(record?.requested)
    }

     
     
    static func homeSentence(for record: ClashStartupOutcomeRecord?) -> String? {
        let refusal = refusal(in: record)
        guard refusal != .none, let message = record?.message, !message.isEmpty else { return nil }
        let words = String(message.prefix(wordsLimit))
        let lead = refusal == .configuration
            ? String(localized: "This configuration can’t be used: %@")
            : String(localized: "Clash couldn’t start: %@")
        return String(format: lead, words)
    }

    static func load(from defaults: UserDefaults) -> ClashTVRefusalPause? {
        guard let stored = defaults.dictionary(forKey: defaultsKey),
              let profileID = stored["profileID"] as? String,
              let revision = stored["revision"] as? String
        else { return nil }
        return ClashTVRefusalPause(profileID: profileID, revision: revision)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(["profileID": profileID, "revision": revision], forKey: Self.defaultsKey)
    }

    static func clear(in defaults: UserDefaults) {
        guard defaults.object(forKey: defaultsKey) != nil else { return }
        defaults.removeObject(forKey: defaultsKey)
    }

     
    func logLine(after trigger: String) -> String {
        "vpn on-demand paused: the core refuses this configuration, nothing to fall back to  id=\(profileID) revision=\(revision) after=\(trigger)"
    }
}
