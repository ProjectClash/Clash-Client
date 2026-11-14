 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CertificateSigningRequest {
     
     
     
     
     
     
     
     
    public struct Attribute {
         
         
         
        public var oid: ASN1ObjectIdentifier

         
         
         
        public var values: [ASN1Any]

         
         
         
         
         
        @inlinable
        public init(oid: ASN1ObjectIdentifier, values: [ASN1Any]) {
            self.oid = oid
            self.values = values
        }
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CertificateSigningRequest.Attribute: Hashable {
    @inlinable
    public static func == (lhs: CertificateSigningRequest.Attribute, rhs: CertificateSigningRequest.Attribute) -> Bool {
        if lhs.oid != rhs.oid { return false }
        if lhs.values.count != rhs.values.count { return false }

        for element in lhs.values {
            if !rhs.values.contains(element) { return false }
        }

        return true
    }

    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.oid)

         
         
         
        var hash = 0
        for element in self.values {
            var newHasher = Hasher()
            element.hash(into: &newHasher)
            hash ^= newHasher.finalize()
        }

        hasher.combine(hash)
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CertificateSigningRequest.Attribute: Sendable {}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CertificateSigningRequest.Attribute: CustomStringConvertible {
    public var description: String {
        return "Attribute(oid: \(self.oid), values: \(self.values))"
    }
}

 
 
 
 
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CertificateSigningRequest.Attribute: DERImplicitlyTaggable {
    @inlinable
    public static var defaultIdentifier: ASN1Identifier {
        .sequence
    }

    @inlinable
    public init(derEncoded rootNode: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        self = try DER.sequence(rootNode, identifier: identifier) { nodes in
            let type = try ASN1ObjectIdentifier(derEncoded: &nodes)
            let values = try DER.set(of: ASN1Any.self, identifier: .set, nodes: &nodes)

            return CertificateSigningRequest.Attribute(oid: type, values: values)
        }
    }

    @inlinable
    public func serialize(into coder: inout DER.Serializer, withIdentifier identifier: ASN1Identifier) throws {
        try coder.appendConstructedNode(identifier: identifier) { coder in
            try coder.serialize(self.oid)
            try coder.serializeSetOf(self.values)
        }
    }
}

extension ASN1ObjectIdentifier {
     
    public enum CSRAttributes {
         
        public static let extensionRequest: ASN1ObjectIdentifier = [1, 2, 840, 113549, 1, 9, 14]
    }
}
