 
 
 
 
 
 
 
 
 
 
 
 
 
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftASN1
import Crypto

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
public enum CMS {
    @_spi(CMS)
    @inlinable
    public static func sign<Bytes: DataProtocol>(
        _ bytes: Bytes,
        signatureAlgorithm: Certificate.SignatureAlgorithm,
        additionalIntermediateCertificates: [Certificate] = [],
        certificate: Certificate,
        privateKey: Certificate.PrivateKey,
        signingTime: Date? = nil,
        detached: Bool = true
    ) throws -> [UInt8] {
        if let signingTime = signingTime {
            return try self.signWithSigningTime(
                bytes,
                signatureAlgorithm: signatureAlgorithm,
                certificate: certificate,
                privateKey: privateKey,
                signingTime: signingTime,
                detached: detached
            )
        }

         
        let signature = try privateKey.sign(bytes: bytes, signatureAlgorithm: signatureAlgorithm)
        let signedData = try self.generateSignedData(
            signatureBytes: ASN1OctetString(signature),
            signatureAlgorithm: signatureAlgorithm,
            additionalIntermediateCertificates: additionalIntermediateCertificates,
            certificate: certificate,
            withContent: detached ? nil : bytes
        )

        return try self.serializeSignedData(signedData)
    }

    @_spi(CMS)
    @inlinable
    public static func sign<Bytes: DataProtocol>(
        _ bytes: Bytes,
        additionalIntermediateCertificates: [Certificate] = [],
        certificate: Certificate,
        privateKey: Certificate.PrivateKey,
        signingTime: Date? = nil,
        detached: Bool = true
    ) throws -> [UInt8] {
        return try self.sign(
            bytes,
            signatureAlgorithm: privateKey.defaultSignatureAlgorithm,
            additionalIntermediateCertificates: additionalIntermediateCertificates,
            certificate: certificate,
            privateKey: privateKey,
            signingTime: signingTime,
            detached: detached
        )
    }

    @inlinable
    static func signWithSigningTime<Bytes: DataProtocol>(
        _ bytes: Bytes,
        signatureAlgorithm: Certificate.SignatureAlgorithm,
        additionalIntermediateCertificates: [Certificate] = [],
        certificate: Certificate,
        privateKey: Certificate.PrivateKey,
        signingTime: Date,
        detached: Bool = true
    ) throws -> [UInt8] {
        var signedAttrs: [CMSAttribute] = []
         
         
         

         
        let contentTypeVal = try ASN1Any(erasing: ASN1ObjectIdentifier.cmsData)
        let contentTypeAttribute = CMSAttribute(attrType: .contentType, attrValues: [contentTypeVal])
        signedAttrs.append(contentTypeAttribute)

         
        let digestAlgorithm = try AlgorithmIdentifier(digestAlgorithmFor: signatureAlgorithm)
        let computedDigest = try Digest.computeDigest(for: bytes, using: digestAlgorithm)
        let messageDigest = ASN1OctetString(contentBytes: ArraySlice(computedDigest))
        let messageDigestVal = try ASN1Any(erasing: messageDigest)
        let messageDigestAttr = CMSAttribute(attrType: .messageDigest, attrValues: [messageDigestVal])
        signedAttrs.append(messageDigestAttr)

         
        let utcTime = try UTCTime(signingTime.utcDate)
        let signingTimeAttrVal = try ASN1Any(erasing: utcTime)
        let signingTimeAttribute = CMSAttribute(attrType: .signingTime, attrValues: [signingTimeAttrVal])
        signedAttrs.append(signingTimeAttribute)

         
         
        var coder = DER.Serializer()
        try coder.serializeSetOf(signedAttrs)
        let signedAttrBytes = coder.serializedBytes[...]
        let signature = try privateKey.sign(bytes: signedAttrBytes, signatureAlgorithm: signatureAlgorithm)
        let signedData = try self.generateSignedData(
            signatureBytes: ASN1OctetString(signature),
            signatureAlgorithm: signatureAlgorithm,
            additionalIntermediateCertificates: additionalIntermediateCertificates,
            certificate: certificate,
            signedAttrs: signedAttrs,
            withContent: detached ? nil : bytes
        )
        return try self.serializeSignedData(signedData)
    }

    @_spi(CMS)
    @inlinable
    public static func sign(
        signatureBytes: ASN1OctetString,
        signatureAlgorithm: Certificate.SignatureAlgorithm,
        additionalIntermediateCertificates: [Certificate] = [],
        certificate: Certificate
    ) throws -> [UInt8] {
        let signedData = try self.generateSignedData(
            signatureBytes: signatureBytes,
            signatureAlgorithm: signatureAlgorithm,
            additionalIntermediateCertificates: additionalIntermediateCertificates,
            certificate: certificate,
            withContent: nil as Data?
        )

        return try serializeSignedData(signedData)
    }

    @inlinable
    static func serializeSignedData(
        _ contentInfo: CMSContentInfo
    ) throws -> [UInt8] {
        var serializer = DER.Serializer()
        try serializer.serialize(contentInfo)
        return serializer.serializedBytes
    }

    @inlinable
    static func generateSignedData(
        signatureBytes: ASN1OctetString,
        signatureAlgorithm: Certificate.SignatureAlgorithm,
        additionalIntermediateCertificates: [Certificate],
        certificate: Certificate,
        signedAttrs: [CMSAttribute]? = nil
    ) throws -> CMSContentInfo {
        return try generateSignedData(
            signatureBytes: signatureBytes,
            signatureAlgorithm: signatureAlgorithm,
            additionalIntermediateCertificates: additionalIntermediateCertificates,
            certificate: certificate,
            signedAttrs: signedAttrs,
            withContent: nil as Data?
        )
    }

    @inlinable
    static func generateSignedData<Bytes: DataProtocol>(
        signatureBytes: ASN1OctetString,
        signatureAlgorithm: Certificate.SignatureAlgorithm,
        additionalIntermediateCertificates: [Certificate],
        certificate: Certificate,
        signedAttrs: [CMSAttribute]? = nil,
        withContent content: Bytes? = nil
    ) throws -> CMSContentInfo {
        let digestAlgorithm = try AlgorithmIdentifier(digestAlgorithmFor: signatureAlgorithm)
        var contentInfo = CMSEncapsulatedContentInfo(eContentType: .cmsData)
        if let content {
            contentInfo.eContent = ASN1OctetString(contentBytes: Array(content)[...])
        }

        let signerInfo = CMSSignerInfo(
            signerIdentifier: .init(issuerAndSerialNumber: certificate),
            digestAlgorithm: digestAlgorithm,
            signedAttrs: signedAttrs,
            signatureAlgorithm: AlgorithmIdentifier(signatureAlgorithm),
            signature: signatureBytes
        )

        var certificates = additionalIntermediateCertificates
        certificates.append(certificate)

        let signedData = CMSSignedData(
            version: .v1,
            digestAlgorithms: [digestAlgorithm],
            encapContentInfo: contentInfo,
            certificates: certificates,
            signerInfos: [signerInfo]
        )
        return try CMSContentInfo(signedData)
    }

    @_spi(CMS)
    @inlinable
    public static func isValidAttachedSignature<SignatureBytes: DataProtocol>(
        signatureBytes: SignatureBytes,
        additionalIntermediateCertificates: [Certificate] = [],
        trustRoots: CertificateStore,
        diagnosticCallback: ((VerificationDiagnostic) -> Void)? = nil,
        microsoftCompatible: Bool = false,
        @PolicyBuilder policy: () throws -> some VerifierPolicy
    ) async rethrows -> SignatureVerificationResult {
        do {
             
            let parsedSignature = try CMSContentInfo(berEncoded: ArraySlice(signatureBytes))
            guard let attachedData = try parsedSignature.signedData?.encapContentInfo.eContent else {
                return .failure(.init(invalidCMSBlockReason: "No attached content"))
            }

            return try await isValidSignature(
                dataBytes: attachedData.bytes,
                signatureBytes: signatureBytes,
                trustRoots: trustRoots,
                diagnosticCallback: diagnosticCallback,
                microsoftCompatible: microsoftCompatible,
                allowAttachedContent: true,
                policy: policy
            )
        } catch {
            return .failure(.invalidCMSBlock(.init(reason: String(describing: error))))
        }
    }

    @_spi(CMS)
    @inlinable
    public static func isValidSignature<
        DataBytes: DataProtocol,
        SignatureBytes: DataProtocol
    >(
        dataBytes: DataBytes,
        signatureBytes: SignatureBytes,
        additionalIntermediateCertificates: [Certificate] = [],
        trustRoots: CertificateStore,
        diagnosticCallback: ((VerificationDiagnostic) -> Void)? = nil,
        microsoftCompatible: Bool = false,
        allowAttachedContent: Bool = false,
        @PolicyBuilder policy: () throws -> some VerifierPolicy
    ) async rethrows -> SignatureVerificationResult {
        let signedData: CMSSignedData
        let signingCert: Certificate
        do {
            let parsedSignature = try CMSContentInfo(berEncoded: ArraySlice(signatureBytes))
            guard let _signedData = try parsedSignature.signedData else {
                return .failure(.init(invalidCMSBlockReason: "Unable to parse signed data"))
            }
            signedData = _signedData

            guard signedData.signerInfos.count == 1 else {
                return .failure(.init(invalidCMSBlockReason: "Too many signatures"))
            }

            switch signedData.version {
            case .v1:
                 
                 
                 
                guard signedData.encapContentInfo.eContentType == .cmsData,
                    signedData.signerInfos.allSatisfy({ $0.version == .v1 })
                else {
                    return .failure(.init(invalidCMSBlockReason: "Invalid v1 signed data: \(signedData)"))
                }

            case .v3:
                 
                guard
                    signedData.encapContentInfo.eContentType == .cmsData
                        || signedData.encapContentInfo.eContentType == .cmsSignedData
                else {
                    return .failure(.init(invalidCMSBlockReason: "Invalid v3 signed data: \(signedData)"))
                }
                break

            case .v4:
                guard
                    signedData.encapContentInfo.eContentType == .cmsData
                        || signedData.encapContentInfo.eContentType == .cmsSignedData
                else {
                    return .failure(.init(invalidCMSBlockReason: "Invalid v4 signed data: \(signedData)"))
                }
                break

            default:
                 
                return .failure(.init(invalidCMSBlockReason: "Invalid signed data: \(signedData)"))
            }

            if let attachedContent = signedData.encapContentInfo.eContent {
                guard allowAttachedContent else {
                    return .failure(.init(invalidCMSBlockReason: "Attached content data not allowed"))
                }
                 
                guard dataBytes.elementsEqual(attachedContent.bytes) else {
                    return .failure(.init(invalidCMSBlockReason: "Attached content data does not match provided data"))
                }
            }

             
            let signer = signedData.signerInfos[0]

             
             
             
             
             
             
             
             
             
            guard signedData.digestAlgorithms.contains(signer.digestAlgorithm) else {
                return .failure(.init(invalidCMSBlockReason: "Digest algorithm mismatch"))
            }

             
             
            var signatureAlgorithm = Certificate.SignatureAlgorithm(algorithmIdentifier: signer.signatureAlgorithm)

             
             
            if microsoftCompatible
                && signer.signatureAlgorithm.algorithm == ASN1ObjectIdentifier.AlgorithmIdentifier.idEcPublicKey
            {
                 
                let sigAlgID: AlgorithmIdentifier
                switch signer.digestAlgorithm {
                case .sha256:
                    sigAlgID = .ecdsaWithSHA256

                case .sha384:
                    sigAlgID = .ecdsaWithSHA384

                case .sha512:
                    sigAlgID = .ecdsaWithSHA512

                default:
                    return .failure(.init(invalidCMSBlockReason: "Invalid digest algorithm"))
                }
                signatureAlgorithm = Certificate.SignatureAlgorithm(algorithmIdentifier: sigAlgID)
            } else {
                let expectedDigestAlgorithm = try AlgorithmIdentifier(digestAlgorithmFor: signatureAlgorithm)
                guard expectedDigestAlgorithm == signer.digestAlgorithm else {
                    return .failure(.init(invalidCMSBlockReason: "Digest and signature algorithm mismatch"))
                }
            }

             
             
            guard let _signingCert = try signedData.certificates?.certificate(signerInfo: signer) else {
                return .failure(.init(invalidCMSBlockReason: "Unable to locate signing certificate"))
            }
            signingCert = _signingCert

             
             
             
             
            let signature = try Certificate.Signature(
                signatureAlgorithm: signatureAlgorithm,
                signatureBytes: signer.signature
            )
            if let signedAttrs = signer.signedAttrs {
                guard let messageDigest = try signedAttrs.messageDigest else {
                    return .failure(.init(invalidCMSBlockReason: "Missing message digest from signed attributes"))
                }

                let digestAlgorithm = try AlgorithmIdentifier(digestAlgorithmFor: signatureAlgorithm)
                let actualDigest = try Digest.computeDigest(for: dataBytes, using: digestAlgorithm)

                guard actualDigest.elementsEqual(messageDigest) else {
                    return .failure(.init(invalidCMSBlockReason: "Message digest mismatch"))
                }

                guard
                    signingCert.publicKey.isValidSignature(
                        signature,
                        for: try signer._signedAttrsBytes(),
                        signatureAlgorithm: signatureAlgorithm
                    )
                else {
                    return .failure(
                        .init(invalidCMSBlockReason: "Invalid signature from signing certificate: \(signingCert)")
                    )
                }
            } else {
                guard
                    signingCert.publicKey.isValidSignature(
                        signature,
                        for: dataBytes,
                        signatureAlgorithm: signatureAlgorithm
                    )
                else {
                    return .failure(
                        .init(invalidCMSBlockReason: "Invalid signature from signing certificate: \(signingCert)")
                    )
                }
            }

        } catch {
            return .failure(.invalidCMSBlock(.init(reason: String(describing: error))))
        }

         
         
        var untrustedIntermediates = CertificateStore(signedData.certificates!)
        untrustedIntermediates.append(contentsOf: additionalIntermediateCertificates)

        var verifier = try Verifier(rootCertificates: trustRoots, policy: policy)
        let result = await verifier.validate(
            leafCertificate: signingCert,
            intermediates: untrustedIntermediates,
            diagnosticCallback: diagnosticCallback
        )

        switch result {
        case .validCertificate:
            return .success(.init(signer: signingCert))
        case .couldNotValidate(let validationFailures):
            return .failure(.unableToValidateSigner(.init(validationFailures: validationFailures, signer: signingCert)))
        }
    }

    @_spi(CMS)
    public enum Error: Swift.Error {
        case incorrectCMSVersionUsed
        case unexpectedCMSType
    }

    @_spi(CMS)
    public typealias SignatureVerificationResult = Result<Valid, VerificationError>

    public struct Valid: Hashable {
        public var signer: Certificate

        @inlinable
        public init(signer: Certificate) {
            self.signer = signer
        }
    }

    @_spi(CMS) public enum VerificationError: Swift.Error, Hashable {
        case unableToValidateSigner(SignerValidationFailure)
        case invalidCMSBlock(InvalidCMSBlock)

        public struct SignerValidationFailure: Hashable, Swift.Error {
            public var validationFailures: [VerificationResult.PolicyFailure]

            public var signer: Certificate

            @inlinable
            public init(validationFailures: [VerificationResult.PolicyFailure], signer: Certificate) {
                self.validationFailures = validationFailures
                self.signer = signer
            }
        }

        public struct InvalidCMSBlock: Hashable, Swift.Error {
            public var reason: String

            @inlinable
            public init(reason: String) {
                self.reason = reason
            }
        }

        @inlinable
        internal init(invalidCMSBlockReason: String) {
            self = .invalidCMSBlock(.init(reason: invalidCMSBlockReason))
        }
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Array where Element == Certificate {
    @usableFromInline
    func certificate(signerInfo: CMSSignerInfo) throws -> Certificate? {
        switch signerInfo.signerIdentifier {
        case .issuerAndSerialNumber(let issuerAndSerialNumber):
            return self.first { cert in
                cert.issuer == issuerAndSerialNumber.issuer && cert.serialNumber == issuerAndSerialNumber.serialNumber
            }

        case .subjectKeyIdentifier(let subjectKeyIdentifier):
            return self.first { cert in
                (try? cert.extensions.subjectKeyIdentifier)?.keyIdentifier == subjectKeyIdentifier.keyIdentifier
            }
        }
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.Signature {
    @inlinable
    init(signatureAlgorithm: Certificate.SignatureAlgorithm, signatureBytes: ASN1OctetString) throws {
        self = try Certificate.Signature(
            signatureAlgorithm: signatureAlgorithm,
            signatureBytes: ASN1BitString(bytes: signatureBytes.bytes)
        )
    }
}
