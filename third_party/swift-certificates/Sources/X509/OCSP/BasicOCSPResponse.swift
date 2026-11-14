 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 

 
 
 
 
 
 
 
 
 
 
 
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
struct BasicOCSPResponse: DERImplicitlyTaggable, Hashable {
    static var defaultIdentifier: ASN1Identifier {
        .sequence
    }

    var responseData: OCSPResponseData

    var responseDataBytes: ArraySlice<UInt8>

    var signatureAlgorithm: AlgorithmIdentifier

    var signature: ASN1BitString

    var certs: [Certificate]?

    init(
        responseData: OCSPResponseData,
        responseDataBytes: ArraySlice<UInt8>,
        signatureAlgorithm: AlgorithmIdentifier,
        signature: ASN1BitString,
        certs: [Certificate]?
    ) {
        self.responseData = responseData
        self.responseDataBytes = responseDataBytes
        self.signatureAlgorithm = signatureAlgorithm
        self.signature = signature
        self.certs = certs
    }
    init(derEncoded rootNode: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        self = try DER.sequence(rootNode, identifier: identifier) { nodes in
            guard let responseDataNode = nodes.next() else {
                throw ASN1Error.invalidASN1Object(reason: "missing OCSP response data")
            }
            let responseData = try OCSPResponseData(derEncoded: responseDataNode)
            let signatureAlgorithm = try AlgorithmIdentifier(derEncoded: &nodes)
            let signature = try ASN1BitString(derEncoded: &nodes)

            let certs = try DER.optionalExplicitlyTagged(&nodes, tagNumber: 0, tagClass: .contextSpecific) { node in
                try DER.sequence(of: Certificate.self, identifier: .sequence, rootNode: node)
            }

            return .init(
                responseData: responseData,
                responseDataBytes: responseDataNode.encodedBytes,
                signatureAlgorithm: signatureAlgorithm,
                signature: signature,
                certs: certs
            )
        }
    }

    func serialize(into coder: inout DER.Serializer, withIdentifier identifier: ASN1Identifier) throws {
        try coder.appendConstructedNode(identifier: identifier) { coder in
            coder.serializeRawBytes(self.responseDataBytes)
            try coder.serialize(self.signatureAlgorithm)
            try coder.serialize(self.signature)
            if let certs {
                try coder.serialize(explicitlyTaggedWithTagNumber: 0, tagClass: .contextSpecific) { coder in
                    try coder.serializeSequenceOf(certs)
                }
            }
        }
    }
}

enum ResponderID: DERParseable, DERSerializable, Hashable {
    case byName(DistinguishedName)
     
    case byKey(ASN1OctetString)

    private static let nameIdentifier = ASN1Identifier(tagWithNumber: 1, tagClass: .contextSpecific)
    private static let keyIdentifier = ASN1Identifier(tagWithNumber: 2, tagClass: .contextSpecific)

    init(derEncoded: ASN1Node) throws {
        switch derEncoded.identifier {
        case ResponderID.nameIdentifier:
            guard case .constructed(let nodes) = derEncoded.content else {
                throw ASN1Error.invalidASN1Object(reason: "ResponderID content must be constructed.")
            }
            var iterator = nodes.makeIterator()
            guard let rootNode = iterator.next(), iterator.next() == nil else {
                throw ASN1Error.invalidASN1Object(reason: "Invalid number of responder nodes.")
            }

            self = try .byName(.init(derEncoded: rootNode))
        case ResponderID.keyIdentifier:
            guard case .constructed(let nodes) = derEncoded.content else {
                throw ASN1Error.invalidASN1Object(reason: "ResponderID content must be constructed")
            }
            var iterator = nodes.makeIterator()
            guard let rootNode = iterator.next(), iterator.next() == nil else {
                throw ASN1Error.invalidASN1Object(reason: "Invalid number of responder nodes")
            }

            self = try .byKey(.init(derEncoded: rootNode))
        default:
            throw ASN1Error.unexpectedFieldType(derEncoded.identifier)
        }
    }

    func serialize(into coder: inout DER.Serializer) throws {
        switch self {
        case .byName(let name):
            try coder.appendConstructedNode(identifier: ResponderID.nameIdentifier) { coder in
                try name.serialize(into: &coder)
            }
        case .byKey(let key):
            try coder.appendConstructedNode(identifier: ResponderID.keyIdentifier) { coder in
                try key.serialize(into: &coder)
            }
        }
    }
}
