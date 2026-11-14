 
 
 
 
 
 
 
 
 
 
 
 
 

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CertificateSigningRequest {
     
     
     
     
    public struct Version {
        public var rawValue: Int

        @inlinable
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

         
        public static let v1 = Self(rawValue: 0)
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CertificateSigningRequest.Version: Hashable {}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CertificateSigningRequest.Version: Sendable {}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CertificateSigningRequest.Version: Comparable {
    @inlinable
    public static func < (lhs: CertificateSigningRequest.Version, rhs: CertificateSigningRequest.Version) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CertificateSigningRequest.Version: CustomStringConvertible {
    public var description: String {
        switch self {
        case .v1:
            return "CSRv1"
        case let unknown:
            return "CSRv\(unknown.rawValue + 1)"
        }
    }
}
