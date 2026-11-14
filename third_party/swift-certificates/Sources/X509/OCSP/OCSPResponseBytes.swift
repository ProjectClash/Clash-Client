 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

 
 
 
 
 
 
 
 
 
 
 
 
 
struct OCSPResponseBytes: DERImplicitlyTaggable, Hashable {
    static var defaultIdentifier: ASN1Identifier {
        .sequence
    }

    var responseType: ASN1ObjectIdentifier

    var response: ASN1OctetString

    init(responseType: ASN1ObjectIdentifier, response: ASN1OctetString) {
        self.responseType = responseType
        self.response = response
    }

    init(derEncoded rootNode: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        self = try DER.sequence(rootNode, identifier: identifier) { nodes in
            let responseType = try ASN1ObjectIdentifier(derEncoded: &nodes)
            let response = try ASN1OctetString(derEncoded: &nodes)
            return .init(responseType: responseType, response: response)
        }
    }

    func serialize(into coder: inout DER.Serializer, withIdentifier identifier: ASN1Identifier) throws {
        try coder.appendConstructedNode(identifier: identifier) { coder in
            try coder.serialize(self.responseType)
            try coder.serialize(self.response)
        }
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension BasicOCSPResponse {
    init(decoding original: OCSPResponseBytes) throws {
        guard original.responseType == .OCSP.basicResponse else {
            throw ASN1Error.invalidASN1Object(reason: "Cannot decode BasicOCSPResponse from \(original.responseType)")
        }

        self = try .init(derEncoded: original.response.bytes)
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension OCSPResponseBytes {
    init(encoding original: BasicOCSPResponse) throws {
        self.responseType = .OCSP.basicResponse
        self.response = ASN1OctetString(contentBytes: try DER.Serializer.serialized(element: original)[...])
    }
}
