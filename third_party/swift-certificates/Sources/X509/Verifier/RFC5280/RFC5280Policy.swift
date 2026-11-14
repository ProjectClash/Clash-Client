 
 
 
 
 
 
 
 
 
 
 
 
 
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftASN1

 
 
 
 
 
 
 
 
 
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
public struct RFC5280Policy: VerifierPolicy {
    public let verifyingCriticalExtensions: [ASN1ObjectIdentifier] = [
        .X509ExtensionID.basicConstraints,
        .X509ExtensionID.nameConstraints,

         
         
         
         
         
         
         
        .X509ExtensionID.keyUsage,
    ]

    @usableFromInline
    let versionPolicy: VersionPolicy

    @usableFromInline
    let expiryPolicy: ExpiryPolicy?

    @usableFromInline
    let basicConstraintsPolicy: BasicConstraintsPolicy

    @usableFromInline
    let nameConstraintsPolicy: NameConstraintsPolicy

    @inlinable
    public init(validationTime: Date) {
        self.versionPolicy = VersionPolicy()
        self.expiryPolicy = ExpiryPolicy(validationTime: validationTime)
        self.basicConstraintsPolicy = BasicConstraintsPolicy()
        self.nameConstraintsPolicy = NameConstraintsPolicy()
    }

    private init() {
        self.versionPolicy = VersionPolicy()
        self.expiryPolicy = nil
        self.basicConstraintsPolicy = BasicConstraintsPolicy()
        self.nameConstraintsPolicy = NameConstraintsPolicy()
    }

    @_spi(DisableValidityCheck)
    public static func withValidityCheckDisabled() -> RFC5280Policy {
        return RFC5280Policy()
    }

    @inlinable
    public func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) -> PolicyEvaluationResult {
        if case .failsToMeetPolicy(let reason) = self.versionPolicy.chainMeetsPolicyRequirements(chain: chain) {
            return .failsToMeetPolicy(reason: reason)
        }
        if let expiryPolicy = self.expiryPolicy,
            case .failsToMeetPolicy(let reason) = expiryPolicy.chainMeetsPolicyRequirements(chain: chain)
        {
            return .failsToMeetPolicy(reason: reason)
        }

        if case .failsToMeetPolicy(let reason) = self.basicConstraintsPolicy.chainMeetsPolicyRequirements(chain: chain)
        {
            return .failsToMeetPolicy(reason: reason)
        }

        if case .failsToMeetPolicy(let reason) = self.nameConstraintsPolicy.chainMeetsPolicyRequirements(chain: chain) {
            return .failsToMeetPolicy(reason: reason)
        }

        return .meetsPolicy
    }
}
