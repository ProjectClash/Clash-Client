 
 
 
 
 
 
 
 
 
 
 
 
 
import SwiftASN1

 
 
 
 
 
 
 
 
 
 
 
 
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
public struct AnyPolicy: VerifierPolicy {
    @usableFromInline
    var policy: any VerifierPolicy

    @inlinable
     
     
    public init(_ policy: some VerifierPolicy) {
        self.policy = policy
    }

     
     
    @inlinable
    public init(@PolicyBuilder makePolicy: () throws -> some VerifierPolicy) rethrows {
        self.init(try makePolicy())
    }

    @inlinable
    public var verifyingCriticalExtensions: [SwiftASN1.ASN1ObjectIdentifier] {
        policy.verifyingCriticalExtensions
    }

    @inlinable
    public mutating func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult
    {
        await policy.chainMeetsPolicyRequirements(chain: chain)
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
struct LegacyPolicySet: VerifierPolicy {
    let verifyingCriticalExtensions: [ASN1ObjectIdentifier]

    var policies: [any VerifierPolicy]

    init(policies: [any VerifierPolicy]) {
        self.policies = policies

        var extensions: [ASN1ObjectIdentifier] = []
        extensions.reserveCapacity(policies.reduce(into: 0, { $0 += $1.verifyingCriticalExtensions.count }))

        for policy in policies {
            extensions.append(contentsOf: policy.verifyingCriticalExtensions)
        }

        self.verifyingCriticalExtensions = extensions
    }

    mutating func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult {
        var policyIndex = self.policies.startIndex

        while policyIndex < self.policies.endIndex {
            switch await self.policies[policyIndex].chainMeetsPolicyRequirements(chain: chain) {
            case .meetsPolicy:
                ()
            case .failsToMeetPolicy(reason: let reason):
                return .failsToMeetPolicy(reason: reason)
            }

            self.policies.formIndex(after: &policyIndex)
        }

        return .meetsPolicy
    }
}
