 
 
 
 
 
 
 
 
 
 
 
 
 

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate {
     
     
     
     
     
    public struct Version {
        @usableFromInline
        var rawValue: Int

        @inlinable
        init(rawValue: Int) {
            self.rawValue = rawValue
        }

         
        public static let v1 = Self(rawValue: 0)

         
        public static let v3 = Self(rawValue: 2)
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.Version: Hashable {}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.Version: Sendable {}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.Version: Comparable {
    @inlinable
    public static func < (lhs: Certificate.Version, rhs: Certificate.Version) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.Version: CustomStringConvertible {
    public var description: String {
        switch self {
        case .v1:
            return "X509v1"
        case .v3:
            return "X509v3"
        case let unknown:
            return "X509v\(unknown.rawValue + 1)"
        }
    }
}
