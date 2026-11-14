 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

 
 
 
public struct OrganizationalUnitName: RelativeDistinguishedNameConvertible {
     
    public var name: String

     
     
     
    @inlinable
    public init(_ name: String) {
        self.name = name
    }

    @inlinable
    public func makeRDN() throws -> RelativeDistinguishedName {
        return RelativeDistinguishedName(
            .init(type: .RDNAttributeType.organizationalUnitName, utf8String: name)
        )
    }
}
