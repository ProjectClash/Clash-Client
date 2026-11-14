 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public struct Extension {
         
         
         
        public var oid: ASN1ObjectIdentifier

         
         
         
         
        public var critical: Bool

         
         
         
        public var value: ArraySlice<UInt8>

         
         
         
         
         
         
        @inlinable
        public init(oid: ASN1ObjectIdentifier, critical: Bool, value: ArraySlice<UInt8>) {
            self.oid = oid
            self.critical = critical
            self.value = value
        }
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.Extension: Hashable {}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.Extension: Sendable {}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.Extension: CustomStringConvertible {
    public var description: String {
        if let knownExtension = try? AuthorityInformationAccess(self) {
            return String(reflecting: knownExtension)
        } else if let knownExtension = try? SubjectKeyIdentifier(self) {
            return String(reflecting: knownExtension)
        } else if let knownExtension = try? AuthorityKeyIdentifier(self) {
            return String(reflecting: knownExtension)
        } else if let knownExtension = try? ExtendedKeyUsage(self) {
            return String(reflecting: knownExtension)
        } else if let knownExtension = try? BasicConstraints(self) {
            return String(reflecting: knownExtension)
        } else if let knownExtension = try? KeyUsage(self) {
            return String(reflecting: knownExtension)
        } else if let knownExtension = try? NameConstraints(self) {
            return String(reflecting: knownExtension)
        } else if let knownExtension = try? SubjectAlternativeNames(self) {
            return String(reflecting: knownExtension)
        } else {
            return """
                Extension(\
                oid: \(String(reflecting: self.oid)), \
                critical: \(String(reflecting: self.critical)), \
                value: \(self.value.count) bytes\
                )
                """
        }
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.Extension: DERImplicitlyTaggable {
    @inlinable
    public static var defaultIdentifier: ASN1Identifier {
        .sequence
    }

    @inlinable
    public init(derEncoded rootNode: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        self = try DER.sequence(rootNode, identifier: identifier) { nodes in
            let extensionID = try ASN1ObjectIdentifier(derEncoded: &nodes)
            let critical = try DER.decodeDefault(&nodes, defaultValue: false)
            let value = try ASN1OctetString(derEncoded: &nodes)

            return Certificate.Extension(oid: extensionID, critical: critical, value: value.bytes)
        }
    }

    @inlinable
    public func serialize(into coder: inout DER.Serializer, withIdentifier identifier: ASN1Identifier) throws {
        try coder.appendConstructedNode(identifier: identifier) { coder in
            try coder.serialize(self.oid)

            if self.critical {
                try coder.serialize(self.critical)
            }

            try coder.serialize(ASN1OctetString(contentBytes: self.value))
        }
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.Extension: CertificateExtensionConvertible {
    public func makeCertificateExtension() -> Certificate.Extension {
        self
    }
}
