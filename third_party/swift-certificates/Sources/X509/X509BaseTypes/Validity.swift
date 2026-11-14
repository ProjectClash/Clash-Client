 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

 
 
 
@usableFromInline
struct Validity: DERImplicitlyTaggable, Hashable, Sendable {
    @inlinable
    static var defaultIdentifier: ASN1Identifier {
        .sequence
    }

    @usableFromInline
    var notBefore: Time

    @usableFromInline
    var notAfter: Time

    @inlinable
    internal init(notBefore: Time, notAfter: Time) {
        self.notBefore = notBefore
        self.notAfter = notAfter
    }

    @inlinable
    init(derEncoded rootNode: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        self = try DER.sequence(rootNode, identifier: identifier) { nodes in
            let notBefore = try Time(derEncoded: &nodes)
            let notAfter = try Time(derEncoded: &nodes)
            return Validity(notBefore: notBefore, notAfter: notAfter)
        }
    }

    @inlinable
    func serialize(into coder: inout DER.Serializer, withIdentifier identifier: ASN1Identifier) throws {
        try coder.appendConstructedNode(identifier: identifier) { coder in
            try coder.serialize(self.notBefore)
            try coder.serialize(self.notAfter)
        }
    }
}
