 
 
 
 
 
 
 
 
 
 
 
 
 

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate {
     
     
     
     
     
     
     
     
    public struct SignatureAlgorithm {
        @usableFromInline
        var _algorithmIdentifier: AlgorithmIdentifier

        @inlinable
        init(algorithmIdentifier: AlgorithmIdentifier) {
            switch algorithmIdentifier {
             
             
             
            case .sha1WithRSAEncryptionUsingNil:
                self._algorithmIdentifier = .sha1WithRSAEncryption
            case .sha256WithRSAEncryptionUsingNil:
                self._algorithmIdentifier = .sha256WithRSAEncryption
            case .sha384WithRSAEncryptionUsingNil:
                self._algorithmIdentifier = .sha384WithRSAEncryption
            case .sha512WithRSAEncryptionUsingNil:
                self._algorithmIdentifier = .sha512WithRSAEncryption
            case let identifier:
                self._algorithmIdentifier = identifier
            }
        }

         
        public static let ecdsaWithSHA256 = Self(algorithmIdentifier: .ecdsaWithSHA256)

         
        public static let ecdsaWithSHA384 = Self(algorithmIdentifier: .ecdsaWithSHA384)

         
        public static let ecdsaWithSHA512 = Self(algorithmIdentifier: .ecdsaWithSHA512)

         
        public static let sha1WithRSAEncryption = Self(algorithmIdentifier: .sha1WithRSAEncryption)

         
        public static let sha256WithRSAEncryption = Self(algorithmIdentifier: .sha256WithRSAEncryption)

         
        public static let sha384WithRSAEncryption = Self(algorithmIdentifier: .sha384WithRSAEncryption)

         
        public static let sha512WithRSAEncryption = Self(algorithmIdentifier: .sha512WithRSAEncryption)

         
        public static let ed25519 = Self(algorithmIdentifier: .ed25519)

         
        @inlinable
        var isECDSA: Bool {
            switch self {
            case .ecdsaWithSHA256, .ecdsaWithSHA384, .ecdsaWithSHA512:
                return true
            default:
                return false
            }
        }

        @inlinable
        var isRSA: Bool {
            switch self {
            case .sha1WithRSAEncryption, .sha256WithRSAEncryption, .sha384WithRSAEncryption, .sha512WithRSAEncryption:
                return true
            default:
                return false
            }
        }
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.SignatureAlgorithm: Hashable {}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.SignatureAlgorithm: Sendable {}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.SignatureAlgorithm: CustomStringConvertible {
    public var description: String {
        switch self {
        case .ecdsaWithSHA256:
            return "SignatureAlgorithm.ecdsaWithSHA256"
        case .ecdsaWithSHA384:
            return "SignatureAlgorithm.ecdsaWithSHA384"
        case .ecdsaWithSHA512:
            return "SignatureAlgorithm.ecdsaWithSHA512"
        case .sha1WithRSAEncryption:
            return "SignatureAlgorithm.sha1WithRSAEncryption"
        case .sha256WithRSAEncryption:
            return "SignatureAlgorithm.sha256WithRSAEncryption"
        case .sha384WithRSAEncryption:
            return "SignatureAlgorithm.sha384WithRSAEncryption"
        case .sha512WithRSAEncryption:
            return "SignatureAlgorithm.sha512WithRSAEncryption"
        case .ed25519:
            return "SignatureAlgorithm.ed25519"
        default:
            return "SignatureAlgorithm(\(self._algorithmIdentifier))"
        }

    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension AlgorithmIdentifier {
    @inlinable
    init(_ signatureAlgorithm: Certificate.SignatureAlgorithm) {
        self = signatureAlgorithm._algorithmIdentifier
    }

    @inlinable
    init(digestAlgorithmFor signatureAlgorithm: Certificate.SignatureAlgorithm) throws {
         
         
        switch signatureAlgorithm {
        case .ecdsaWithSHA256, .sha256WithRSAEncryption:
            self = .sha256UsingNil
        case .ecdsaWithSHA384, .sha384WithRSAEncryption:
            self = .sha384UsingNil
        case .ecdsaWithSHA512, .sha512WithRSAEncryption, .ed25519:
            self = .sha512UsingNil
        case .sha1WithRSAEncryption:
            self = .sha1
        default:
            throw CertificateError.unsupportedSignatureAlgorithm(
                reason: "Cannot generate digest algorithm for \(signatureAlgorithm)"
            )
        }
    }
}
