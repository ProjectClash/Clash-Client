 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1
import Crypto
import struct Foundation.Data

 
 
 
 
 
 
public struct SubjectKeyIdentifier {
    public var keyIdentifier: ArraySlice<UInt8>

     
     
     
    @inlinable
    public init(keyIdentifier: ArraySlice<UInt8>) {
        self.keyIdentifier = keyIdentifier
    }

     
     
     
     
     
     
    @inlinable
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
    public init(_ ext: Certificate.Extension) throws {
        guard ext.oid == .X509ExtensionID.subjectKeyIdentifier else {
            throw CertificateError.incorrectOIDForExtension(
                reason: "Expected \(ASN1ObjectIdentifier.X509ExtensionID.subjectKeyIdentifier), got \(ext.oid)"
            )
        }

        let asn1KeyIdentifier = try ASN1OctetString(derEncoded: ext.value)
        self.keyIdentifier = asn1KeyIdentifier.bytes
    }
}

extension SubjectKeyIdentifier: Hashable {}

extension SubjectKeyIdentifier: Sendable {}

extension SubjectKeyIdentifier: CustomStringConvertible {
    public var description: String {
        return self.keyIdentifier.lazy.map { String($0, radix: 16) }.joined(separator: ":")
    }
}

extension SubjectKeyIdentifier: CustomDebugStringConvertible {
    public var debugDescription: String {
        "SubjectKeyIdentifier(\(String(describing: self)))"
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.Extension {
     
     
     
     
     
    @inlinable
    public init(_ ski: SubjectKeyIdentifier, critical: Bool) throws {
        let asn1Representation = ASN1OctetString(contentBytes: ski.keyIdentifier)
        var serializer = DER.Serializer()
        try serializer.serialize(asn1Representation)
        self.init(
            oid: .X509ExtensionID.subjectKeyIdentifier,
            critical: critical,
            value: serializer.serializedBytes[...]
        )
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension SubjectKeyIdentifier: CertificateExtensionConvertible {
    public func makeCertificateExtension() throws -> Certificate.Extension {
        return try .init(self, critical: false)
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension SubjectKeyIdentifier {
     
     
    @inlinable
    public init(hash publicKey: Certificate.PublicKey) {
         
         
         
         
        let hash = Insecure.SHA1.hash(data: publicKey.subjectPublicKeyInfoBytes)
        self.init(keyIdentifier: .init(hash))
    }
}
