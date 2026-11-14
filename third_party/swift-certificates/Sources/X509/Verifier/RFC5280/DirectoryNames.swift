 
 
 
 
 
 
 
 
 
 
 
 
 

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension NameConstraintsPolicy {
     
     
     
     
     
    @inlinable
    static func directoryNameMatchesConstraint(directoryName: DistinguishedName, constraint: DistinguishedName) -> Bool
    {
        return directoryName == constraint
    }
}
