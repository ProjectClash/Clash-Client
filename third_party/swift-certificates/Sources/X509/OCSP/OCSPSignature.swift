 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

 
 
 
 
 
 
 
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
struct OCSPSignature: DERImplicitlyTaggable, Hashable {
    static var defaultIdentifier: ASN1Identifier {
        .sequence
    }

    var algorithmIIdentifier: AlgorithmIdentifier

    var signature: ASN1BitString

    var certs: [Certificate]?

    init(algorithmIIdentifier: AlgorithmIdentifier, signature: ASN1BitString, certs: [Certificate]? = nil) {
        self.algorithmIIdentifier = algorithmIIdentifier
        self.signature = signature
        self.certs = certs
    }

    init(derEncoded: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        self = try DER.sequence(derEncoded, identifier: identifier) { nodes in
            let algorithmIdentifier = try AlgorithmIdentifier(derEncoded: &nodes)
            let signature = try ASN1BitString(derEncoded: &nodes)
            let certs = try DER.optionalExplicitlyTagged(&nodes, tagNumber: 0, tagClass: .contextSpecific) { node in
                try DER.sequence(of: Certificate.self, identifier: .sequence, rootNode: node)
            }
            return .init(algorithmIIdentifier: algorithmIdentifier, signature: signature, certs: certs)
        }
    }

    func serialize(into coder: inout DER.Serializer, withIdentifier identifier: ASN1Identifier) throws {
        try coder.appendConstructedNode(identifier: identifier) { coder in
            try self.algorithmIIdentifier.serialize(into: &coder)
            try self.signature.serialize(into: &coder)
            if let certs = self.certs {
                try coder.serialize(explicitlyTaggedWithTagNumber: 0, tagClass: .contextSpecific) { coder in
                    try coder.serializeSequenceOf(certs)
                }
            }
        }
    }
}
