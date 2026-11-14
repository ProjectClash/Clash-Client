 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

 
 
 
 
 
public struct AuthorityInformationAccess {
    @usableFromInline
    var descriptions: [AccessDescription]

     
     
    public init() {
        self.descriptions = []
    }

     
     
     
     
    @inlinable
    public init<Descriptions: Sequence>(_ descriptions: Descriptions) where Descriptions.Element == AccessDescription {
        self.descriptions = Array(descriptions)
    }

     
     
     
     
     
     
    @inlinable
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
    public init(_ ext: Certificate.Extension) throws {
        guard ext.oid == .X509ExtensionID.authorityInformationAccess else {
            throw CertificateError.incorrectOIDForExtension(
                reason: "Expected \(ASN1ObjectIdentifier.X509ExtensionID.authorityInformationAccess), got \(ext.oid)"
            )
        }

        let aiaSyntax = try AuthorityInfoAccessSyntax(derEncoded: ext.value)
        self.descriptions = aiaSyntax.descriptions.map { AccessDescription($0) }
    }
}

extension AuthorityInformationAccess: Hashable {}

extension AuthorityInformationAccess: Sendable {}

extension AuthorityInformationAccess: CustomStringConvertible {
    public var description: String {
        return self.map { String(reflecting: $0) }.joined(separator: ", ")
    }
}

extension AuthorityInformationAccess: CustomDebugStringConvertible {
    public var debugDescription: String {
        "AuthorityInformationAccess(\(String(describing: self)))"
    }
}

extension AuthorityInformationAccess: RandomAccessCollection {
    @inlinable
    public var startIndex: Int {
        self.descriptions.startIndex
    }

    @inlinable
    public var endIndex: Int {
        self.descriptions.endIndex
    }

    @inlinable
    public subscript(position: Int) -> AccessDescription {
        get {
            self.descriptions[position]
        }
        set {
            self.descriptions[position] = newValue
        }
    }
}

extension AuthorityInformationAccess: RangeReplaceableCollection {
    @inlinable
    public mutating func replaceSubrange(_ subrange: Range<Int>, with newElements: some Collection<AccessDescription>) {
        self.descriptions.replaceSubrange(subrange, with: newElements)
    }
}

extension AuthorityInformationAccess {
     
     
    public struct AccessDescription {
         
        public var method: AccessMethod

         
        public var location: GeneralName

         
        @inlinable
        public init(method: AccessMethod, location: GeneralName) {
            self.method = method
            self.location = location
        }

        @inlinable
        init(_ asn1Form: AIAAccessDescription) {
            self.method = .init(asn1Form.accessMethod)
            self.location = asn1Form.accessLocation
        }
    }
}

extension AuthorityInformationAccess.AccessDescription: Hashable {}

extension AuthorityInformationAccess.AccessDescription: Sendable {}

extension AuthorityInformationAccess.AccessDescription: CustomStringConvertible {
    public var description: String {
        return "\(self.method): \(self.location)"
    }
}

extension AuthorityInformationAccess.AccessDescription: CustomDebugStringConvertible {
    public var debugDescription: String {
        "(\(String(describing: self)))"
    }
}

extension AuthorityInformationAccess.AccessDescription {
     
     
     
    public struct AccessMethod {
        @usableFromInline
        var backing: Backing

        @usableFromInline
        enum Backing {
            case ocspServer
            case issuingCA
            case unknownType(ASN1ObjectIdentifier)
        }

        @inlinable
        init(_ backing: Backing) {
            self.backing = backing
        }

        @inlinable
        init(_ oid: ASN1ObjectIdentifier) {
            switch oid {
            case .AccessMethodIdentifiers.ocspServer:
                self.backing = .ocspServer
            case .AccessMethodIdentifiers.issuingCA:
                self.backing = .issuingCA
            default:
                self.backing = .unknownType(oid)
            }
        }

         
        public static let ocspServer = Self(.ocspServer)

         
        public static let issuingCA = Self(.issuingCA)
    }
}

extension AuthorityInformationAccess.AccessDescription.AccessMethod: Hashable {}

extension AuthorityInformationAccess.AccessDescription.AccessMethod: Sendable {}

extension AuthorityInformationAccess.AccessDescription.AccessMethod: CustomStringConvertible {
    @inlinable
    public var description: String {
        switch self.backing {
        case .ocspServer:
            return "OCSP Server"
        case .issuingCA:
            return "Issuer"
        case .unknownType(let oid):
            return String(describing: oid)
        }
    }
}

extension AuthorityInformationAccess.AccessDescription.AccessMethod: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self.backing {
        case .ocspServer:
            return "\"OCSP Server\""
        case .issuingCA:
            return "\"Issuer\""
        case .unknownType(let oid):
            return String(reflecting: oid)
        }
    }
}

extension AuthorityInformationAccess.AccessDescription.AccessMethod.Backing: Hashable {}

extension AuthorityInformationAccess.AccessDescription.AccessMethod.Backing: Sendable {}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.Extension {
     
     
     
     
     
    @inlinable
    public init(_ aia: AuthorityInformationAccess, critical: Bool) throws {
        let asn1Representation = AuthorityInfoAccessSyntax(aia)
        var serializer = DER.Serializer()
        try serializer.serialize(asn1Representation)
        self.init(
            oid: .X509ExtensionID.authorityInformationAccess,
            critical: critical,
            value: serializer.serializedBytes[...]
        )
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension AuthorityInformationAccess: CertificateExtensionConvertible {
    public func makeCertificateExtension() throws -> Certificate.Extension {
        return try .init(self, critical: false)
    }
}

 

 
 
 
 
 
 
@usableFromInline
struct AuthorityInfoAccessSyntax: DERImplicitlyTaggable {
    @inlinable
    static var defaultIdentifier: ASN1Identifier {
        .sequence
    }

    @usableFromInline
    var descriptions: [AIAAccessDescription]

    @inlinable
    init(_ aia: AuthorityInformationAccess) {
        self.descriptions = aia.descriptions.map { .init($0) }
    }

    @inlinable
    init(derEncoded rootNode: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        self.descriptions = try DER.sequence(of: AIAAccessDescription.self, identifier: identifier, rootNode: rootNode)
    }

    @inlinable
    func serialize(into coder: inout DER.Serializer, withIdentifier identifier: ASN1Identifier) throws {
        try coder.appendConstructedNode(identifier: identifier) { coder in
            for description in descriptions {
                try coder.serialize(description)
            }
        }
    }
}

@usableFromInline
struct AIAAccessDescription: DERImplicitlyTaggable {
    @inlinable
    static var defaultIdentifier: ASN1Identifier {
        .sequence
    }

    @usableFromInline
    var accessMethod: ASN1ObjectIdentifier

    @usableFromInline
    var accessLocation: GeneralName

    @inlinable
    init(accessMethod: ASN1ObjectIdentifier, accessLocation: GeneralName) {
        self.accessMethod = accessMethod
        self.accessLocation = accessLocation
    }

    @inlinable
    init(_ description: AuthorityInformationAccess.AccessDescription) {
        self.accessMethod = ASN1ObjectIdentifier(accessMethod: description.method)
        self.accessLocation = description.location
    }

    @inlinable
    init(derEncoded rootNode: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        self = try DER.sequence(rootNode, identifier: identifier) { nodes in
            let accessMethod = try ASN1ObjectIdentifier(derEncoded: &nodes)
            let accessLocation = try GeneralName(derEncoded: &nodes)
            return AIAAccessDescription(accessMethod: accessMethod, accessLocation: accessLocation)
        }
    }

    @inlinable
    func serialize(into coder: inout DER.Serializer, withIdentifier identifier: ASN1Identifier) throws {
        try coder.appendConstructedNode(identifier: identifier) { coder in
            try coder.serialize(self.accessMethod)
            try coder.serialize(self.accessLocation)
        }
    }
}

extension ASN1ObjectIdentifier {
    @usableFromInline
    enum AccessMethodIdentifiers {
        @usableFromInline
        static let ocspServer: ASN1ObjectIdentifier = [1, 3, 6, 1, 5, 5, 7, 48, 1]

        @usableFromInline
        static let issuingCA: ASN1ObjectIdentifier = [1, 3, 6, 1, 5, 5, 7, 48, 2]
    }

    @inlinable
    public init(accessMethod: AuthorityInformationAccess.AccessDescription.AccessMethod) {
        switch accessMethod.backing {
        case .ocspServer:
            self = .AccessMethodIdentifiers.ocspServer
        case .issuingCA:
            self = .AccessMethodIdentifiers.issuingCA
        case .unknownType(let oid):
            self = oid
        }
    }
}
