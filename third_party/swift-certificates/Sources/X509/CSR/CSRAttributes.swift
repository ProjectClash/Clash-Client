 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CertificateSigningRequest {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public struct Attributes {
        @usableFromInline
        var _attributes: [Attribute]

         
         
         
        @inlinable
        public init<Elements>(_ attributes: Elements) where Elements: Sequence, Elements.Element == Attribute {
            self._attributes = []

            for element in attributes {
                self[oid: element.oid] = element
            }
        }
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CertificateSigningRequest.Attributes: Hashable {
    @inlinable
    public static func == (lhs: CertificateSigningRequest.Attributes, rhs: CertificateSigningRequest.Attributes) -> Bool
    {
        if lhs.count != rhs.count { return false }

        for element in lhs {
            if !rhs.contains(element) { return false }
        }

        return true
    }

    @inlinable
    public func hash(into hasher: inout Hasher) {
         
         
        var hash = 0
        for element in self {
            var newHasher = Hasher()
            element.hash(into: &newHasher)
            hash ^= newHasher.finalize()
        }

        hasher.combine(hash)
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CertificateSigningRequest.Attributes: Sendable {}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CertificateSigningRequest.Attributes: RandomAccessCollection {
    @inlinable
    public init() {
        self._attributes = []
    }

    @inlinable
    public var startIndex: Int {
        self._attributes.startIndex
    }

    @inlinable
    public var endIndex: Int {
        self._attributes.endIndex
    }

    @inlinable
    public subscript(position: Int) -> CertificateSigningRequest.Attribute {
        get {
            self._attributes[position]
        }
    }

     
     
     
     
     
    @inlinable
    public mutating func insert(_ ext: CertificateSigningRequest.Attribute) {
        self[oid: ext.oid] = ext
    }

     
     
     
     
     
     
     
    @inlinable
    public mutating func insert<Extensions: Sequence>(contentsOf extensions: Extensions)
    where Extensions.Element == CertificateSigningRequest.Attribute {
        for element in extensions {
            self[oid: element.oid] = element
        }
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CertificateSigningRequest.Attributes: CustomStringConvertible {
    @inlinable
    public var description: String {
        return "Attributes([\(self._attributes.map { String(reflecting: $0) }.joined(separator: ", "))])"
    }
}

 
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CertificateSigningRequest.Attributes {
     
     
     
    @inlinable
    public subscript(oid oid: ASN1ObjectIdentifier) -> CertificateSigningRequest.Attribute? {
        get {
            return self.first(where: { $0.oid == oid })
        }
        set {
            if let newValue = newValue {
                precondition(oid == newValue.oid)
                if let currentAttributeIndex = self.firstIndex(where: { $0.oid == oid }) {
                    self._attributes[currentAttributeIndex] = newValue
                } else {
                    self._attributes.append(newValue)
                }
            } else if let currentAttributeIndex = self.firstIndex(where: { $0.oid == oid }) {
                self._attributes.remove(at: currentAttributeIndex)
            }
        }
    }

     
     
     
     
    @inlinable
    public var extensionRequest: ExtensionRequest? {
        get throws {
            try self[oid: .CSRAttributes.extensionRequest].map { try .init($0) }
        }
    }
}
