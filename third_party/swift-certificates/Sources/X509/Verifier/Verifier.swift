 
 
 
 
 
 
 
 
 
 
 
 
 
import SwiftASN1

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
public struct Verifier<Policy: VerifierPolicy> {
    public var rootCertificates: CertificateStore

    public var policy: Policy

    @inlinable
    public init(rootCertificates: CertificateStore, @PolicyBuilder policy: () throws -> Policy) rethrows {
        self.rootCertificates = rootCertificates
        self.policy = try policy()
    }

    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
    public mutating func validate(
        leafCertificate: Certificate,
        intermediates: CertificateStore,
        diagnosticCallback: ((VerificationDiagnostic) -> Void)? = nil
    ) async -> VerificationResult {
        var partialChains: [CandidatePartialChain] = [CandidatePartialChain(leaf: leafCertificate)]

        var policyFailures: [VerificationResult.PolicyFailure] = []

         
         
        if leafCertificate.hasUnhandledCriticalExtensions(handledExtensions: self.policy.verifyingCriticalExtensions) {

            diagnosticCallback?(
                .leafCertificateHasUnhandledCriticalExtension(
                    leafCertificate,
                    handledCriticalExtensions: self.policy.verifyingCriticalExtensions
                )
            )
            return .couldNotValidate([])
        }

        let rootCertificates = await self.rootCertificates.resolve(diagnosticsCallback: diagnosticCallback)
         
         
         
         
         
         
        if rootCertificates.contains(leafCertificate) {
            let unverifiedChain = UnverifiedCertificateChain([leafCertificate])

            switch await self.policy.chainMeetsPolicyRequirements(chain: unverifiedChain) {
            case .meetsPolicy:
                 
                diagnosticCallback?(.foundValidCertificateChain(unverifiedChain.certificates))
                return .validCertificate(unverifiedChain.certificates)

            case .failsToMeetPolicy(reason: let reason):
                diagnosticCallback?(
                    .leafCertificateIsInTheRootStoreButDoesNotMeetPolicy(leafCertificate, reason: reason)
                )
                policyFailures.append(
                    VerificationResult.PolicyFailure(chain: unverifiedChain, policyFailureReason: reason)
                )
            }
        }

        let intermediates = await intermediates.resolve(diagnosticsCallback: diagnosticCallback)

         
        while let nextPartialCandidate = partialChains.popLast() {
            diagnosticCallback?(.searchingForIssuerOfPartialChain(nextPartialCandidate))
             
             
            if var rootParents = rootCertificates[nextPartialCandidate.currentTip.issuer] {
                 
                rootParents.sortBySuitabilityForIssuing(certificate: nextPartialCandidate.currentTip)
                diagnosticCallback?(
                    .foundCandidateIssuersOfPartialChainInRootStore(nextPartialCandidate, issuers: rootParents)
                )

                 
                for root in rootParents {
                    if self.shouldSkipAddingCertificate(
                        partialChain: nextPartialCandidate,
                        nextCertificate: root,
                        diagnosticCallback: diagnosticCallback
                    ) {
                        continue
                    }

                    let unverifiedChain = UnverifiedCertificateChain(chain: nextPartialCandidate, root: root)

                    switch await self.policy.chainMeetsPolicyRequirements(chain: unverifiedChain) {
                    case .meetsPolicy:
                         
                        diagnosticCallback?(.foundValidCertificateChain(unverifiedChain.certificates))
                        return .validCertificate(unverifiedChain.certificates)

                    case .failsToMeetPolicy(reason: let reason):
                        diagnosticCallback?(.chainFailsToMeetPolicy(unverifiedChain, reason: reason))
                        policyFailures.append(
                            VerificationResult.PolicyFailure(chain: unverifiedChain, policyFailureReason: reason)
                        )
                    }
                }
            }

            if var intermediateParents = intermediates[nextPartialCandidate.currentTip.issuer] {
                 
                intermediateParents.sortBySuitabilityForIssuing(certificate: nextPartialCandidate.currentTip)
                diagnosticCallback?(
                    .foundCandidateIssuersOfPartialChainInIntermediateStore(
                        nextPartialCandidate,
                        issuers: intermediateParents
                    )
                )

                 
                 
                 
                for parent in intermediateParents.reversed() {
                    if self.shouldSkipAddingCertificate(
                        partialChain: nextPartialCandidate,
                        nextCertificate: parent,
                        diagnosticCallback: diagnosticCallback
                    ) {
                        continue
                    }

                    let nextChain = nextPartialCandidate.appending(parent)
                    partialChains.append(nextChain)
                }
            }
        }

        diagnosticCallback?(.couldNotValidateLeafCertificate(leafCertificate))
        return .couldNotValidate(policyFailures)
    }

    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
    private func shouldSkipAddingCertificate(
        partialChain: CandidatePartialChain,
        nextCertificate: Certificate,
        diagnosticCallback: ((VerificationDiagnostic) -> Void)?
    ) -> Bool {
         
        if nextCertificate.hasUnhandledCriticalExtensions(handledExtensions: self.policy.verifyingCriticalExtensions) {
            diagnosticCallback?(
                .issuerHasUnhandledCriticalExtension(
                    issuer: nextCertificate,
                    chain: partialChain,
                    handledCriticalExtensions: self.policy.verifyingCriticalExtensions
                )
            )
            return true
        }

         
         
        if partialChain.contains(certificate: nextCertificate) {
            diagnosticCallback?(.issuerIsAlreadyInTheChain(partialChain, issuer: nextCertificate))
            return true
        }

         
        guard
            nextCertificate.publicKey.isValidSignature(partialChain.currentTip.signature, for: partialChain.currentTip)
        else {
            diagnosticCallback?(.issuerHasNotSignedCertificate(nextCertificate, chain: partialChain))
            return true
        }

        return false
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
public enum VerificationResult: Hashable, Sendable {
    case validCertificate([Certificate])
    case couldNotValidate([PolicyFailure])
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension VerificationResult {
    public struct PolicyFailure: Hashable, Sendable {
        public var chain: UnverifiedCertificateChain
        public var policyFailureReason: PolicyFailureReason

        @inlinable
        public init(chain: UnverifiedCertificateChain, policyFailureReason: PolicyFailureReason) {
            self.chain = chain
            self.policyFailureReason = policyFailureReason
        }
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
struct CandidatePartialChain: Hashable {
    var chain: [Certificate]

    var currentTip: Certificate

    init(leaf: Certificate) {
        self.chain = []
        self.currentTip = leaf
    }

     
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
    func contains(certificate: Certificate) -> Bool {
         
         
         
         
         
         
         
         
         
         
         
         
         
        func match(_ left: Certificate, _ right: Certificate) -> Bool {
            (left.subject == right.subject && left.publicKey == right.publicKey
                && left.extensions.subjectAlternativeNameBytes == right.extensions.subjectAlternativeNameBytes)
        }

        return (self.chain.contains(where: { match($0, certificate) }) || match(self.currentTip, certificate))
    }

    func appending(_ newElement: Certificate) -> CandidatePartialChain {
        var newChain = self
        newChain.chain.append(newChain.currentTip)
        newChain.currentTip = newElement
        return newChain
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Array where Element == Certificate {
    fileprivate mutating func sortBySuitabilityForIssuing(certificate: Certificate) {
         
         
        guard let aki = try? certificate.extensions.authorityKeyIdentifier else {
            return
        }

        self.sort(by: { $0.issuerPreference(subjectAKI: aki) > $1.issuerPreference(subjectAKI: aki) })
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate {
    func issuerPreference(subjectAKI: AuthorityKeyIdentifier) -> Int {
        guard let ski = try? self.extensions.subjectKeyIdentifier else {
             
            return 0
        }

         
        return subjectAKI.keyIdentifier == ski.keyIdentifier ? 1 : -1
    }

    func hasUnhandledCriticalExtensions(handledExtensions: [ASN1ObjectIdentifier]) -> Bool {
        for ext in self.extensions where ext.critical {
            guard handledExtensions.contains(ext.oid) else {
                return true
            }
        }

        return false
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension UnverifiedCertificateChain {
    fileprivate init(chain: CandidatePartialChain, root: Certificate) {
        var certificates = chain.chain
        certificates.append(chain.currentTip)
        certificates.append(root)
        self = .init(certificates)
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.Extensions {
    fileprivate var subjectAlternativeNameBytes: ArraySlice<UInt8>? {
        return self[oid: .X509ExtensionID.subjectAlternativeName].map { $0.value }
    }
}
