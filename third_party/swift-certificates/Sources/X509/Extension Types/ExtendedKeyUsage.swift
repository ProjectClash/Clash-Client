 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

 
 
 
public struct ExtendedKeyUsage {
    @usableFromInline
    var usages: [Usage]

     
     
     
     
    @inlinable
    public init<Usages: Sequence>(_ usages: Usages) throws where Usages.Element == Usage {
        self.usages = Array(usages)

         
         
         
         
         
        let maxUsages = 32
        guard self.usages.count <= maxUsages else {
            throw ASN1Error.invalidASN1Object(
                reason: "Too many extended key usages. Found \(self.usages.count) but only \(maxUsages) are allowed."
            )
        }

        if let (firstIndex, secondIndex) = self.usages.findDuplicates(by: ==) {
            let usage = self.usages[firstIndex]
            throw CertificateError.duplicateOID(
                reason: "duplicate \(usage) usage. First at \(firstIndex) and second at \(secondIndex)"
            )
        }
    }

     
     
     
     
     
     
    @inlinable
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
    public init(_ ext: Certificate.Extension) throws {
        guard ext.oid == .X509ExtensionID.extendedKeyUsage else {
            throw CertificateError.incorrectOIDForExtension(
                reason: "Expected \(ASN1ObjectIdentifier.X509ExtensionID.extendedKeyUsage), got \(ext.oid)"
            )
        }

        let asn1EKU = try ASN1ExtendedKeyUsage(derEncoded: ext.value)
        try self.init(asn1EKU.usages.map { Usage(oid: $0) })
    }

     
    @inlinable
    public init() {
        self.usages = []
    }
}

extension Array {
    @inlinable
     
     
     
     
    func findDuplicates(
        by areEqual: (Element, Element) -> Bool
    ) -> (first: Index, second: Index)? {
        for index in self.indices {
            let usage = self[index]
            for currentIndex in self.indices[index...].dropFirst() {
                let currentUsage = self[currentIndex]
                if areEqual(usage, currentUsage) {
                    return (index, currentIndex)
                }
            }
        }
        return nil
    }
}

extension ExtendedKeyUsage: Hashable {}

extension ExtendedKeyUsage: Sendable {}

extension ExtendedKeyUsage: CustomStringConvertible {
    public var description: String {
        return self.map {
            String(reflecting: $0)
        }.joined(separator: ", ")
    }
}

extension ExtendedKeyUsage: CustomDebugStringConvertible {
    public var debugDescription: String {
        "ExtendedKeyUsage(\(String(describing: self)))"
    }
}

extension ExtendedKeyUsage: RandomAccessCollection {
    public var startIndex: Int {
        self.usages.startIndex
    }

    public var endIndex: Int {
        self.usages.endIndex
    }

    public subscript(position: Int) -> Usage {
        get {
            self.usages[position]
        }
    }
}

extension ExtendedKeyUsage {
     
     
     
     
     
     
     
     
    @inlinable
    @discardableResult
    public mutating func append(_ usage: Element) -> (inserted: Bool, index: Int) {
        self.insert(usage, at: self.endIndex)
    }

     
     
     
     
     
     
     
     
     
     
     
    @inlinable
    @discardableResult
    public mutating func insert(
        _ usage: Element,
        at index: Int
    ) -> (inserted: Bool, index: Int) {
        guard let index = self.usages.firstIndex(of: usage) else {
            self.usages.insert(usage, at: index)
            return (true, index)
        }
        return (false, index)
    }

     
     
     
    @inlinable
    @discardableResult
    public mutating func remove(_ usage: Element) -> Element? {
        guard let index = self.usages.firstIndex(where: { $0 == usage }) else {
            return nil
        }
        return self.usages.remove(at: index)
    }
}

extension ExtendedKeyUsage {
     
     
     
    public struct Usage {
        @usableFromInline
        enum Backing {
            case serverAuth
            case clientAuth
            case codeSigning
            case emailProtection
            case timeStamping
            case ocspSigning
            case any
            case certificateTransparency
            case unknown(ASN1ObjectIdentifier)
        }

        @usableFromInline
        var backing: Backing

        @inlinable
        init(_ backing: Backing) {
            self.backing = backing
        }

         
         
         
        @inlinable
        public init(oid: ASN1ObjectIdentifier) {
            switch oid {
            case .ExtendedKeyUsage.serverAuth:
                self = .serverAuth
            case .ExtendedKeyUsage.clientAuth:
                self = .clientAuth
            case .ExtendedKeyUsage.codeSigning:
                self = .codeSigning
            case .ExtendedKeyUsage.emailProtection:
                self = .emailProtection
            case .ExtendedKeyUsage.timeStamping:
                self = .timeStamping
            case .ExtendedKeyUsage.ocspSigning:
                self = .ocspSigning
            case .ExtendedKeyUsage.any:
                self = .any
            case .ExtendedKeyUsage.certificateTransparency:
                self = .certificateTransparency
            default:
                self.backing = .unknown(oid)
            }
        }

         
        public static let serverAuth = Self(.serverAuth)

         
        public static let clientAuth = Self(.clientAuth)

         
        public static let codeSigning = Self(.codeSigning)

         
        public static let emailProtection = Self(.emailProtection)

         
        public static let timeStamping = Self(.timeStamping)

         
        public static let ocspSigning = Self(.ocspSigning)

         
        public static let any = Self(.any)

         
        public static let certificateTransparency = Self(.certificateTransparency)
    }
}

extension ExtendedKeyUsage.Usage: Hashable {}

extension ExtendedKeyUsage.Usage: Sendable {}

extension ExtendedKeyUsage.Usage: CustomStringConvertible {
    public var description: String {
        switch self.backing {
        case .any:
            return "anyKeyUsage"
        case .serverAuth:
            return "serverAuth"
        case .clientAuth:
            return "clientAuth"
        case .codeSigning:
            return "codeSigning"
        case .emailProtection:
            return "emailProtection"
        case .timeStamping:
            return "timeStamping"
        case .ocspSigning:
            return "ocspSigning"
        case .certificateTransparency:
            return "certificateTransparency"
        case .unknown(let oid):
            return String(describing: oid)
        }
    }
}

extension ExtendedKeyUsage.Usage: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self.backing {
        case .any:
            return "anyKeyUsage"
        case .serverAuth:
            return "serverAuth"
        case .clientAuth:
            return "clientAuth"
        case .codeSigning:
            return "codeSigning"
        case .emailProtection:
            return "emailProtection"
        case .timeStamping:
            return "timeStamping"
        case .ocspSigning:
            return "ocspSigning"
        case .certificateTransparency:
            return "certificateTransparency"
        case .unknown(let oid):
            return String(reflecting: oid)
        }
    }
}

extension ExtendedKeyUsage.Usage.Backing: Hashable {}

extension ExtendedKeyUsage.Usage.Backing: Sendable {}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.Extension {
     
     
     
     
     
    @inlinable
    public init(_ eku: ExtendedKeyUsage, critical: Bool) throws {
        let asn1Representation = ASN1ExtendedKeyUsage(eku)
        var serializer = DER.Serializer()
        try serializer.serialize(asn1Representation)
        self.init(oid: .X509ExtensionID.extendedKeyUsage, critical: critical, value: serializer.serializedBytes[...])
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension ExtendedKeyUsage: CertificateExtensionConvertible {
    public func makeCertificateExtension() throws -> Certificate.Extension {
        return try .init(self, critical: false)
    }
}

extension ASN1ObjectIdentifier {
     
     
     
    @inlinable
    public init(_ usage: X509.ExtendedKeyUsage.Usage) {
        switch usage.backing {
        case .serverAuth:
            self = .ExtendedKeyUsage.serverAuth
        case .clientAuth:
            self = .ExtendedKeyUsage.clientAuth
        case .codeSigning:
            self = .ExtendedKeyUsage.codeSigning
        case .emailProtection:
            self = .ExtendedKeyUsage.emailProtection
        case .timeStamping:
            self = .ExtendedKeyUsage.timeStamping
        case .ocspSigning:
            self = .ExtendedKeyUsage.ocspSigning
        case .any:
            self = .ExtendedKeyUsage.any
        case .certificateTransparency:
            self = .ExtendedKeyUsage.certificateTransparency
        case .unknown(let oid):
            self = oid
        }
    }

     
     
     
    public enum ExtendedKeyUsage {
         
        public static let any: ASN1ObjectIdentifier = [2, 5, 29, 37, 0]

         
        public static let serverAuth: ASN1ObjectIdentifier = [1, 3, 6, 1, 5, 5, 7, 3, 1]

         
        public static let clientAuth: ASN1ObjectIdentifier = [1, 3, 6, 1, 5, 5, 7, 3, 2]

         
        public static let codeSigning: ASN1ObjectIdentifier = [1, 3, 6, 1, 5, 5, 7, 3, 3]

         
        public static let emailProtection: ASN1ObjectIdentifier = [1, 3, 6, 1, 5, 5, 7, 3, 4]

         
        public static let timeStamping: ASN1ObjectIdentifier = [1, 3, 6, 1, 5, 5, 7, 3, 8]

         
        public static let ocspSigning: ASN1ObjectIdentifier = [1, 3, 6, 1, 5, 5, 7, 3, 9]

         
        public static let certificateTransparency: ASN1ObjectIdentifier = [1, 3, 6, 1, 4, 1, 11129, 2, 4, 4]
    }
}

@usableFromInline
struct ASN1ExtendedKeyUsage: DERImplicitlyTaggable {
    @inlinable
    static var defaultIdentifier: ASN1Identifier {
        .sequence
    }

    @usableFromInline
    var usages: [ASN1ObjectIdentifier]

    @inlinable
    init(_ usages: [ASN1ObjectIdentifier]) {
        self.usages = usages
    }

    @inlinable
    init(_ eku: ExtendedKeyUsage) {
        self.usages = eku.usages.map { ASN1ObjectIdentifier($0) }
    }

    @inlinable
    init(derEncoded rootNode: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        self.usages = try DER.sequence(identifier: identifier, rootNode: rootNode)
    }

    @inlinable
    func serialize(into coder: inout DER.Serializer, withIdentifier identifier: ASN1Identifier) throws {
        try coder.serializeSequenceOf(self.usages, identifier: identifier)
    }
}
