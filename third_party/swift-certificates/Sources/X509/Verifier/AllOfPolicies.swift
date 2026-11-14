 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
public struct AllOfPolicies<Policy: VerifierPolicy>: VerifierPolicy {
    @usableFromInline
    var policy: Policy

    @inlinable
    public init(@PolicyBuilder policy: () throws -> Policy) throws {
        self.policy = try policy()
    }

    @inlinable
    public init(@PolicyBuilder policy: () -> Policy) {
        self.policy = policy()
    }

    @inlinable
    public var verifyingCriticalExtensions: [ASN1ObjectIdentifier] {
        self.policy.verifyingCriticalExtensions
    }

    @inlinable
    public mutating func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult
    {
        await self.policy.chainMeetsPolicyRequirements(chain: chain)
    }
}
