 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

 
 
 
 
 
 
 
 
 
 
 
 
 
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
struct OCSPResponseData: DERImplicitlyTaggable, Hashable {
    static var defaultIdentifier: ASN1Identifier {
        .sequence
    }

    var version: OCSPVersion

    var responderID: ResponderID

    var producedAt: GeneralizedTime

    var responses: [OCSPSingleResponse]

    var responseExtensions: Certificate.Extensions?

    init(
        version: OCSPVersion = .v1,
        responderID: ResponderID,
        producedAt: GeneralizedTime,
        responses: [OCSPSingleResponse],
        responseExtensions: Certificate.Extensions? = nil
    ) {
        self.version = version
        self.responderID = responderID
        self.producedAt = producedAt
        self.responses = responses
        self.responseExtensions = responseExtensions
    }

    init(derEncoded rootNode: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        self = try DER.sequence(rootNode, identifier: identifier) { nodes in
            let version = try DER.decodeDefaultExplicitlyTagged(
                &nodes,
                tagNumber: 0,
                tagClass: .contextSpecific,
                defaultValue: 0
            ) { try Int(derEncoded: $0) }
            let responderID = try ResponderID(derEncoded: &nodes)
            let producedAt = try GeneralizedTime(derEncoded: &nodes)
            let responses = try DER.sequence(of: OCSPSingleResponse.self, identifier: .sequence, nodes: &nodes)
            let responseExtensions = try DER.optionalExplicitlyTagged(&nodes, tagNumber: 1, tagClass: .contextSpecific)
            { node in
                try DER.sequence(of: Certificate.Extension.self, identifier: .sequence, rootNode: node)
            }

            return .init(
                version: .init(rawValue: version),
                responderID: responderID,
                producedAt: producedAt,
                responses: responses,
                responseExtensions: try responseExtensions.map { try .init($0) }
            )
        }
    }

    func serialize(into coder: inout DER.Serializer, withIdentifier identifier: ASN1Identifier) throws {
        try coder.appendConstructedNode(identifier: identifier) { coder in
            if self.version != .v1 {
                try coder.serialize(self.version.rawValue, explicitlyTaggedWithTagNumber: 0, tagClass: .contextSpecific)
            }

            try coder.serialize(self.responderID)
            try coder.serialize(self.producedAt)
            try coder.serializeSequenceOf(self.responses)

            if let responseExtensions = self.responseExtensions {
                try coder.serialize(explicitlyTaggedWithTagNumber: 1, tagClass: .contextSpecific) { coder in
                    try coder.serializeSequenceOf(responseExtensions)
                }
            }
        }
    }
}
