 
 
 
 
 
 
 
 
 
 
 
 
 

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftASN1
import Crypto

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Curve25519.Signing.PrivateKey {
    @inlinable
    init(pkcs8Key: PKCS8PrivateKey) throws {
         
        let rawRepresentation = try ASN1OctetString(derEncoded: pkcs8Key.privateKey.bytes)
        self = try .init(rawRepresentation: rawRepresentation.bytes)
    }

    @inlinable
    var derRepresentation: [UInt8] {
         
         
         
        let pkcs8Key = PKCS8PrivateKey(
            algorithm: .ed25519,
            privateKey: ASN1OctetString(contentBytes: ArraySlice(self.rawRepresentation))
        )
        var serializer = DER.Serializer()
        try! serializer.serialize(pkcs8Key)
        return serializer.serializedBytes
    }

    @inlinable
    var pemRepresentation: PEMDocument {
        return PEMDocument(type: "PRIVATE KEY", derBytes: self.derRepresentation)
    }
}
