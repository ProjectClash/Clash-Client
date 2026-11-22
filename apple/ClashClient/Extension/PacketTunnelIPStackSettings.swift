import CoreFoundation
import Foundation

 
 
struct PacketTunnelIPStackSettings: Equatable, Sendable {
    enum QueryMode: String, Sendable {
         
        case followConfiguration = "config"
        case ipv4Only = "ipv4-only"
        case dualStack = "dual-stack"
        case preferIPv4 = "prefer-ipv4"
        case preferIPv6 = "prefer-ipv6"
        case ipv6Only = "ipv6-only"
    }

    enum TunIPv6Mode: String, Sendable {
         
         
         
         
        case followConfiguration = "config"
        case disabled
        case automatic
        case enabled

         
        var followsPath: Bool { self == .automatic || self == .followConfiguration }

        func declaresIPv6(coreOffersIPv6: Bool, pathReady: Bool, supportsIPv6: Bool) -> Bool {
            guard coreOffersIPv6 else { return false }
            switch self {
            case .disabled: return false
            case .automatic, .followConfiguration: return pathReady && supportsIPv6
            case .enabled: return true
            }
        }
    }

    enum InvalidSnapshot: LocalizedError {
        case malformed

        var errorDescription: String? {
            "The saved VPN IP Stack settings are invalid. Save valid IP Stack settings in the app before connecting."
        }
    }

    let queryMode: QueryMode
    let tunIPv6Mode: TunIPv6Mode

     
     
    static let `default` = Self(queryMode: .followConfiguration, tunIPv6Mode: .followConfiguration)

    static func decode(providerConfiguration: [String: Any]?) throws -> Self {
#if os(tvOS)
         
        guard let configuration = providerConfiguration,
              let payload = configuration["ipStack"] else { return .default }
        guard let dictionary = payload as? [String: Any],
              let version = dictionary["schemaVersion"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
              let query = dictionary["queryMode"] as? String,
              let queryMode = QueryMode(rawValue: query),
              let tun = dictionary["tunIPv6Mode"] as? String,
              let tunIPv6Mode = TunIPv6Mode(rawValue: tun) else {
            throw InvalidSnapshot.malformed
        }
        return Self(queryMode: queryMode, tunIPv6Mode: tunIPv6Mode)
#else
         
         
         
         
         
         
         
        return .default
#endif
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
struct TunnelIPv6PathFlapBreaker: Equatable {
    static let window: TimeInterval = 10
    static let flipsToTrip = 4
    static let settle: TimeInterval = 30
     
    static let heldPathIPv6 = true

    enum Verdict: Equatable {
         
        case follow
         
        case trip(flips: Int)
         
        case hold
    }

    private(set) var isHolding = false
     
    private var recentFlips: [TimeInterval] = []
    private var lastFlip: TimeInterval?

     
     
    mutating func noteFlip(at now: TimeInterval) -> Verdict {
        lastFlip = now
        guard !isHolding else { return .hold }
        recentFlips.removeAll { now - $0 >= Self.window }
        recentFlips.append(now)
        guard recentFlips.count >= Self.flipsToTrip else { return .follow }
        let flips = recentFlips.count
        recentFlips.removeAll()
        isHolding = true
        return .trip(flips: flips)
    }

     
    mutating func reset() {
        self = Self()
    }

     
     
    mutating func resumeIfSettled(at now: TimeInterval) -> Bool {
        guard isHolding, let lastFlip, now - lastFlip >= Self.settle else { return false }
        isHolding = false
        recentFlips.removeAll()
        return true
    }

     
     
    func pathIPv6ToDeclare(pathHasIPv6: Bool) -> Bool {
        isHolding ? Self.heldPathIPv6 : pathHasIPv6
    }

     
     
    func secondsUntilSettled(at now: TimeInterval) -> TimeInterval? {
        guard isHolding, let lastFlip else { return nil }
        return max(0, Self.settle - (now - lastFlip))
    }
}
