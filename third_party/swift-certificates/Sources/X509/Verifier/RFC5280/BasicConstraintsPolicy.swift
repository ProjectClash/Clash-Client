 
 
 
 
 
 
 
 
 
 
 
 
 
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftASN1

 
@usableFromInline
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
struct BasicConstraintsPolicy: VerifierPolicy {
    @usableFromInline
    let verifyingCriticalExtensions: [ASN1ObjectIdentifier] = [
        .X509ExtensionID.basicConstraints
    ]

    @inlinable
    init() {}

    @inlinable
    func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) -> PolicyEvaluationResult {
         
         
         
         
         
         
         
         
         
         
         
         
        var chain = chain[...]
        guard let leaf = chain.popFirst() else {
             
            return .failsToMeetPolicy(reason: "RFC5280Policy: Empty certificate chain")
        }

         
         
        if chain.count == 0 && leaf.version != .v1 {
            do {
                switch try leaf.extensions.basicConstraints {
                case .some(.isCertificateAuthority):
                    return .meetsPolicy
                case .some(.notCertificateAuthority), .none:
                    return .failsToMeetPolicy(reason: "RFC5280Policy: Self-signed cert \(leaf) is not marked as a CA")
                }
            } catch {
                return .failsToMeetPolicy(
                    reason: "RFC5280Policy: Error processing basic constraints for \(leaf): \(error)"
                )
            }
        }

         
        var subCACount = 0

        for cert in chain {
            do {
                switch try (cert.extensions.basicConstraints, cert.version) {
                case (_, .v1):
                     
                     
                     
                    ()
                case (.some(.isCertificateAuthority(.some(let maxPathLength))), _) where maxPathLength < subCACount:
                     
                    let subCACount = subCACount
                    return .failsToMeetPolicy(
                        reason:
                            "RFC5280Policy: CA \(cert) has maximum path length \(maxPathLength), but chain has \(subCACount) subCAs"
                    )

                case (.some(.isCertificateAuthority), _):
                     
                     
                    ()

                case (.some(.notCertificateAuthority), _), (.none, _):
                    return .failsToMeetPolicy(reason: "RFC5280Policy: Certificate \(cert) is not marked as a CA")
                }
            } catch {
                return .failsToMeetPolicy(
                    reason: "RFC5280Policy: Error processing basic constraints for \(cert): \(error)"
                )
            }

            if cert.issuer != cert.subject {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 

                subCACount += 1
            }
        }

        return .meetsPolicy
    }
}
