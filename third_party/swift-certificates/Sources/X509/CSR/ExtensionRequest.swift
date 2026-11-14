 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

 
 
 
 
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
public struct ExtensionRequest: Hashable, Sendable {
     
    public var extensions: Certificate.Extensions

     
     
     
     
    @inlinable
    public init(extensions: Certificate.Extensions) {
        self.extensions = extensions
    }

     
     
     
     
     
    @inlinable
    public init(_ attribute: CertificateSigningRequest.Attribute) throws {
        guard attribute.oid == .CSRAttributes.extensionRequest else {
            throw CertificateError.incorrectOIDForAttribute(
                reason: "Expected \(ASN1ObjectIdentifier.CSRAttributes.extensionRequest), got \(attribute.oid)"
            )
        }

        guard attribute.values.count == 1 else {
            throw CertificateError.invalidCSRAttribute(
                reason: "Invalid number of values for extension request attribute: \(attribute.values)"
            )
        }

        let extRequest = try ExtensionRequestAttribute(asn1Any: attribute.values.first!)
        self.extensions = extRequest.extensions
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CertificateSigningRequest.Attribute {
     
     
     
     
    @inlinable
    public init(_ extensionRequest: ExtensionRequest) throws {
        self.init(
            oid: .CSRAttributes.extensionRequest,
            values: [try ASN1Any(erasing: ExtensionRequestAttribute(extensionRequest))]
        )
    }
}

@usableFromInline
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
struct ExtensionRequestAttribute: Hashable, Sendable, DERImplicitlyTaggable {
    @inlinable
    static var defaultIdentifier: ASN1Identifier {
        .sequence
    }

    @usableFromInline
    var extensions: Certificate.Extensions

    @inlinable
    init(_ extensionRequest: ExtensionRequest) {
        self.extensions = extensionRequest.extensions
    }

    @inlinable
    init(derEncoded rootNode: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        self.extensions = try Certificate.Extensions(
            DER.sequence(
                of: Certificate.Extension.self,
                identifier: identifier,
                rootNode: rootNode
            )
        )
    }

    @inlinable
    func serialize(into coder: inout DER.Serializer, withIdentifier identifier: ASN1Identifier) throws {
        try coder.serializeSequenceOf(self.extensions, identifier: identifier)
    }
}
