 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

 
 
 
 
 
 
 
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
struct OCSPSingleRequest: DERImplicitlyTaggable, Hashable {
    static var defaultIdentifier: ASN1Identifier {
        .sequence
    }

    var certID: OCSPCertID

    var singleRequestExtensions: Certificate.Extensions?

    init(certID: OCSPCertID, singleRequestExtensions: Certificate.Extensions? = nil) {
        self.certID = certID
        self.singleRequestExtensions = singleRequestExtensions
    }

    init(derEncoded: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        self = try DER.sequence(derEncoded, identifier: identifier) { nodes in
            let certID = try OCSPCertID(derEncoded: &nodes)
            let singleRequestExtensions = try DER.optionalExplicitlyTagged(
                &nodes,
                tagNumber: 0,
                tagClass: .contextSpecific
            ) { node in
                try Certificate.Extensions(
                    try DER.sequence(of: Certificate.Extension.self, identifier: .sequence, rootNode: node)
                )
            }
            return .init(certID: certID, singleRequestExtensions: singleRequestExtensions)
        }
    }

    func serialize(into coder: inout DER.Serializer, withIdentifier identifier: ASN1Identifier) throws {
        try coder.appendConstructedNode(identifier: identifier) { coder in
            try self.certID.serialize(into: &coder)
            if let singleRequestExtensions = self.singleRequestExtensions {
                try coder.serialize(explicitlyTaggedWithTagNumber: 0, tagClass: .contextSpecific) { coder in
                    try coder.serializeSequenceOf(singleRequestExtensions)
                }
            }
        }
    }
}
