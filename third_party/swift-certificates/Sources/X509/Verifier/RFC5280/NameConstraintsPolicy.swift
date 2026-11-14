 
 
 
 
 
 
 
 
 
 
 
 
 
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftASN1

 
@usableFromInline
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
struct NameConstraintsPolicy: VerifierPolicy {
    @usableFromInline
    let verifyingCriticalExtensions: [ASN1ObjectIdentifier] = [
        .X509ExtensionID.nameConstraints
    ]

    @inlinable
    init() {}

    @inlinable
    func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) -> PolicyEvaluationResult {
         
         
         
         
         
         
         
         
         
         
         
         
        if chain.count == 1 {
            return Self._validateNameConstraints(chain[...], issuer: chain.first!)
        }

        var issuedCerts = chain[...]
        while let issuer = issuedCerts.popLast(), issuedCerts.count > 0 {
            if case .failsToMeetPolicy(let reason) = Self._validateNameConstraints(issuedCerts, issuer: issuer) {
                return .failsToMeetPolicy(reason: reason)
            }
        }

        return .meetsPolicy
    }

    @inlinable
    static func _validateNameConstraints(
        _ issuedCerts: UnverifiedCertificateChain.SubSequence,
        issuer: Certificate
    ) -> PolicyEvaluationResult {
        let maybeConstraints: NameConstraints?

        do {
            maybeConstraints = try issuer.extensions.nameConstraints
        } catch {
             
            return .failsToMeetPolicy(reason: "RFC5280Policy: Unable to decode name constraints from \(issuer)")
        }

        guard let constraints = maybeConstraints else {
             
            return .meetsPolicy
        }

        for cert in issuedCerts {
            let names: Certificate.NameSequence

            do {
                names = try cert.names
            } catch {
                return .failsToMeetPolicy(reason: "RFC5280Policy: Unable to decode SAN field of \(cert): \(error)")
            }

            for name in names {
                if case .failsToMeetPolicy(let reason) = Self._validatePermittedSubtrees(
                    constraints.permittedSubtrees,
                    name
                ) {
                    return .failsToMeetPolicy(reason: reason)
                }

                if case .failsToMeetPolicy(let reason) = Self._validateExcludedSubtrees(
                    constraints.excludedSubtrees,
                    name
                ) {
                    return .failsToMeetPolicy(reason: reason)
                }
            }
        }

        return .meetsPolicy
    }

    @inlinable
    static func _validateExcludedSubtrees(
        _ excludedSubtrees: [GeneralName],
        _ name: GeneralName
    ) -> PolicyEvaluationResult {
         
        for excludedSubtree in excludedSubtrees {
            switch (excludedSubtree, name) {
            case (.directoryName(let constraint), .directoryName(let presentedName)):
                if directoryNameMatchesConstraint(directoryName: presentedName, constraint: constraint) {
                    return .failsToMeetPolicy(
                        reason:
                            "RFC5280Policy: directoryName \(presentedName) is excluded by \(excludedSubtree) in name constraints"
                    )
                }
            case (.dnsName(let constraint), .dnsName(let presentedName)):
                if dnsNameMatchesConstraint(dnsName: presentedName.utf8, constraint: constraint.utf8) {
                    return .failsToMeetPolicy(
                        reason:
                            "RFC5280Policy: dnsName \(presentedName) is excluded by \(excludedSubtree) in name constraints"
                    )
                }
            case (.ipAddress(let constraint), .ipAddress(let presentedName)):
                if ipAddressMatchesConstraint(ipAddress: presentedName, constraint: constraint) {
                    return .failsToMeetPolicy(
                        reason:
                            "RFC5280Policy: ipAddress \(presentedName) is excluded by \(excludedSubtree) in name constraints"
                    )
                }
            case (.uniformResourceIdentifier(let constraint), .uniformResourceIdentifier(let presentedName)):
                if uriNameMatchesConstraint(uriName: presentedName, constraint: constraint) {
                    return .failsToMeetPolicy(
                        reason:
                            "RFC5280Policy: URI \(presentedName) is excluded by \(excludedSubtree) in name constraints"
                    )
                }
            case (.directoryName, _), (.dnsName, _), (.ipAddress, _), (.uniformResourceIdentifier, _):
                 
                continue
            default:
                 
                 
                 
                 
                 
                return .failsToMeetPolicy(
                    reason:
                        "RFC5280Policy: Unable to validate excluded subtree for name \(excludedSubtree), unsupported constraint"
                )
            }
        }

         
        return .meetsPolicy
    }

    @inlinable
    static func _validatePermittedSubtrees(
        _ permittedSubtrees: [GeneralName],
        _ name: GeneralName
    ) -> PolicyEvaluationResult {
        var evaluatedAtLeastOneConstraint = false

        for permittedSubtree in permittedSubtrees {
            switch (permittedSubtree, name) {
            case (.directoryName(let constraint), .directoryName(let presentedName)):
                evaluatedAtLeastOneConstraint = true

                if directoryNameMatchesConstraint(directoryName: presentedName, constraint: constraint) {
                     
                    return .meetsPolicy
                }

            case (.dnsName(let constraint), .dnsName(let presentedName)):
                evaluatedAtLeastOneConstraint = true

                if dnsNameMatchesConstraint(dnsName: presentedName.utf8, constraint: constraint.utf8) {
                     
                    return .meetsPolicy
                }
            case (.ipAddress(let constraint), .ipAddress(let presentedName)):
                evaluatedAtLeastOneConstraint = true

                if ipAddressMatchesConstraint(ipAddress: presentedName, constraint: constraint) {
                     
                    return .meetsPolicy
                }
            case (.uniformResourceIdentifier(let constraint), .uniformResourceIdentifier(let presentedName)):
                evaluatedAtLeastOneConstraint = true

                if uriNameMatchesConstraint(uriName: presentedName, constraint: constraint) {
                     
                    return .meetsPolicy
                }
            case (.directoryName, _), (.dnsName, _), (.ipAddress, _), (.uniformResourceIdentifier, _):
                 
                 
                continue
            default:
                 
                 
                 
                 
                 
                return .failsToMeetPolicy(
                    reason:
                        "RFC5280Policy: Unable to validate permitted subtree for name \(permittedSubtree), unsupported constraint"
                )
            }
        }

         
        guard evaluatedAtLeastOneConstraint else {
            return .meetsPolicy
        }
        return .failsToMeetPolicy(
            reason: "RFC5280Policy: Unable to validate permitted subtree for \(permittedSubtrees), no matches!"
        )
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate {
    @inlinable
    var names: NameSequence {
        get throws {
            return try NameSequence(self)
        }
    }

    @usableFromInline
    struct NameSequence: Sequence {
        @usableFromInline
        var subject: DistinguishedName

        @usableFromInline
        var alternativeNames: SubjectAlternativeNames

        @inlinable
        init(_ certificate: Certificate) throws {
            self.subject = certificate.subject
            self.alternativeNames = try certificate.extensions.subjectAlternativeNames ?? .init()
        }

        @inlinable
        func makeIterator() -> Iterator {
            return Iterator(self.subject, self.alternativeNames)
        }

        @usableFromInline
        struct Iterator: IteratorProtocol {
            @usableFromInline
            var subject: DistinguishedName?

            @usableFromInline
            var alternativeNames: SubjectAlternativeNames.SubSequence

            @inlinable
            init(_ subject: DistinguishedName, _ alternativeNames: SubjectAlternativeNames) {
                self.subject = subject
                self.alternativeNames = alternativeNames[...]
            }

            @inlinable
            mutating func next() -> GeneralName? {
                guard let subject = self.subject else {
                    return self.alternativeNames.popFirst()
                }
                self.subject = nil
                return .directoryName(subject)
            }
        }
    }
}
