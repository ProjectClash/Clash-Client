 
 
 
 
 
 
 
 
 
 
 
 
 

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
public struct UnverifiedCertificateChain: Sendable, Hashable {
    @usableFromInline
    var certificates: [Certificate]

    init(_ certificates: [Certificate]) {
        precondition(!certificates.isEmpty)
        self.certificates = certificates
    }

    @inlinable
    public var leaf: Certificate {
        self.certificates.first!
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension UnverifiedCertificateChain: RandomAccessCollection {
    @inlinable
    public var startIndex: Int {
        self.certificates.startIndex
    }

    @inlinable
    public var endIndex: Int {
        self.certificates.endIndex
    }

    @inlinable
    public subscript(position: Int) -> Certificate {
        get {
            self.certificates[position]
        }
    }
}
