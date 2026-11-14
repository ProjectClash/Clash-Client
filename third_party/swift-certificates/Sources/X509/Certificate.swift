 
 
 
 
 
 
 
 
 
 
 
 
 

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftASN1

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
#if canImport(Security)
 
 
 
 
 
#endif
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
public struct Certificate {
     
     
     
     
    @inlinable
    public var version: Version {
        self.tbsCertificate.version
    }

     
     
     
    @inlinable
    public var serialNumber: SerialNumber {
        self.tbsCertificate.serialNumber
    }

     
     
     
     
    @inlinable
    public var publicKey: PublicKey {
        self.tbsCertificate.publicKey
    }

     
    @inlinable
    public var notValidBefore: Date {
        Date(self.tbsCertificate.validity.notBefore)
    }

     
    @inlinable
    public var notValidAfter: Date {
        Date(self.tbsCertificate.validity.notAfter)
    }

     
    @inlinable
    public var issuer: DistinguishedName {
        self.tbsCertificate.issuer
    }

     
    @inlinable
    public var subject: DistinguishedName {
        self.tbsCertificate.subject
    }

     
    @inlinable
    public var extensions: Extensions {
        self.tbsCertificate.extensions
    }

    @usableFromInline
    internal let tbsCertificate: TBSCertificate

     
     
     
    public let tbsCertificateBytes: ArraySlice<UInt8>

     
     
     
    public let signature: Signature

     
    public let signatureAlgorithm: SignatureAlgorithm

     
     
     
     
    @usableFromInline
    internal let signatureBytes: ArraySlice<UInt8>

     
     
     
     
    @usableFromInline
    internal let signatureAlgorithmBytes: ArraySlice<UInt8>

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @inlinable
    public init(
        version: Version,
        serialNumber: SerialNumber,
        publicKey: PublicKey,
        notValidBefore: Date,
        notValidAfter: Date,
        issuer: DistinguishedName,
        subject: DistinguishedName,
        signatureAlgorithm: SignatureAlgorithm,
        extensions: Extensions,
        issuerPrivateKey: PrivateKey
    ) throws {
        self.tbsCertificate = TBSCertificate(
            version: version,
            serialNumber: serialNumber,
            signature: signatureAlgorithm,
            issuer: issuer,
            validity: try Validity(
                notBefore: .makeTime(from: notValidBefore),
                notAfter: .makeTime(from: notValidAfter)
            ),
            subject: subject,
            publicKey: publicKey,
            extensions: extensions
        )
        self.signatureAlgorithm = signatureAlgorithm

        let tbsCertificateBytes = try DER.Serializer.serialized(element: self.tbsCertificate)[...]
        self.signature = try issuerPrivateKey.sign(bytes: tbsCertificateBytes, signatureAlgorithm: signatureAlgorithm)
        self.tbsCertificateBytes = tbsCertificateBytes
        self.signatureAlgorithmBytes = try DER.Serializer.serialized(
            element: AlgorithmIdentifier(self.signatureAlgorithm)
        )[...]
        self.signatureBytes = try DER.Serializer.serialized(element: ASN1BitString(self.signature))[...]
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @inlinable
    public init(
        version: Version,
        serialNumber: SerialNumber,
        publicKey: PublicKey,
        notValidBefore: Date,
        notValidAfter: Date,
        issuer: DistinguishedName,
        subject: DistinguishedName,
        extensions: Extensions,
        issuerPrivateKey: PrivateKey
    ) throws {
        try self.init(
            version: version,
            serialNumber: serialNumber,
            publicKey: publicKey,
            notValidBefore: notValidBefore,
            notValidAfter: notValidAfter,
            issuer: issuer,
            subject: subject,
            signatureAlgorithm: issuerPrivateKey.defaultSignatureAlgorithm,
            extensions: extensions,
            issuerPrivateKey: issuerPrivateKey
        )
    }

    @inlinable
    init(
        tbsCertificate: TBSCertificate,
        signatureAlgorithm: AlgorithmIdentifier,
        signature: ASN1BitString,
        tbsCertificateBytes: ArraySlice<UInt8>,
        signatureAlgorithmBytes: ArraySlice<UInt8>,
        signatureBytes: ArraySlice<UInt8>
    ) throws {
        self.tbsCertificate = tbsCertificate
        self.signatureAlgorithm = SignatureAlgorithm(algorithmIdentifier: signatureAlgorithm)
        self.signature = try Signature(signatureAlgorithm: self.signatureAlgorithm, signatureBytes: signature)
        self.tbsCertificateBytes = tbsCertificateBytes
        self.signatureAlgorithmBytes = signatureAlgorithmBytes
        self.signatureBytes = signatureBytes
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate: Hashable {}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate: Sendable {}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate: CustomStringConvertible {
    public var description: String {
        """
        Certificate(\
        version: \(String(reflecting: self.version)), \
        serialNumber: \(String(reflecting: self.serialNumber)), \
        issuer: \(String(reflecting: self.issuer)), \
        subject: \(String(reflecting: self.subject)), \
        notValidBefore: \(String(reflecting: self.notValidBefore)), \
        notValidAfter: \(String(reflecting: self.notValidAfter)), \
        publicKey: \(String(reflecting: self.publicKey)), \
        signature: \(String(reflecting: self.signature)), \
        extensions: \(String(reflecting: self.extensions))\
        )
        """
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate: DERImplicitlyTaggable {
    @inlinable
    public static var defaultIdentifier: ASN1Identifier {
        .sequence
    }

    @inlinable
    public init(derEncoded rootNode: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        self = try DER.sequence(rootNode, identifier: identifier) { nodes in
            guard let tbsCertificateNode = nodes.next(),
                let signatureAlgorithmNode = nodes.next(),
                let signatureNode = nodes.next()
            else {
                throw ASN1Error.invalidASN1Object(reason: "Invalid certificate object, insufficient ASN.1 nodes")
            }
            let tbsCertificate = try TBSCertificate(derEncoded: tbsCertificateNode)
            let signatureAlgorithm = try AlgorithmIdentifier(derEncoded: signatureAlgorithmNode)
            let signature = try ASN1BitString(derEncoded: signatureNode)
            return try Certificate(
                tbsCertificate: tbsCertificate,
                signatureAlgorithm: signatureAlgorithm,
                signature: signature,
                tbsCertificateBytes: tbsCertificateNode.encodedBytes,
                signatureAlgorithmBytes: signatureAlgorithmNode.encodedBytes,
                signatureBytes: signatureNode.encodedBytes
            )
        }
    }

    @inlinable
    public func serialize(into coder: inout DER.Serializer, withIdentifier identifier: ASN1Identifier) throws {
        coder.appendConstructedNode(identifier: identifier) { coder in
            coder.serializeRawBytes(self.tbsCertificateBytes)
            coder.serializeRawBytes(self.signatureAlgorithmBytes)
            coder.serializeRawBytes(self.signatureBytes)
        }
    }
}

extension DER.Serializer {
    @inlinable
    static func serialized<Element: DERSerializable>(element: Element) throws -> [UInt8] {
        var serializer = DER.Serializer()
        try serializer.serialize(element)
        return serializer.serializedBytes
    }

}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate: PEMRepresentable {
    @inlinable
    public static var defaultPEMDiscriminator: String { "CERTIFICATE" }
}

#if canImport(Security)
import Security

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate {
     
     
     
    public init(_ certificate: SecCertificate) throws {
        try self.init(derEncoded: Array(SecCertificateCopyData(certificate) as Data))
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension SecCertificate {
     
     
     
     
    public static func makeWithCertificate(_ certificate: Certificate) throws -> SecCertificate {
        var coder = DER.Serializer()
        try certificate.serialize(into: &coder)

        let derData = Data(coder.serializedBytes)

        return SecCertificateCreateWithData(nil, derData as CFData)!
    }
}
#endif
