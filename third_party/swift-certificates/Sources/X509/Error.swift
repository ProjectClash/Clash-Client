 
 
 
 
 
 
 
 
 
 
 
 
 

 
 
 
 
 
 
 
 
 
 
public struct CertificateError: Error, Hashable, CustomStringConvertible {
    private var backing: Backing

     
    public var code: ErrorCode {
        get {
            self.backing.code
        }
        set {
            self.makeUnique()
            self.backing.code = newValue
        }
    }

    private var reason: String {
        self.backing.reason
    }

    private var file: String {
        self.backing.file
    }

    private var line: UInt {
        self.backing.line
    }

    public var description: String {
        "CertificateError.\(self.code): \(self.reason) \(self.file):\(self.line)"
    }

    private mutating func makeUnique() {
        if !isKnownUniquelyReferenced(&self.backing) {
            self.backing = self.backing.copy()
        }
    }

     
     
     
     
     
    @inline(never)
    public static func unsupportedSignatureAlgorithm(
        reason: String,
        file: String = #fileID,
        line: UInt = #line
    ) -> CertificateError {
        return CertificateError(
            backing: .init(
                code: .unsupportedSignatureAlgorithm,
                reason: reason,
                file: file,
                line: line
            )
        )
    }

     
     
     
     
     
    @inline(never)
    public static func unsupportedPublicKeyAlgorithm(
        reason: String,
        file: String = #fileID,
        line: UInt = #line
    ) -> CertificateError {
        return CertificateError(
            backing: .init(
                code: .unsupportedPublicKeyAlgorithm,
                reason: reason,
                file: file,
                line: line
            )
        )
    }

     
     
     
     
     
    @inline(never)
    public static func invalidSignatureForCertificate(
        reason: String,
        file: String = #fileID,
        line: UInt = #line
    ) -> CertificateError {
        return CertificateError(
            backing: .init(
                code: .invalidSignatureForCertificate,
                reason: reason,
                file: file,
                line: line
            )
        )
    }

     
     
     
     
     
    @inline(never)
    public static func incorrectOIDForExtension(
        reason: String,
        file: String = #fileID,
        line: UInt = #line
    ) -> CertificateError {
        return CertificateError(
            backing: .init(
                code: .incorrectOIDForExtension,
                reason: reason,
                file: file,
                line: line
            )
        )
    }

     
     
     
     
     
    @inline(never)
    public static func unsupportedDigestAlgorithm(
        reason: String,
        file: String = #fileID,
        line: UInt = #line
    ) -> CertificateError {
        return CertificateError(
            backing: .init(
                code: .unsupportedDigestAlgorithm,
                reason: reason,
                file: file,
                line: line
            )
        )
    }

     
     
     
     
     
    @inline(never)
    public static func unsupportedPrivateKey(
        reason: String,
        file: String = #fileID,
        line: UInt = #line
    ) -> CertificateError {
        return CertificateError(
            backing: .init(
                code: .unsupportedPrivateKey,
                reason: reason,
                file: file,
                line: line
            )
        )
    }

     
     
     
     
     
    @inline(never)
    public static func incorrectOIDForAttribute(
        reason: String,
        file: String = #fileID,
        line: UInt = #line
    ) -> CertificateError {
        return CertificateError(
            backing: .init(
                code: .incorrectOIDForAttribute,
                reason: reason,
                file: file,
                line: line
            )
        )
    }

     
     
     
     
     
    @inline(never)
    public static func invalidCSRAttribute(
        reason: String,
        file: String = #fileID,
        line: UInt = #line
    ) -> CertificateError {
        return CertificateError(
            backing: .init(
                code: .invalidCSRAttribute,
                reason: reason,
                file: file,
                line: line
            )
        )
    }

     
     
     
     
     
    @inline(never)
    public static func duplicateOID(
        reason: String,
        file: String = #fileID,
        line: UInt = #line
    ) -> CertificateError {
        return CertificateError(
            backing: .init(
                code: .duplicateOID,
                reason: reason,
                file: file,
                line: line
            )
        )
    }

     
     
     
     
     
    @inline(never)
    public static func failedToLoadSystemTrustStore(
        reason: String,
        file: String = #fileID,
        line: UInt = #line
    ) -> CertificateError {
        return CertificateError(
            backing: .init(
                code: .failedToLoadSystemTrustStore,
                reason: reason,
                file: file,
                line: line
            )
        )
    }
}

 
extension CertificateError: @unchecked Sendable {}

extension CertificateError {
     
     
     
     
     
    public struct ErrorCode: Hashable, Sendable, CustomStringConvertible {
        fileprivate enum BackingCode {
            case unsupportedSignatureAlgorithm
            case unsupportedPublicKeyAlgorithm
            case invalidSignatureForCertificate
            case incorrectOIDForExtension
            case unsupportedDigestAlgorithm
            case unsupportedPrivateKey
            case incorrectOIDForAttribute
            case invalidCSRAttribute
            case duplicateOID
            case failedToLoadSystemTrustStore
        }

        fileprivate var backingCode: BackingCode

        fileprivate init(_ backingCode: BackingCode) {
            self.backingCode = backingCode
        }

         
        public static let unsupportedSignatureAlgorithm = ErrorCode(.unsupportedSignatureAlgorithm)

         
        public static let unsupportedPublicKeyAlgorithm = ErrorCode(.unsupportedPublicKeyAlgorithm)

         
        public static let invalidSignatureForCertificate = ErrorCode(.invalidSignatureForCertificate)

         
        public static let incorrectOIDForExtension = ErrorCode(.incorrectOIDForExtension)

         
        public static let unsupportedDigestAlgorithm = ErrorCode(.unsupportedDigestAlgorithm)

         
        public static let unsupportedPrivateKey = ErrorCode(.unsupportedPrivateKey)

         
        public static let incorrectOIDForAttribute = ErrorCode(.incorrectOIDForAttribute)

         
        public static let invalidCSRAttribute = ErrorCode(.invalidCSRAttribute)

         
        public static let duplicateOID = ErrorCode(.duplicateOID)

         
        public static let failedToLoadSystemTrustStore = ErrorCode(.failedToLoadSystemTrustStore)

        public var description: String {
            return String(describing: self.backingCode)
        }
    }
}

extension CertificateError {
    final class Backing: Hashable {
        var code: CertificateError.ErrorCode

        let reason: String

        let file: String

        let line: UInt

        fileprivate init(
            code: CertificateError.ErrorCode,
            reason: String,
            file: String,
            line: UInt
        ) {
            self.code = code
            self.reason = reason
            self.file = file
            self.line = line
        }

         
        static func == (lhs: Backing, rhs: Backing) -> Bool {
            return lhs.code == rhs.code
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(self.code)
        }

        fileprivate func copy() -> Backing {
            return Backing(code: self.code, reason: self.reason, file: self.file, line: self.line)
        }
    }
}
