 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

 
 
 
 
 
 
 
@usableFromInline
struct CMSEncapsulatedContentInfo: DERImplicitlyTaggable, BERImplicitlyTaggable, Hashable, Sendable {
    @inlinable
    static var defaultIdentifier: ASN1Identifier {
        .sequence
    }

    @usableFromInline
    var eContentType: ASN1ObjectIdentifier

    @usableFromInline
    var eContent: ASN1OctetString?

    @inlinable
    init(eContentType: ASN1ObjectIdentifier, eContent: ASN1OctetString? = nil) {
        self.eContentType = eContentType
        self.eContent = eContent
    }

    @inlinable
    init(derEncoded rootNode: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        self = try DER.sequence(rootNode, identifier: identifier) { nodes in
            let eContentType = try ASN1ObjectIdentifier(derEncoded: &nodes)
            let eContent = try DER.optionalExplicitlyTagged(&nodes, tagNumber: 0, tagClass: .contextSpecific) { node in
                try ASN1OctetString(derEncoded: node)
            }

            return .init(eContentType: eContentType, eContent: eContent)
        }
    }

    @inlinable
    init(berEncoded rootNode: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        self = try BER.sequence(rootNode, identifier: identifier) { nodes in
            let eContentType = try ASN1ObjectIdentifier(derEncoded: &nodes)
            let eContent = try BER.optionalExplicitlyTagged(&nodes, tagNumber: 0, tagClass: .contextSpecific) { node in
                try ASN1OctetString(berEncoded: node)
            }

            return .init(eContentType: eContentType, eContent: eContent)
        }
    }

    @inlinable
    func serialize(into coder: inout DER.Serializer, withIdentifier identifier: ASN1Identifier) throws {
        try coder.appendConstructedNode(
            identifier: identifier,
            { coder in
                try coder.serialize(eContentType)
                if let eContent {
                    try coder.serialize(explicitlyTaggedWithTagNumber: 0, tagClass: .contextSpecific) { coder in
                        try coder.serialize(eContent)
                    }
                }
            }
        )
    }
}
