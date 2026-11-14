 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

 
 
 
 
 
 
 
 
 
 
@usableFromInline
struct RSAPKCS1PublicKey: DERImplicitlyTaggable, Hashable, Sendable {
    @inlinable
    static var defaultIdentifier: ASN1Identifier {
        .sequence
    }

    @usableFromInline
    var modulus: ArraySlice<UInt8>

    @usableFromInline
    var publicExponent: ArraySlice<UInt8>

    @inlinable
    init(derEncoded rootNode: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        self = try DER.sequence(rootNode, identifier: identifier) { nodes in
            let modulus = try ArraySlice(derEncoded: &nodes)
            let publicExponent = try ArraySlice(derEncoded: &nodes)

            return RSAPKCS1PublicKey(modulus: modulus, publicExponent: publicExponent)
        }
    }

    @inlinable
    init(modulus: ArraySlice<UInt8>, publicExponent: ArraySlice<UInt8>) {
        self.modulus = modulus
        self.publicExponent = publicExponent
    }

    @inlinable
    func serialize(into coder: inout DER.Serializer, withIdentifier identifier: ASN1Identifier) throws {
        try coder.appendConstructedNode(identifier: identifier) { coder in
            try coder.serialize(self.modulus)
            try coder.serialize(self.publicExponent)
        }
    }
}
