 
 
 
 
 
 
 
 
 
 
 
 
 

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@resultBuilder
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
public struct ExtensionsBuilder {
    @inlinable
    public static func buildExpression<Extension: CertificateExtensionConvertible>(
        _ expression: Extension
    ) -> Result<Certificate.Extensions, any Error> {
        Result {
            try Certificate.Extensions([expression.makeCertificateExtension()])
        }
    }

    @inlinable
    public static func buildExpression(
        _ expression: Certificate.Extensions
    ) -> Result<Certificate.Extensions, any Error> {
        .success(expression)
    }

    @inlinable
    public static func buildExpression() -> Result<Certificate.Extensions, any Error> {
        .success(Certificate.Extensions())
    }

    @inlinable
    public static func buildBlock() -> Result<Certificate.Extensions, any Error> {
        .success(Certificate.Extensions())
    }

    @inlinable
    public static func buildBlock(
        _ components: Result<Certificate.Extensions, any Error>...
    ) -> Result<Certificate.Extensions, any Error> {
        Result {
            try Certificate.Extensions(try components.lazy.flatMap { try $0.get() })
        }
    }

    @inlinable
    public static func buildOptional(
        _ component: Result<Certificate.Extensions, any Error>?
    ) -> Result<Certificate.Extensions, any Error> {
        component ?? .success(Certificate.Extensions())
    }

    @inlinable
    public static func buildEither(
        first component: Result<Certificate.Extensions, any Error>
    ) -> Result<Certificate.Extensions, any Error> {
        component
    }

    @inlinable
    public static func buildEither(
        second component: Result<Certificate.Extensions, any Error>
    ) -> Result<Certificate.Extensions, any Error> {
        component
    }

    @inlinable
    public static func buildArray(
        _ components: [Result<Certificate.Extensions, any Error>]
    ) -> Result<Certificate.Extensions, any Error> {
        Result {
            try Certificate.Extensions(try components.lazy.flatMap { try $0.get() })
        }
    }

    @inlinable
    public static func buildLimitedAvailability(
        _ component: Result<Certificate.Extensions, any Error>
    ) -> Result<Certificate.Extensions, any Error> {
        component
    }
}

 
 
 
 
 
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
public protocol CertificateExtensionConvertible {
     
    func makeCertificateExtension() throws -> Certificate.Extension
}

 
 
 
@frozen
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
public struct Critical<BaseExtension: CertificateExtensionConvertible>: CertificateExtensionConvertible {
     
    public var base: BaseExtension

     
    @inlinable
    public init(_ base: BaseExtension) {
        self.base = base
    }

    @inlinable
    public func makeCertificateExtension() throws -> Certificate.Extension {
        var ext = try self.base.makeCertificateExtension()
        ext.critical = true
        return ext
    }
}
