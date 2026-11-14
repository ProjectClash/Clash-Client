 
 
 
 
 
 
 
 
 
 
 
 
 

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@resultBuilder
public struct DistinguishedNameBuilder {
    @inlinable
    public static func buildExpression<Extension: RelativeDistinguishedNameConvertible>(
        _ expression: Extension
    ) -> Result<DistinguishedName, any Error> {
        Result {
            try DistinguishedName([expression.makeRDN()])
        }
    }

    @inlinable
    public static func buildBlock(
        _ components: Result<DistinguishedName, any Error>...
    ) -> Result<DistinguishedName, any Error> {
        Result {
            DistinguishedName(try components.flatMap { try $0.get() })
        }
    }

    @inlinable
    public static func buildOptional(
        _ component: Result<DistinguishedName, any Error>?
    ) -> Result<DistinguishedName, any Error> {
        component ?? .success(DistinguishedName())
    }

    @inlinable
    public static func buildEither(
        first component: Result<DistinguishedName, any Error>
    ) -> Result<DistinguishedName, any Error> {
        component
    }

    @inlinable
    public static func buildEither(
        second component: Result<DistinguishedName, any Error>
    ) -> Result<DistinguishedName, any Error> {
        component
    }

    @inlinable
    public static func buildArray(
        _ components: [Result<DistinguishedName, any Error>]
    ) -> Result<DistinguishedName, any Error> {
        Result {
            DistinguishedName(try components.flatMap { try $0.get() })
        }
    }

    @inlinable
    public static func buildLimitedAvailability(
        _ component: Result<DistinguishedName, any Error>
    ) -> Result<DistinguishedName, any Error> {
        component
    }
}

public protocol RelativeDistinguishedNameConvertible {
    func makeRDN() throws -> RelativeDistinguishedName
}
