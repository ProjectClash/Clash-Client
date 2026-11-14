 
 
 
 
 
 
 
 
 
 
 
 
 
import SwiftASN1

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
public protocol VerifierPolicy {
     
     
     
     
     
     
     
     
     
     
     
    var verifyingCriticalExtensions: [ASN1ObjectIdentifier] { get }

     
     
     
     
     
     
     
     
    mutating func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult
}

public enum PolicyEvaluationResult: Sendable {
    case meetsPolicy
    case failsToMeetPolicy(PolicyFailureReason)

    public static func failsToMeetPolicy(reason makeReason: @autoclosure @Sendable @escaping () -> String) -> Self {
        return .failsToMeetPolicy(.init(makeReason()))
    }

    public static func failsToMeetPolicy(reason: PolicyFailureReason) -> Self {
        return .failsToMeetPolicy(reason)
    }
}

public struct PolicyFailureReason: Sendable {
    var storage: @Sendable () -> String

    public init(_ makeString: @autoclosure @Sendable @escaping () -> String) {
        self.storage = makeString
    }
}

extension PolicyFailureReason: Equatable {
    public static func == (lhs: PolicyFailureReason, rhs: PolicyFailureReason) -> Bool {
        lhs.description == rhs.description
    }
}

extension PolicyFailureReason: Hashable {
    public func hash(into hasher: inout Hasher) {
        description.hash(into: &hasher)
    }
}

extension PolicyFailureReason: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        storage()
    }

    public var debugDescription: String {
        description.debugDescription
    }
}
