 
 
 
 
 
 
 
 
 
 
 
 
 

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftASN1

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@usableFromInline
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
struct CMSSignerInfo: DERImplicitlyTaggable, BERImplicitlyTaggable, Hashable, Sendable {
    @usableFromInline
    enum Error: Swift.Error {
        case versionAndSignerIdentifierMismatch(String)
    }

    @inlinable
    static var defaultIdentifier: ASN1Identifier {
        .sequence
    }

    @usableFromInline var version: CMSVersion
    @usableFromInline var signerIdentifier: CMSSignerIdentifier
    @usableFromInline var digestAlgorithm: AlgorithmIdentifier
    @usableFromInline var signedAttrs: [CMSAttribute]?
    @usableFromInline var signatureAlgorithm: AlgorithmIdentifier
    @usableFromInline var signature: ASN1OctetString
    @usableFromInline var unsignedAttrs: [CMSAttribute]?

    @inlinable
    init(
        signerIdentifier: CMSSignerIdentifier,
        digestAlgorithm: AlgorithmIdentifier,
        signedAttrs: [CMSAttribute]? = nil,
        signatureAlgorithm: AlgorithmIdentifier,
        signature: ASN1OctetString,
        unsignedAttrs: [CMSAttribute]? = nil
    ) {
        switch signerIdentifier {
        case .issuerAndSerialNumber:
            self.version = .v1
        case .subjectKeyIdentifier:
            self.version = .v3
        }
        self.signerIdentifier = signerIdentifier
        self.digestAlgorithm = digestAlgorithm
        self.signedAttrs = signedAttrs
        self.signatureAlgorithm = signatureAlgorithm
        self.signature = signature
        self.unsignedAttrs = unsignedAttrs
    }

    @inlinable
    init(
        version: CMSVersion,
        signerIdentifier: CMSSignerIdentifier,
        digestAlgorithm: AlgorithmIdentifier,
        signedAttrs: [CMSAttribute]? = nil,
        signatureAlgorithm: AlgorithmIdentifier,
        signature: ASN1OctetString,
        unsignedAttrs: [CMSAttribute]? = nil
    ) {
        self.version = version
        self.signerIdentifier = signerIdentifier
        self.digestAlgorithm = digestAlgorithm
        self.signedAttrs = signedAttrs
        self.signatureAlgorithm = signatureAlgorithm
        self.signature = signature
        self.unsignedAttrs = unsignedAttrs
    }

    @inlinable
    init(derEncoded rootNode: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        self = try DER.sequence(rootNode, identifier: identifier) { nodes in
            let version = try CMSVersion(rawValue: Int(derEncoded: &nodes))
            let signerIdentifier = try CMSSignerIdentifier(derEncoded: &nodes)
            switch signerIdentifier {
            case .issuerAndSerialNumber:
                guard version == .v1 else {
                    throw Error.versionAndSignerIdentifierMismatch(
                        "expected \(CMSVersion.v1) but got \(version) where signerIdentifier is \(signerIdentifier)"
                    )
                }
            case .subjectKeyIdentifier:
                guard version == .v3 else {
                    throw Error.versionAndSignerIdentifierMismatch(
                        "expected \(CMSVersion.v3) but got \(version) where signerIdentifier is \(signerIdentifier)"
                    )
                }
            }
            let digestAlgorithm = try AlgorithmIdentifier(derEncoded: &nodes)

            let signedAttrs = try DER.optionalImplicitlyTagged(&nodes, tagNumber: 0, tagClass: .contextSpecific) {
                node in
                return try DER.set(
                    of: CMSAttribute.self,
                    identifier: .init(tagWithNumber: 0, tagClass: .contextSpecific),
                    rootNode: node
                )
            }

            let signatureAlgorithm = try AlgorithmIdentifier(derEncoded: &nodes)
            let signature = try ASN1OctetString(derEncoded: &nodes)

            let unsignedAttrs = try DER.optionalImplicitlyTagged(&nodes, tagNumber: 1, tagClass: .contextSpecific) {
                node in
                return try DER.set(
                    of: CMSAttribute.self,
                    identifier: .init(tagWithNumber: 0, tagClass: .contextSpecific),
                    rootNode: node
                )
            }

            return .init(
                version: version,
                signerIdentifier: signerIdentifier,
                digestAlgorithm: digestAlgorithm,
                signedAttrs: signedAttrs,
                signatureAlgorithm: signatureAlgorithm,
                signature: signature,
                unsignedAttrs: unsignedAttrs
            )
        }
    }

    @inlinable
    init(berEncoded rootNode: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        self = try BER.sequence(rootNode, identifier: identifier) { nodes in
            let version = try CMSVersion(rawValue: Int(derEncoded: &nodes))
            let signerIdentifier = try CMSSignerIdentifier(berEncoded: &nodes)
            switch signerIdentifier {
            case .issuerAndSerialNumber:
                guard version == .v1 else {
                    throw Error.versionAndSignerIdentifierMismatch(
                        "expected \(CMSVersion.v1) but got \(version) where signerIdentifier is \(signerIdentifier)"
                    )
                }
            case .subjectKeyIdentifier:
                guard version == .v3 else {
                    throw Error.versionAndSignerIdentifierMismatch(
                        "expected \(CMSVersion.v3) but got \(version) where signerIdentifier is \(signerIdentifier)"
                    )
                }
            }
            let digestAlgorithm = try AlgorithmIdentifier(berEncoded: &nodes)

             
            let signedAttrs = try DER.optionalImplicitlyTagged(&nodes, tagNumber: 0, tagClass: .contextSpecific) {
                node in
                return try DER.set(
                    of: CMSAttribute.self,
                    identifier: .init(tagWithNumber: 0, tagClass: .contextSpecific),
                    rootNode: node
                )
            }

            let signatureAlgorithm = try AlgorithmIdentifier(berEncoded: &nodes)
            let signature = try ASN1OctetString(berEncoded: &nodes)

            let unsignedAttrs = try BER.optionalImplicitlyTagged(&nodes, tagNumber: 1, tagClass: .contextSpecific) {
                node in
                return try BER.set(
                    of: CMSAttribute.self,
                    identifier: .init(tagWithNumber: 0, tagClass: .contextSpecific),
                    rootNode: node
                )
            }

            return .init(
                version: version,
                signerIdentifier: signerIdentifier,
                digestAlgorithm: digestAlgorithm,
                signedAttrs: signedAttrs,
                signatureAlgorithm: signatureAlgorithm,
                signature: signature,
                unsignedAttrs: unsignedAttrs
            )
        }
    }

    @inlinable
    func serialize(into coder: inout DER.Serializer, withIdentifier identifier: ASN1Identifier) throws {
        try coder.appendConstructedNode(identifier: identifier) { coder in
            try coder.serialize(self.version.rawValue)
            try coder.serialize(self.signerIdentifier)
            try coder.serialize(self.digestAlgorithm)
            if let signedAttrs = self.signedAttrs {
                try coder.serializeSetOf(signedAttrs, identifier: .init(tagWithNumber: 0, tagClass: .contextSpecific))
            }
            try coder.serialize(self.signatureAlgorithm)
            try coder.serialize(self.signature)
            if let unsignedAttrs = self.unsignedAttrs {
                try coder.serializeSetOf(unsignedAttrs, identifier: .init(tagWithNumber: 1, tagClass: .contextSpecific))
            }
        }
    }
}

 
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CMSSignerInfo {
    @inlinable
     
     
    func _signedAttrsBytes() throws -> ArraySlice<UInt8> {
        precondition(self.signedAttrs != nil)
        var coder = DER.Serializer()
        try coder.serializeSetOf(self.signedAttrs!)
        return coder.serializedBytes[...]
    }
}

 

extension Array where Element == CMSAttribute {
    @inlinable
    subscript(oid: ASN1ObjectIdentifier) -> CMSAttribute? {
        if let attr = self.first(where: { $0.attrType == oid }) {
            return attr
        }
        return nil
    }
}

extension Array where Element == CMSAttribute {
    @inlinable
    var signingTime: Date? {
        get throws {
            if let attr = self[.signingTime] {
                guard attr.attrValues.count == 1 else {
                    throw ASN1Error.invalidASN1Object(reason: "Signing time attribute must have a single value")
                }
                let time = try Time(asn1Any: attr.attrValues[0])
                return Date(time)
            }
            return nil
        }
    }

    @inlinable
    var messageDigest: ArraySlice<UInt8>? {
        get throws {
            if let attr = self[.messageDigest] {
                guard attr.attrValues.count == 1 else {
                    throw ASN1Error.invalidASN1Object(reason: "Message digest attribute must have a single value")
                }
                let octets = try ASN1OctetString(asn1Any: attr.attrValues[0])
                return octets.bytes
            }
            return nil
        }
    }
}

extension ASN1ObjectIdentifier {
    @usableFromInline
    static let messageDigest: Self = [1, 2, 840, 113549, 1, 9, 4]

    @usableFromInline
    static let signingTime: Self = [1, 2, 840, 113549, 1, 9, 5]

    @usableFromInline
    static let contentType: Self = [1, 2, 840, 113549, 1, 9, 3]
}
