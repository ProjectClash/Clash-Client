 
 
 
 
 
 
 
 
 
 
 
 
 

#if canImport(FoundationEssentials)
import FoundationEssentials
import Dispatch
#else
import Foundation
#endif
import SwiftASN1

 
 
 
private let rootCAFileSearchPaths = [
    "/etc/ssl/certs/ca-certificates.crt",   
    "/etc/pki/tls/certs/ca-bundle.crt",   
]

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CertificateStore {
     
     
     
     
     
     
     
     
     
     
    public static let systemTrustRoots: CertificateStore = {
         
        _ = cachedSystemTrustRootsFuture
        return CertificateStore(systemTrustStore: true)
    }()

    static let cachedSystemTrustRootsFuture: Future<[DistinguishedName: [Certificate]], any Error> =
        DispatchQueue(
            label: "com.apple.swift-certificates.trust-roots",
            qos: .userInteractive
        ).asyncFuture {
            try Self.loadTrustRoots(at: rootCAFileSearchPaths)
        }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension CertificateStore {
    @_spi(Testing)
    public static func loadTrustRoots(at searchPaths: [String]) throws -> [DistinguishedName: [Certificate]] {
        var fileLoadingErrors = [(path: String, error: any Error)]()

        for path in searchPaths {
            let pemEncodedData: Data
            do {
                pemEncodedData = try Data(contentsOf: URL(fileURLWithPath: path))
            } catch {
                 
                 
                fileLoadingErrors.append((path, error))
                continue
            }

            return try parseTrustRoot(from: pemEncodedData)
        }

        throw CertificateError.failedToLoadSystemTrustStore(
            reason: fileLoadingErrors.lazy.map {
                "(\(String(reflecting: $0.path)): \(String(reflecting: $0.error)))"
            }.joined(separator: ", ")
        )
    }

    static func parseTrustRoot(from pemEncodedData: Data) throws -> [DistinguishedName: [Certificate]] {
        let pemEncodedString = String(decoding: pemEncodedData, as: UTF8.self)
        let documents = try PEMDocument.parseMultiple(pemString: pemEncodedString)
        return Dictionary(
            grouping: try documents.lazy.map {
                try Certificate(pemDocument: $0)
            },
            by: \.subject
        )
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension DispatchQueue {
    func asyncFuture<Success: Sendable>(
        withResultOf work: @Sendable @escaping () throws -> Success
    ) -> Future<Success, any Error> {
        let promise = Promise<Success, any Error>()
        self.async {
            promise.fulfil(with: Result { try work() })
        }
        return Future(promise)
    }
}
