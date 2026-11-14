 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public struct Extensions {
        @usableFromInline
        var _extensions: [Certificate.Extension]

         
         
         
         
        @inlinable
        public init<Elements>(_ extensions: Elements) throws where Elements: Sequence, Elements.Element == Extension {
            self._extensions = Array(extensions)

             
             
             
             
             
            let maxExtensions = 32
            guard self._extensions.count <= maxExtensions else {
                throw ASN1Error.invalidASN1Object(
                    reason:
                        "Too many extensions. Found \(self._extensions.count) but only \(maxExtensions) are allowed."
                )
            }

            if let (firstIndex, secondIndex) = self._extensions.findDuplicates(by: { $0.oid == $1.oid }) {
                let firstExt = self._extensions[firstIndex]
                let secondExt = self._extensions[secondIndex]
                throw CertificateError.duplicateOID(
                    reason:
                        "duplicate extension for OID \(firstExt.oid). First extension \(firstExt) at \(firstIndex) and second extension \(secondExt) at \(secondIndex)"
                )
            }
        }

         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        @inlinable
        public init(@ExtensionsBuilder builder: () throws -> Result<Certificate.Extensions, any Error>) throws {
            self = try builder().get()
        }
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.Extensions: Hashable {}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.Extensions: Sendable {}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.Extensions: RandomAccessCollection {
     
    @inlinable
    public init() {
        self._extensions = []
    }

    @inlinable
    public var startIndex: Int {
        self._extensions.startIndex
    }

    @inlinable
    public var endIndex: Int {
        self._extensions.endIndex
    }

    @inlinable
    public subscript(position: Int) -> Certificate.Extension {
        get {
            self._extensions[position]
        }
    }
}

 
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.Extensions {

     
     
     
     
    @inlinable
    public mutating func append(_ extension: Certificate.Extension) throws {
        if let oldExtension = self._extensions.first(where: { $0.oid == `extension`.oid }) {
            throw CertificateError.duplicateOID(
                reason:
                    "tried to append an extension for OID \(`extension`.oid) which is already present. Old extension: \(oldExtension) New extension: \(`extension`)"
            )
        } else {
            self._extensions.append(`extension`)
        }
    }

     
     
     
     
     
    @inlinable
    @discardableResult
    public mutating func update(_ extension: Certificate.Extension) -> Certificate.Extension? {
        guard let index = self._extensions.firstIndex(where: { $0.oid == `extension`.oid }) else {
            self._extensions.append(`extension`)
            return nil
        }
        let oldExtension = self._extensions[index]
        self._extensions[index] = `extension`
        return oldExtension
    }

     
     
     
     
    @inlinable
    @discardableResult
    public mutating func remove(_ oid: ASN1ObjectIdentifier) -> Certificate.Extension? {
        guard let index = self._extensions.firstIndex(where: { $0.oid == oid }) else {
            return nil
        }
        return self._extensions.remove(at: index)
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.Extensions: CustomStringConvertible {
    @inlinable
    public var description: String {
        guard self.isEmpty else {
            return self._extensions.lazy.map { String(reflecting: $0) }.joined(separator: ", ")
        }
        return "(none)"
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.Extensions: CustomDebugStringConvertible {
    public var debugDescription: String {
        "[\(String(describing: self))]"
    }
}

 
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.Extensions {
     
     
     
    @inlinable
    public subscript(oid oid: ASN1ObjectIdentifier) -> Certificate.Extension? {
        get {
            self._extensions.first(where: { $0.oid == oid })
        }
        set {
            if let newValue = newValue {
                precondition(oid == newValue.oid)
                self.update(newValue)
            } else {
                self.remove(oid)
            }
        }
    }

     
     
     
     
    @inlinable
    public var authorityInformationAccess: AuthorityInformationAccess? {
        get throws {
            try self[oid: .X509ExtensionID.authorityInformationAccess].map { try .init($0) }
        }
    }

     
     
     
     
    @inlinable
    public var subjectKeyIdentifier: SubjectKeyIdentifier? {
        get throws {
            try self[oid: .X509ExtensionID.subjectKeyIdentifier].map { try .init($0) }
        }
    }

     
     
     
     
    @inlinable
    public var authorityKeyIdentifier: AuthorityKeyIdentifier? {
        get throws {
            try self[oid: .X509ExtensionID.authorityKeyIdentifier].map { try .init($0) }
        }
    }

     
     
     
     
    @inlinable
    public var extendedKeyUsage: ExtendedKeyUsage? {
        get throws {
            try self[oid: .X509ExtensionID.extendedKeyUsage].map { try .init($0) }
        }
    }

     
     
     
     
    @inlinable
    public var basicConstraints: BasicConstraints? {
        get throws {
            try self[oid: .X509ExtensionID.basicConstraints].map { try .init($0) }
        }
    }

     
     
     
     
    @inlinable
    public var keyUsage: KeyUsage? {
        get throws {
            try self[oid: .X509ExtensionID.keyUsage].map { try .init($0) }
        }
    }

     
     
     
     
    @inlinable
    public var nameConstraints: NameConstraints? {
        get throws {
            try self[oid: .X509ExtensionID.nameConstraints].map { try .init($0) }
        }
    }

     
     
     
     
    @inlinable
    public var subjectAlternativeNames: SubjectAlternativeNames? {
        get throws {
            try self[oid: .X509ExtensionID.subjectAlternativeName].map { try .init($0) }
        }
    }
}
