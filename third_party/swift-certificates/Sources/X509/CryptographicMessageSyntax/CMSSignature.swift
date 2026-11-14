 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1
#if canImport(FoundationEssentials)
import FoundationEssentials
#elseif canImport(Darwin) || swift(>=5.9.1)
import Foundation
#else
@preconcurrency import Foundation
#endif

 
 
 
 
 
@_spi(CMS)
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
public struct CMSSignature: Sendable, Hashable {
    @usableFromInline
    let base: CMSSignedData

     
    @inlinable
    public var signers: [Signer] {
        get throws {
            try self.base.signerInfos.compactMap { signerInfo in
                try self.base.certificates?.certificate(signerInfo: signerInfo).map {
                    Signer(certificate: $0, signingTime: try signerInfo.signedAttrs?.signingTime)
                }
            }
        }
    }

     
    @inlinable
    public var certificates: [Certificate] {
        self.base.certificates ?? []
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CMSSignature: DERImplicitlyTaggable, BERImplicitlyTaggable {
    @inlinable
    public static var defaultIdentifier: ASN1Identifier {
        CMSContentInfo.defaultIdentifier
    }

    @inlinable
    public init(derEncoded rootNode: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        guard let base = try CMSContentInfo(derEncoded: rootNode, withIdentifier: identifier).signedData,
            base.version == .v1 || base.version == .v4
        else {
            throw CMS.Error.unexpectedCMSType
        }

        self.base = base
    }

    @inlinable
    public init(berEncoded rootNode: ASN1Node, withIdentifier identifier: ASN1Identifier) throws {
        guard let base = try CMSContentInfo(berEncoded: rootNode, withIdentifier: identifier).signedData,
            base.version == .v1 || base.version == .v4
        else {
            throw CMS.Error.unexpectedCMSType
        }

        self.base = base
    }

    @inlinable
    public func serialize(into coder: inout DER.Serializer, withIdentifier identifier: ASN1Identifier) throws {
        try CMSContentInfo(self.base).serialize(into: &coder, withIdentifier: identifier)
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CMSSignature {
     
     
     
     
    @_spi(CMS)
    public struct Signer: Sendable, Hashable {
        public let certificate: Certificate

        public let signingTime: Date?

        @inlinable
        init(certificate: Certificate, signingTime: Date? = nil) {
            self.certificate = certificate
            self.signingTime = signingTime
        }
    }
}
