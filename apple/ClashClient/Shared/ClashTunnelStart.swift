import Foundation

 
 
 

enum ClashTunnelStart {
     
     
     
     
    static let userInitiatedStartOption = "clashUserInitiated"

     
     
    static let outcomeFileName = "clash-startup-outcome.json"

     
    static let stateFileName = "clash-start-state.json"

     
     
     
     
    static let startErrorDomain = "Clash.TunnelStart"

     
     
     
    enum StartErrorCode: Int {
        case serviceUnavailable = 0
         
        case coreRefused = 1
        case backedOff = 2
        case appGroupUnavailable = 3
        case configurationUnavailable = 4
        case physicalPathUnavailable = 5
    }
}

 
 
 
struct ClashStartupOutcomeRecord: Codable, Equatable {
    enum Outcome: String, Codable {
        case started
        case reloaded
        case recoveredFromLastKnownGood
        case refusedKeptRunning
        case refused
        case backedOff
         
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Outcome(rawValue: raw) ?? .unknown
        }
    }

    struct Revision: Codable, Equatable {
        let profileID: String
        let revision: String

         
         
        static let storeUnreadable = Revision(profileID: "", revision: "store-unreadable")
    }

    struct Quarantine: Codable, Equatable {
        let profileID: String
        let revision: String
        let message: String
        let at: Date
    }

    var schema = 1
    var at: Date?
    var operation: String?
    var outcome: Outcome
    var errorClass: String?
    var message: String?
    var requested: Revision?
    var running: Revision?
    var quarantined: Quarantine?
    var userInitiated: Bool?
    var backoffUntil: Date?

    init(at: Date, operation: String, outcome: Outcome, errorClass: String? = nil, message: String? = nil,
         requested: Revision? = nil, running: Revision? = nil, quarantined: Quarantine? = nil,
         userInitiated: Bool? = nil, backoffUntil: Date? = nil) {
        self.at = at
        self.operation = operation
        self.outcome = outcome
        self.errorClass = errorClass
        self.message = message
        self.requested = requested
        self.running = running
        self.quarantined = quarantined
        self.userInitiated = userInitiated
        self.backoffUntil = backoffUntil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = (try? container.decodeIfPresent(Int.self, forKey: .schema)) ?? 1
        at = try? container.decodeIfPresent(Date.self, forKey: .at)
        operation = try? container.decodeIfPresent(String.self, forKey: .operation)
        outcome = (try? container.decodeIfPresent(Outcome.self, forKey: .outcome)) ?? .unknown
        errorClass = try? container.decodeIfPresent(String.self, forKey: .errorClass)
        message = try? container.decodeIfPresent(String.self, forKey: .message)
        requested = try? container.decodeIfPresent(Revision.self, forKey: .requested)
        running = try? container.decodeIfPresent(Revision.self, forKey: .running)
        quarantined = try? container.decodeIfPresent(Quarantine.self, forKey: .quarantined)
        userInitiated = try? container.decodeIfPresent(Bool.self, forKey: .userInitiated)
        backoffUntil = try? container.decodeIfPresent(Date.self, forKey: .backoffUntil)
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

     
    func write(in container: URL) throws {
        let data = try Self.encoder().encode(self)
        try data.write(to: container.appendingPathComponent(ClashTunnelStart.outcomeFileName), options: .atomic)
    }

    static func read(in container: URL) -> ClashStartupOutcomeRecord? {
        guard let data = try? Data(contentsOf: container.appendingPathComponent(ClashTunnelStart.outcomeFileName)) else {
            return nil
        }
        return try? decoder().decode(Self.self, from: data)
    }
}
