 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct DistinguishedName {
    @usableFromInline
    var rdns: [RelativeDistinguishedName]

     
     
     
    @inlinable
    public init<RDNSequence: Sequence>(_ rdns: RDNSequence) where RDNSequence.Element == RelativeDistinguishedName {
        self.rdns = Array(rdns)
    }

     
     
     
     
     
     
    @inlinable
    public init<AttributeSequence: Sequence>(_ attributes: AttributeSequence) throws
    where AttributeSequence.Element == RelativeDistinguishedName.Attribute {
        self.rdns = attributes.map { RelativeDistinguishedName($0) }
    }

     
    @inlinable
    public init() {
        self.rdns = []
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @inlinable
    public init(@DistinguishedNameBuilder builder: () throws -> Result<DistinguishedName, any Error>) throws {
        self = try builder().get()
    }
}

extension DistinguishedName: Hashable {}

extension DistinguishedName: Sendable {}

extension DistinguishedName: RandomAccessCollection, MutableCollection, RangeReplaceableCollection {
    @inlinable
    public var startIndex: Int {
        self.rdns.startIndex
    }

    @inlinable
    public var endIndex: Int {
        self.rdns.endIndex
    }

    @inlinable
    public subscript(position: Int) -> RelativeDistinguishedName {
        get {
            self.rdns[position]
        }
        set {
            self.rdns[position] = newValue
        }
    }

    @inlinable
    public mutating func replaceSubrange<NewElements>(_ subrange: Range<Int>, with newElements: NewElements)
    where NewElements: Collection, RelativeDistinguishedName == NewElements.Element {
        self.rdns.replaceSubrange(subrange, with: newElements)
    }
}

extension DistinguishedName: CustomStringConvertible {
    @inlinable
    public var description: String {
        self.reversed().lazy.map { String(describing: $0) }.joined(separator: ",")
    }
}

extension DistinguishedName: CustomDebugStringConvertible {
    public var debugDescription: String {
        String(reflecting: String(describing: self))
    }
}

extension DistinguishedName: DERSerializable {
    @inlinable
    public func serialize(into coder: inout DER.Serializer) throws {
        try coder.appendConstructedNode(identifier: .sequence) { rootCoder in
            for element in self.rdns {
                try element.serialize(into: &rootCoder)
            }
        }
    }
}

extension DistinguishedName: DERParseable {
    @inlinable
    public init(derEncoded rootNode: ASN1Node) throws {
        self.rdns = try DER.sequence(of: RelativeDistinguishedName.self, identifier: .sequence, rootNode: rootNode)
    }

    @inlinable
    static func derEncoded(_ sequenceNodeIterator: inout ASN1NodeCollection.Iterator) throws -> DistinguishedName {
         
         
        let dnFactory: (inout ASN1NodeCollection.Iterator) throws -> DistinguishedName =
            DistinguishedName.init(derEncoded:)
        return try dnFactory(&sequenceNodeIterator)
    }
}

@available(*, deprecated, message: "Distinguished names may not be implicitly tagged")
extension DistinguishedName: DERImplicitlyTaggable {
    @inlinable
    public static var defaultIdentifier: ASN1Identifier {
        .sequence
    }

    @inlinable
    public init(derEncoded rootNode: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        self.rdns = try DER.sequence(of: RelativeDistinguishedName.self, identifier: identifier, rootNode: rootNode)
    }

    @inlinable
    public func serialize(into coder: inout DER.Serializer, withIdentifier identifier: ASN1Identifier) throws {
        try coder.appendConstructedNode(identifier: identifier) { rootCoder in
            for element in self.rdns {
                try element.serialize(into: &rootCoder)
            }
        }
    }
}
