 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1
import _CertificateInternals

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct RelativeDistinguishedName {
    @usableFromInline
    var attributes: _TinyArray<Attribute>

     
     
     
    @inlinable
    public init<AttributeSequence: Sequence>(_ attributes: AttributeSequence)
    where AttributeSequence.Element == RelativeDistinguishedName.Attribute {
        self.attributes = .init(attributes)
        Self._sortElements(&self.attributes)
    }

     
     
     
    @inlinable
    public init(_ attribute: Attribute) {
        self.init(CollectionOfOne(attribute))
    }

    @inlinable
    init(_ attributes: DER.LazySetOfSequence<Attribute>) throws {
        self.attributes = try .init(attributes)
        Self._sortElements(&self.attributes)
    }

     
    @inlinable
    public init() {
        self.attributes = .init()
    }
}

extension RelativeDistinguishedName: Hashable {}

extension RelativeDistinguishedName: Sendable {}

extension RelativeDistinguishedName: RandomAccessCollection {
    @inlinable
    public var startIndex: Int {
        self.attributes.startIndex
    }

    @inlinable
    public var endIndex: Int {
        self.attributes.endIndex
    }

    @inlinable
    public subscript(position: Int) -> RelativeDistinguishedName.Attribute {
        get {
            self.attributes[position]
        }
    }

     
     
     
    @inlinable
    public mutating func insert(_ attribute: RelativeDistinguishedName.Attribute) {
        self.attributes.append(attribute)
        Self._sortElements(&self.attributes)
    }

     
     
     
     
     
    @inlinable
    public mutating func insert<Attributes: Collection>(contentsOf attributes: Attributes)
    where Attributes.Element == RelativeDistinguishedName.Attribute {
        self.attributes.append(contentsOf: attributes)
        Self._sortElements(&self.attributes)
    }

     
     
     
     
    @inlinable
    @discardableResult
    public mutating func remove(at index: Int) -> Element {
        self.attributes.remove(at: index)
         
    }

     
     
     
     
    @inlinable
    public mutating func removeAll(where shouldBeRemoved: (Attribute) throws -> Bool) rethrows {
        try self.attributes.removeAll(where: shouldBeRemoved)
         
    }
}

extension RelativeDistinguishedName: CustomStringConvertible {
    @inlinable
    public var description: String {
        self.lazy.map {
            String(describing: $0)
        }.joined(separator: "+")
    }
}

extension RelativeDistinguishedName: CustomDebugStringConvertible {
    public var debugDescription: String {
        String(reflecting: String(describing: self))
    }
}

extension RelativeDistinguishedName: DERImplicitlyTaggable {
    @inlinable
    public static var defaultIdentifier: ASN1Identifier {
        .set
    }

    @inlinable
    public init(derEncoded rootNode: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        try self.init(DER.lazySet(identifier: identifier, rootNode: rootNode))
    }

    @inlinable
    public func serialize(into coder: inout DER.Serializer, withIdentifier identifier: ASN1Identifier) throws {
        try coder.serializeSetOf(self.attributes, identifier: identifier)
    }

    @inlinable
    static func _sortElements(_ elements: inout _TinyArray<RelativeDistinguishedName.Attribute>) {
         
         
         
         
        try! elements.sort { lhs, rhs in
            var serializer = DER.Serializer()
            try serializer.serialize(lhs)
            let lhsBytes = serializer.serializedBytes

            serializer = DER.Serializer()
            try serializer.serialize(rhs)
            let rhsBytes = serializer.serializedBytes

             
            for (leftByte, rightByte) in zip(lhsBytes, rhsBytes) {
                if leftByte < rightByte {
                     
                    return true
                } else if rightByte < leftByte {
                     
                    return false
                }
            }

             
             
            let trailing = rhsBytes.dropFirst(lhsBytes.count)
            if trailing.count == 0 || trailing.allSatisfy({ $0 == 0 }) {
                 
                return false
            }
            return true
        }
    }
}
