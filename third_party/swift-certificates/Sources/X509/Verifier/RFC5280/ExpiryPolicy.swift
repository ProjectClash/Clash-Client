 
 
 
 
 
 
 
 
 
 
 
 
 

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftASN1

 
@usableFromInline
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
struct ExpiryPolicy: VerifierPolicy {
    @usableFromInline
    let verifyingCriticalExtensions: [ASN1ObjectIdentifier] = []

    @usableFromInline
    let validationTime: GeneralizedTime

    @inlinable
    init(validationTime: Date) {
        self.validationTime = GeneralizedTime(validationTime)
    }

    @inlinable
    func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) -> PolicyEvaluationResult {
         
         
         
         
        for cert in chain {
            let notValidBefore = GeneralizedTime(cert.tbsCertificate.validity.notBefore)
            let notValidAfter = GeneralizedTime(cert.tbsCertificate.validity.notAfter)

            if notValidBefore > notValidAfter {
                return .failsToMeetPolicy(
                    reason:
                        "RFC5280Policy: Certificate \(cert) has invalid expiry, notValidAfter is earlier than notValidBefore"
                )
            }

            if self.validationTime < notValidBefore {
                return .failsToMeetPolicy(reason: "RFC5280Policy: Certificate \(cert) is not yet valid")
            }

            if self.validationTime > notValidAfter {
                return .failsToMeetPolicy(reason: "RFC5280Policy: Certificate \(cert) has expired")
            }
        }

        return .meetsPolicy
    }
}
