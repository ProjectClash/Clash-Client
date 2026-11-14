import ClashClientKit
import Foundation

 
 
 
 
 
 
 
 
struct ModulePublicationSummary: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var at: Date
     
    var engineInjected: Bool
     
    var certEntryIP: String?
     
     
    var degradedBecause: [String]
     
     
    var notApplied: AuthoredText?
     
     
     
     
     
     
    var skipped: [ModuleIgnoredEntry]?
     
     
     
    var changes: [ModuleChange]?
     
     
     
    var profileID: String?

     
     
     
    init(at: Date, engineInjected: Bool, certEntryIP: String?, reasons: [ModuleDegradeReason], notApplied: AuthoredText?,
         skipped: [ModuleIgnoredEntry] = [], changes: [ModuleChange] = []) {
        schemaVersion = Self.currentSchemaVersion
        self.at = at
        self.engineInjected = engineInjected
        self.certEntryIP = certEntryIP
        self.skipped = skipped.isEmpty ? nil : skipped
        self.changes = changes.isEmpty ? nil : changes
        var words = notApplied
        var kept: [ModuleDegradeReason] = []
        for reason in reasons {
            if case .notApplied(let text) = reason {
                if words == nil { words = text }
            } else {
                kept.append(reason)
            }
        }
        degradedBecause = kept.map(\.spelling)
        self.notApplied = words
    }

     
    var reasons: [ModuleDegradeReason] { degradedBecause.compactMap(ModuleDegradeReason.init(spelling:)) }

     
    static func summary(of publication: ProfileActivationCoordinator.ModulePublication?, at: Date,
                        profileID: String? = nil) -> ModulePublicationSummary? {
        guard let publication else { return nil }
        var summary = ModulePublicationSummary(at: at, engineInjected: publication.record != nil,
                                                certEntryIP: publication.record == nil ? nil : publication.certEntryIP,
                                                reasons: publication.degradedBecause, notApplied: nil,
                                                skipped: publication.skipped, changes: publication.changes)
        summary.profileID = profileID
        return summary
    }

     
     
     
    static func load(locations: ModuleLocations?) -> ModulePublicationSummary? {
        guard let locations, let data = try? Data(contentsOf: locations.publicationSummary),
              let summary = try? ModuleJSON.decoder().decode(ModulePublicationSummary.self, from: data),
              summary.schemaVersion <= currentSchemaVersion else { return nil }
        return summary
    }

     
     
     
     
    static func store(_ summary: ModulePublicationSummary?, locations: ModuleLocations,
                      write: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        let url = locations.publicationSummary
        guard let summary else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try write(try ModuleJSON.encoder().encode(summary), url)
        } catch {
             
             
            let reason = error.localizedDescription
            let line: String
            if !FileManager.default.fileExists(atPath: url.path) {
                line = "modules: the publication summary was not written (\(reason)); there was none before it"
            } else if (try? FileManager.default.removeItem(at: url)) != nil {
                line = "modules: the publication summary was not written (\(reason)); the one before it was removed"
            } else {
                line = "modules: the publication summary was not written (\(reason)); the one before it could not be removed either"
            }
            ClashLogStore.shared.append(line, stream: .app)
        }
    }
}

extension ModuleLocations {
     
     
    var publicationSummary: URL { container.appendingPathComponent("working/adblock/publication.json") }
}

extension ModuleDegradeReason {
     
     
     
     
     
    var spelling: String {
        switch self {
        case .engineUnavailable: return "engineUnavailable"
        case .certificateNotTrusted: return "certificateNotTrusted"
        case .certificateMissing: return "certificateMissing"
        case .certificateUnusable: return "certificateUnusable"
        case .stoppedForMemory: return "stoppedForMemory"
        case .portsTaken: return "portsTaken"
        case .noCertificateAddress: return "noCertificateAddress"
        case .groupsNotAdjustable: return "groupsNotAdjustable"
        case .sectionNotAdjustable(let key): return "sectionNotAdjustable:" + key
        case .alreadyPublished: return "alreadyPublished"
        case .moduleRulesLeftOut: return "moduleRulesLeftOut"
        case .moduleEntriesLeftOut: return "moduleEntriesLeftOut"
        case .moduleSettingsLeftOut: return "moduleSettingsLeftOut"
        case .engineNameTaken: return "engineNameTaken"
        case .snifferWrittenOff(let keys): return "snifferWrittenOff:" + keys
        case .snifferNotCompleted: return "snifferNotCompleted"
         
         
        case .notApplied: return "notApplied"
        }
    }

     
     
     
    init?(spelling: String) {
        let parts = spelling.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let name = parts.first.map(String.init) ?? spelling
        let argument = parts.count == 2 ? String(parts[1]) : nil
        switch (name, argument) {
        case ("engineUnavailable", nil): self = .engineUnavailable
        case ("certificateNotTrusted", nil): self = .certificateNotTrusted
        case ("certificateMissing", nil): self = .certificateMissing
        case ("certificateUnusable", nil): self = .certificateUnusable
        case ("stoppedForMemory", nil): self = .stoppedForMemory
        case ("portsTaken", nil): self = .portsTaken
        case ("noCertificateAddress", nil): self = .noCertificateAddress
        case ("groupsNotAdjustable", nil): self = .groupsNotAdjustable
        case ("sectionNotAdjustable", let key?): self = .sectionNotAdjustable(key)
        case ("alreadyPublished", nil): self = .alreadyPublished
        case ("moduleRulesLeftOut", nil): self = .moduleRulesLeftOut
        case ("moduleEntriesLeftOut", nil): self = .moduleEntriesLeftOut
        case ("moduleSettingsLeftOut", nil): self = .moduleSettingsLeftOut
        case ("engineNameTaken", nil): self = .engineNameTaken
        case ("snifferWrittenOff", let keys?): self = .snifferWrittenOff(keys)
        case ("snifferNotCompleted", nil): self = .snifferNotCompleted
        default: return nil
        }
    }
}
