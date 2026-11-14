import Foundation
import NetworkExtension

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum MacVPNDisconnectErrorPresentation {
    struct Verdict: Equatable {
        let message: String
        let offersVPNProfileReset: Bool
         
         
        var refusal: CoreStartRefusal? = nil
    }

    static let extensionDidNotStartMessage =
        "Connection failed. The VPN extension did not start."
    static let extensionDisabledMessage =
        "The VPN extension is disabled. Enable it in System Settings and try again."
    static let configurationNotFoundMessage =
        "VPN profile not found. Click to reinstall it."
    static let genericStartFailureMessage =
        "The VPN could not start. Check the configuration and try again."

     
     
     
     
     
     
    static func verdict(for error: NSError?, status: NEVPNStatus, record: StartupOutcomeRecord? = nil,
                        issuedAt: Date? = nil) -> Verdict {
        if status == .invalid {
            return Verdict(message: configurationNotFoundMessage, offersVPNProfileReset: true)
        }
        guard let error else {
            return Verdict(message: genericStartFailureMessage, offersVPNProfileReset: false)
        }
        if let refusal = CoreStartRefusal.from(error: error, record: record, issuedAt: issuedAt) {
            return Verdict(message: refusal.message, offersVPNProfileReset: false, refusal: refusal)
        }
        if error.domain == ClashTunnelStart.startErrorDomain {
            return Verdict(message: genericStartFailureMessage, offersVPNProfileReset: false)
        }
        if error.domain == NEVPNConnectionErrorDomain {
            switch NEVPNConnectionError(rawValue: error.code) {
            case .pluginFailed:
                return Verdict(message: extensionDidNotStartMessage, offersVPNProfileReset: false)
            case .pluginDisabled:
                return Verdict(message: extensionDisabledMessage, offersVPNProfileReset: false)
            case .configurationNotFound:
                return Verdict(message: configurationNotFoundMessage, offersVPNProfileReset: true)
            default:
                break
            }
        } else if error.domain == NEVPNErrorDomain,
                  NEVPNError.Code(rawValue: error.code) == .configurationInvalid {
            return Verdict(message: configurationNotFoundMessage, offersVPNProfileReset: true)
        }
        let sentence = error.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Verdict(
            message: sentence.isEmpty ? genericStartFailureMessage : sentence,
            offersVPNProfileReset: false)
    }
}

 
 
 
final class MacVPNDisconnectErrorFetchGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<NSError?, Never>?

    init(_ continuation: CheckedContinuation<NSError?, Never>) {
        self.continuation = continuation
    }

    func resolve(_ error: NSError?) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: error)
    }
}
