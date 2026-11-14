 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

 
 
 
public struct DomainComponent: RelativeDistinguishedNameConvertible {
     
    public var name: String

     
     
     
    @inlinable
    public init(_ name: String) {
        self.name = name
    }

    @inlinable
    public func makeRDN() throws -> RelativeDistinguishedName {
        return RelativeDistinguishedName(
            try .init(type: .RDNAttributeType.domainComponent, ia5String: name)
        )
    }
}
