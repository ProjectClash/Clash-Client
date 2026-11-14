 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1
import Crypto
#if canImport(FoundationEssentials)
import FoundationEssentials
#elseif canImport(Darwin) || swift(>=5.9.1)
import Foundation
#else
@preconcurrency import Foundation
#endif

 
import _Concurrency

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
public protocol OCSPRequester: Sendable {
     
     
     
     
     
     
     
     
    func query(request: [UInt8], uri: String) async -> OCSPRequesterQueryResult
}

public struct OCSPRequesterQueryResult: Sendable {
    @usableFromInline
    enum Storage: Sendable {
        case success([UInt8])
        case nonTerminal(Error)
        case terminal(Error)
    }
    @usableFromInline
    var storage: Storage

    @inlinable
    init(_ storage: Storage) {
        self.storage = storage
    }
}

extension OCSPRequesterQueryResult {
     
     
    @inlinable
    public static func response(_ bytes: [UInt8]) -> Self {
        .init(.success(bytes))
    }

     
     
     
     
    @inlinable
    public static func nonTerminalError(_ reason: Error) -> Self {
        .init(.nonTerminal(reason))
    }

     
     
     
    @inlinable
    public static func terminalError(_ reason: Error) -> Self {
        .init(.terminal(reason))
    }
}

extension ASN1ObjectIdentifier {
    static let sha256NoSign: Self = [2, 16, 840, 1, 101, 3, 4, 2, 1]
    static let sha1NoSign: Self = [1, 3, 14, 3, 2, 26]
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
struct OCSPResponderSigningPolicy: VerifierPolicy {
    let verifyingCriticalExtensions: [ASN1ObjectIdentifier] = []

     
    var issuer: Certificate
    mutating func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult {
         
        guard chain.last == issuer else {
            return .failsToMeetPolicy(
                reason:
                    "OCSP response must be signed by the certificate issuer or a certificate that chains up to the issuer"
            )
        }
        if chain.count == 1 {
             
            return .meetsPolicy
        }

        let leaf = chain.leaf

         
         
         
         
        guard let extendedKeyUsage: ExtendedKeyUsage = try? leaf.extensions.extendedKeyUsage else {
            return .failsToMeetPolicy(reason: "OCSP response certificate has no extended key usages")
        }

        guard extendedKeyUsage.usages.contains(.ocspSigning) else {
            return .failsToMeetPolicy(
                reason: "OCSP response certificate does not have OCSP signing extended key usage set"
            )
        }

        return .meetsPolicy
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
enum OCSPRequestHashAlgorithm {
    case insecureSha1
     
    case sha256

    var oid: ASN1ObjectIdentifier {
        switch self {
        case .insecureSha1: return .sha1NoSign
        case .sha256: return .sha256NoSign
        }
    }
    private func hashed(_ value: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        switch self {
        case .insecureSha1:
            var hashAlgorithm = Insecure.SHA1()
            hashAlgorithm.update(data: value)
            return Array(hashAlgorithm.finalize())[...]
        case .sha256:
            var hashAlgorithm = SHA256()
            hashAlgorithm.update(data: value)
            return Array(hashAlgorithm.finalize())[...]
        }
    }

    fileprivate func issuerNameHashed(_ certificate: Certificate) throws -> ArraySlice<UInt8> {
         
         
         
        var serializer = DER.Serializer()
        try serializer.serialize(certificate.subject)
        return self.hashed(serializer.serializedBytes[...])
    }

    fileprivate func issuerPublicKeyHashed(_ certificate: Certificate) -> ArraySlice<UInt8> {
         
         
         
        self.hashed(certificate.publicKey.subjectPublicKeyInfoBytes)
    }
}

 
 
public struct OCSPFailureMode: Hashable, Sendable {
     
     
    public static var soft: Self { .init(storage: .soft) }
     
     
     
    public static var hard: Self { .init(storage: .hard) }

    enum Storage: Hashable, Sendable {
        case soft
        case hard
    }

    var storage: Storage
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
public struct OCSPVerifierPolicy<Requester: OCSPRequester>: VerifierPolicy {
    public let verifyingCriticalExtensions: [ASN1ObjectIdentifier] = []

    struct Storage: Sendable {
        private var failureMode: OCSPFailureMode
        private var requester: Requester
        private var requestHashAlgorithm: OCSPRequestHashAlgorithm

         
         
         
        private var maxDuration: TimeInterval

         
        private var validationTime: Date

         
         
         
        fileprivate var nonceExtensionEnabled: Bool = true

        fileprivate init(
            failureMode: OCSPFailureMode,
            requester: Requester,
            requestHashAlgorithm: OCSPRequestHashAlgorithm,
            maxDuration: TimeInterval,
            validationTime: Date
        ) {
            self.requester = requester
            self.requestHashAlgorithm = requestHashAlgorithm
            self.maxDuration = maxDuration
            self.validationTime = validationTime
            self.failureMode = failureMode
        }
    }

    var nonceExtensionEnabled: Bool {
        get {
            self.storage.nonceExtensionEnabled
        }
        set {
            self.storage.nonceExtensionEnabled = newValue
        }
    }

    private var storage: Storage

    public init(failureMode: OCSPFailureMode, requester: Requester, validationTime: Date) {
        self.storage = .init(
            failureMode: failureMode,
            requester: requester,
            requestHashAlgorithm: .insecureSha1,
            maxDuration: 10,
            validationTime: validationTime
        )
    }

     
     
    public mutating func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult
    {
        await self.storage.chainMeetsPolicyWithDeadline(chain: chain)
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension OCSPVerifierPolicy.Storage {

     
     
    private func softFailure(reason: PolicyFailureReason) -> PolicyEvaluationResult {
        switch self.failureMode.storage {
        case .soft:
            return .meetsPolicy
        case .hard:
            return .failsToMeetPolicy(reason: reason)
        }
    }

    fileprivate func chainMeetsPolicyWithDeadline(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult {
        await withTimeout(maxDuration) {
            await self.chainMeetsPolicyRequirementsWithoutDeadline(chain: chain)
        }
    }

    private func chainMeetsPolicyRequirementsWithoutDeadline(
        chain: UnverifiedCertificateChain
    ) async -> PolicyEvaluationResult {
        for index in chain.dropLast().indices {
            let certificate = chain[index]
            let issuer = chain[chain.index(after: index)]
            switch await self.certificateMeetsPolicyRequirements(certificate, issuer: issuer) {
            case .meetsPolicy:
                continue
            case .failsToMeetPolicy(let reason):
                return .failsToMeetPolicy(reason: reason)
            }
        }

        do {
            let hasRootCertificateOCSPURI =
                try chain.last?.extensions.authorityInformationAccess?.contains { $0.method == .ocspServer } ?? false
            if hasRootCertificateOCSPURI {
                return .failsToMeetPolicy(reason: "root certificate is not allowed to have an OCSP URI")
            }
        } catch {
            return .failsToMeetPolicy(reason: "failed to parse AuthorityInformationAccess extension")
        }
        return .meetsPolicy
    }

    private func certificateMeetsPolicyRequirements(
        _ certificate: Certificate,
        issuer: Certificate
    ) async -> PolicyEvaluationResult {

        let authorityInformationAccess: AuthorityInformationAccess?
        do {
            authorityInformationAccess = try certificate.extensions.authorityInformationAccess
        } catch {
            return self.softFailure(reason: .init("failed to decode AuthorityInformationAccess \(error)"))
        }
        guard let authorityInformationAccess else {
             
            return .meetsPolicy
        }

        let ocspAccessDescriptions = authorityInformationAccess.lazy.filter { $0.method == .ocspServer }
        if ocspAccessDescriptions.isEmpty {
             
            return .meetsPolicy
        }

         
        let responderURI = ocspAccessDescriptions.lazy.compactMap { description -> String? in
            guard case .uniformResourceIdentifier(let responderURI) = description.location else {
                return nil
            }
            return responderURI
        }.first
        guard let responderURI else {
            let ocspAccessDescriptions = Array(ocspAccessDescriptions)
            return self.softFailure(
                reason: .init("expected OCSP location to be a URI but got \(ocspAccessDescriptions)")
            )
        }

        let certID: OCSPCertID
        do {
            certID = try OCSPCertID(hashAlgorithm: requestHashAlgorithm, certificate: certificate, issuer: issuer)
        } catch {
            return self.softFailure(reason: .init("failed to create OCSPCertID \(error)"))
        }

        return await self.queryAndVerifyCertificateStatus(for: certID, responderURI: responderURI, issuer: issuer)
    }

    private func queryAndVerifyCertificateStatus(
        for certID: OCSPCertID,
        responderURI: String,
        issuer: Certificate
    ) async -> PolicyEvaluationResult {
        let requestNonce = nonceExtensionEnabled ? OCSPNonce() : nil
        let requestBytes: [UInt8]
        do {
            let request = try OCSPRequest(certID: certID, nonce: requestNonce)
            var serializer = DER.Serializer()
            try serializer.serialize(request)
            requestBytes = serializer.serializedBytes
        } catch {
            return self.softFailure(reason: .init("failed to create OCSPRequest \(error)"))
        }

        let responseDerEncoded: [UInt8]
        switch await self.requester.query(request: requestBytes, uri: responderURI).storage {
        case .success(let responseBytes):
            responseDerEncoded = responseBytes
        case .nonTerminal:
             
            return .meetsPolicy
        case .terminal(let error):
            return .failsToMeetPolicy(reason: String(describing: error))
        }

        let response: OCSPResponse
        do {
            response = try OCSPResponse(derEncoded: responseDerEncoded[...])
        } catch {
            return self.softFailure(reason: .init("OCSP deserialisation failed \(error)"))
        }

        return await self.verifyResponse(response, requestedCertID: certID, requestNonce: requestNonce, issuer: issuer)
    }

    private func verifyResponse(
        _ response: OCSPResponse,
        requestedCertID: OCSPCertID,
        requestNonce: OCSPNonce?,
        issuer: Certificate
    ) async -> PolicyEvaluationResult {
        switch response {
        case .unauthorized, .tryLater, .sigRequired, .malformedRequest, .internalError:
            return self.softFailure(reason: .init("OCSP request failed \(OCSPResponseStatus(response))"))
        case .successful(let basicResponse):
            return await self.verifySuccessfulResponse(
                basicResponse,
                requestedCertID: requestedCertID,
                requestNonce: requestNonce,
                issuer: issuer
            )
        }
    }

    private func verifySuccessfulResponse(
        _ basicResponse: BasicOCSPResponse,
        requestedCertID: OCSPCertID,
        requestNonce: OCSPNonce?,
        issuer: Certificate
    ) async -> PolicyEvaluationResult {
        guard let response = basicResponse.responseData.responses.first(where: { $0.certID == requestedCertID }) else {
            return self.softFailure(
                reason: .init(
                    "OCSP response does not include a response for the queried certificate \(requestedCertID) - responses: \(basicResponse.responseData.responses)"
                )
            )
        }

        switch await self.validateResponseSignature(basicResponse, issuer: issuer) {
        case .meetsPolicy:
            break
        case .failsToMeetPolicy(let reason):
            return self.softFailure(reason: reason)
        }

        guard basicResponse.responseData.version == .v1 else {
            return self.softFailure(
                reason: .init("OCSP response version unsupported \(basicResponse.responseData.version)")
            )
        }

        switch basicResponse.responseData.verifyTime(validationTime: self.validationTime) {
        case .failsToMeetPolicy(reason: let reason):
            return self.softFailure(reason: reason)
        case .meetsPolicy:
            break
        }

        do {
             
            if let requestNonce {
                 
                if let responseNonce = try basicResponse.responseData.responseExtensions?.ocspNonce,
                    requestNonce != responseNonce
                {
                    return self.softFailure(reason: .init("OCSP response nonce does not match request nonce"))
                }
            } else {
                precondition(nonceExtensionEnabled == false)
            }
        } catch {
            return self.softFailure(reason: .init("failed to decode nonce response \(error)"))
        }

        switch response.verifyTime(validationTime: self.validationTime) {
        case .meetsPolicy:
            break
        case .failsToMeetPolicy(let reason):
            return self.softFailure(reason: reason)
        }

        switch response.certStatus {
        case .revoked(let info):
            return .failsToMeetPolicy(
                reason: "revoked through OCSP, reason: \(info.revocationReason?.description ?? "nil")"
            )
        case .unknown:
            return self.softFailure(reason: .init("OCSP response returned as status unknown"))
        case .good:
            return .meetsPolicy
        }
    }

    private func validateResponseSignature(
        _ basicResponse: BasicOCSPResponse,
        issuer: Certificate
    ) async -> PolicyEvaluationResult {
        let responderID = basicResponse.responseData.responderID

        let leafCertificate: Certificate?
        if issuer.matches(responderID) {
            leafCertificate = issuer
        } else {
            leafCertificate = basicResponse.certs?.first(where: { $0.matches(responderID) })
        }

        guard let leafCertificate else {
            return .failsToMeetPolicy(reason: "could not find OCSP responder certificate for id \(responderID)")
        }

        let signatureValidationResult = self.validateSignature(
            certificate: leafCertificate,
            tbsResponse: basicResponse.responseDataBytes,
            signatureBytes: basicResponse.signature.bytes,
            signatureAlgorithmIdentifier: basicResponse.signatureAlgorithm
        )

        switch signatureValidationResult {
        case .meetsPolicy:
            break
        case .failsToMeetPolicy(let reason):
            return .failsToMeetPolicy(reason: reason)
        }

        var verifier = Verifier(
            rootCertificates: CertificateStore([issuer])
        ) {
            OCSPResponderSigningPolicy(issuer: issuer)
            RFC5280Policy(validationTime: validationTime)
        }

        let validationResult = await verifier.validate(
            leafCertificate: leafCertificate,
            intermediates: CertificateStore()
        )

        switch validationResult {
        case .couldNotValidate(let failures):
            return .failsToMeetPolicy(reason: "could not validate OCSP responder certificates \(failures)")
        case .validCertificate:
            return .meetsPolicy
        }
    }

    private func validateSignature(
        certificate: Certificate,
        tbsResponse: ArraySlice<UInt8>,
        signatureBytes: ArraySlice<UInt8>,
        signatureAlgorithmIdentifier: AlgorithmIdentifier
    ) -> PolicyEvaluationResult {
        let signatureAlgorithm = Certificate.SignatureAlgorithm(algorithmIdentifier: signatureAlgorithmIdentifier)
        let signature: Certificate.Signature
        do {
            signature = try Certificate.Signature(
                signatureAlgorithm: signatureAlgorithm,
                signatureBytes: .init(bytes: signatureBytes)
            )
        } catch {
            return .failsToMeetPolicy(reason: "could not create signature for OCSP response \(error)")
        }

        guard
            certificate.publicKey.isValidSignature(signature, for: tbsResponse, signatureAlgorithm: signatureAlgorithm)
        else {
            return .failsToMeetPolicy(reason: "OCSP response signature is not valid")
        }
        return .meetsPolicy
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension OCSPCertID {
    init(hashAlgorithm: OCSPRequestHashAlgorithm, certificate: Certificate, issuer: Certificate) throws {
        self.init(
            hashAlgorithm: .init(algorithm: hashAlgorithm.oid, parameters: nil),
            issuerNameHash: .init(contentBytes: try hashAlgorithm.issuerNameHashed(issuer)),
            issuerKeyHash: .init(contentBytes: hashAlgorithm.issuerPublicKeyHashed(issuer)),
            serialNumber: certificate.serialNumber
        )
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension OCSPRequest {
    init(certID: OCSPCertID, nonce: OCSPNonce?) throws {
        self.init(
            tbsRequest: OCSPTBSRequest(
                version: .v1,
                requestList: [
                    OCSPSingleRequest(certID: certID)
                ],
                requestExtensions: try .init(builder: {
                    if let nonce {
                        nonce
                    }
                })
            )
        )
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
 
 
extension OCSPResponseData {
     
    static let defaultTrustTimeLeeway: TimeInterval = 4500.0

    func verifyTime(
        validationTime: Date,
        trustTimeLeeway: TimeInterval = Self.defaultTrustTimeLeeway
    ) -> PolicyEvaluationResult {
        let producedAt = Date(self.producedAt)

        guard producedAt.timeIntervalSince(validationTime.advanced(by: trustTimeLeeway)) <= 0 else {
            return .failsToMeetPolicy(
                reason:
                    "OCSP response `producedAt` (\(self.producedAt) is in the future (+\(trustTimeLeeway) seconds leeway) but should be in the past"
            )
        }

        return .meetsPolicy
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension OCSPSingleResponse {

    func verifyTime(
        validationTime: Date,
        trustTimeLeeway: TimeInterval = OCSPResponseData.defaultTrustTimeLeeway
    ) -> PolicyEvaluationResult {
         
         
         
         
         
        guard let nextUpdateGeneralizedTime = self.nextUpdate else {
            return .failsToMeetPolicy(reason: "OCSP response `nextUpdate` is nil")
        }

        let thisUpdate = Date(self.thisUpdate)
        let nextUpdate = Date(nextUpdateGeneralizedTime)

        guard thisUpdate.timeIntervalSince(validationTime.advanced(by: trustTimeLeeway)) <= 0 else {
            return .failsToMeetPolicy(
                reason:
                    "OCSP response `thisUpdate` (\(self.thisUpdate) is in the future (+\(trustTimeLeeway) seconds leeway) but should be in the past"
            )
        }

        guard nextUpdate.timeIntervalSince(validationTime.advanced(by: -trustTimeLeeway)) >= 0 else {
            return .failsToMeetPolicy(
                reason:
                    "OCSP response `nextUpdate` (\(nextUpdateGeneralizedTime) is in the past (-\(trustTimeLeeway) seconds leeway) but should be in the future"
            )
        }

        return .meetsPolicy
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate {
    fileprivate func matches(_ responderID: ResponderID) -> Bool {
        switch responderID {
        case .byName(let subject):
            return self.subject == subject
        case .byKey(let responderPublicKeyHash):
            let publicKeyHash = Insecure.SHA1.hash(data: self.publicKey.subjectPublicKeyInfoBytes)
            return publicKeyHash == responderPublicKeyHash.bytes
        }
    }
}

 
 
 
 
 
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
private func withTimeout<Result: Sendable>(
    _ maxDuration: TimeInterval,
    operation: @escaping @Sendable () async -> Result
) async -> Result {
    await withTaskGroup(of: Optional<Result>.self) { group in
         
        group.addTask(operation: operation)
         
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(maxDuration * 1000 * 1000 * 1000))
            return nil
        }
         
        let firstResult = await group.next()!
         
         
        group.cancelAll()
        let secondResult = await group.next()!
         
         
         
        return (firstResult ?? secondResult)!
    }
}
