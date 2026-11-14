 
 
 
 
 
 
 
 
 
 
 
 
 

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftASN1
#if os(Windows)
import WinSDK
#elseif canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

 
 
 
 
 
 
 
 
 
 
public struct ServerIdentityPolicy {
    @usableFromInline
    var serverHostname: LazyServerHostname?

     
    @usableFromInline
    var serverIP: LazyIPAddress?

     
     
     
     
     
    @inlinable
    public init(
        serverHostname: String?,
        serverIP: String?
    ) {
        self.serverHostname = serverHostname.map { .string($0) }
        self.serverIP = serverIP.map { .string($0) }
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension ServerIdentityPolicy: VerifierPolicy {
    @inlinable
    public var verifyingCriticalExtensions: [ASN1ObjectIdentifier] {
        [.X509ExtensionID.subjectAlternativeName]
    }

    @inlinable
    public mutating func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) -> PolicyEvaluationResult {
        let targetIP = self.serverIP.convert()
        let targetHostname = self.serverHostname.convert()

         
         
         
         
         
         
        return chain.leaf.hasValidIdentityForService(
            serverHostname: targetHostname,
            serverIP: targetIP
        )
    }
}

extension ServerIdentityPolicy {
    @usableFromInline
    enum IPAddress {
        case v4(in_addr)
        case v6(in6_addr)
    }

    @usableFromInline
    enum LazyIPAddress {
        case ipAddress(IPAddress)
        case string(String)
    }

    @usableFromInline
    enum LazyServerHostname {
        case string(String)
        case prepared(PreparedServerHostname)
    }

    @usableFromInline
    struct PreparedServerHostname {
        var bytes: ArraySlice<UInt8>
        var firstPeriodIndex: ArraySlice<UInt8>.Index?

         
         
         
         
         
         
         
         
         
         
         
         
        @usableFromInline
        init?(lowercaseASCIIBytes string: String) {
            let utf8View = string.utf8
            self.firstPeriodIndex = nil

            var value: [UInt8] = []
            value.reserveCapacity(utf8View.count)

            for codeUnit in utf8View {
                guard codeUnit.isValidDNSCharacter else {
                    return nil
                }

                if self.firstPeriodIndex == nil && codeUnit == asciiPeriod {
                     
                    self.firstPeriodIndex = value.endIndex
                }

                 
                value.append(codeUnit | (0x20))
            }

            self.bytes = value[...]

             
            if self.bytes.last == asciiPeriod {
                self.bytes = self.bytes.dropLast()
            }
        }
    }

     
    @_spi(Testing)
    public static func parsingIPv4Address(_ string: String) -> in_addr? {
        var value = in_addr()

        let rc = string.withCString {
            inet_pton(AF_INET, $0, &value)
        }

        if rc != 1 { return nil }
        return value
    }

     
    @_spi(Testing)
    public static func parsingIPv6Address(_ string: String) -> in6_addr? {
        var value = in6_addr()

        let rc = string.withCString {
            inet_pton(AF_INET6, $0, &value)
        }

        if rc != 1 { return nil }
        return value
    }
}

extension Optional where Wrapped == ServerIdentityPolicy.LazyIPAddress {
     
     
     
     
    @usableFromInline
    mutating func convert() -> ServerIdentityPolicy.IPAddress? {
        switch self {
        case .some(.ipAddress(let address)):
            return address
        case .some(.string(let value)):
            if let v4 = ServerIdentityPolicy.parsingIPv4Address(value) {
                self = .some(.ipAddress(.v4(v4)))
                return .v4(v4)
            } else if let v6 = ServerIdentityPolicy.parsingIPv6Address(value) {
                self = .some(.ipAddress(.v6(v6)))
                return .v6(v6)
            } else {
                 
                 
                self = .none
                return nil
            }
        case .none:
            return nil
        }
    }
}

extension Optional where Wrapped == ServerIdentityPolicy.LazyServerHostname {
     
     
     
     
    @usableFromInline
    mutating func convert() -> ServerIdentityPolicy.PreparedServerHostname? {
        switch self {
        case .none:
            return nil
        case .some(.string(let string)):
            guard let prepared = ServerIdentityPolicy.PreparedServerHostname(lowercaseASCIIBytes: string) else {
                 
                self = .none
                return nil
            }

            self = .some(.prepared(prepared))
            return prepared
        case .some(.prepared(let prepared)):
            return prepared
        }
    }
}

extension ServerIdentityPolicy.IPAddress {
    init?(sanField: ASN1OctetString) {
        switch sanField.bytes.count {
        case 4:
            let addr = sanField.bytes.withUnsafeBufferPointer {
                UnsafeRawPointer($0.baseAddress!).loadUnaligned(as: in_addr.self)
            }
            self = .v4(addr)
        case 16:
            let addr = sanField.bytes.withUnsafeBufferPointer {
                UnsafeRawPointer($0.baseAddress!).loadUnaligned(as: in6_addr.self)
            }
            self = .v6(addr)
        default:
            return nil
        }
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate {
     
     
     
     
     
     
     
     
     
    @usableFromInline
    internal func hasValidIdentityForService(
        serverHostname: ServerIdentityPolicy.PreparedServerHostname?,
        serverIP: ServerIdentityPolicy.IPAddress?
    ) -> PolicyEvaluationResult {
         
         
         
         
         
         
        let subjectAlternativeNames: SubjectAlternativeNames
        do {
            subjectAlternativeNames = try self.extensions.subjectAlternativeNames ?? SubjectAlternativeNames()
        } catch {
            return .failsToMeetPolicy(reason: "Error parsing SAN field, cert cannot be trusted: \(error)")
        }

        var checkedMatch = false
        for name in subjectAlternativeNames {
            checkedMatch = true

            switch name {
            case .dnsName(let dnsName):
                if Self.matchHostname(serverHostname: serverHostname, dnsName: dnsName) {
                    return .meetsPolicy
                }
            case .ipAddress(let ipAddressBytes):
                if let serverIP = serverIP,
                    let certificateIP = ServerIdentityPolicy.IPAddress(sanField: ipAddressBytes),
                    Self.matchIpAddress(serverIP: serverIP, certificateIP: certificateIP)
                {
                    return .meetsPolicy
                }
            default:
                continue
            }
        }

        guard !checkedMatch else {
             
            return .failsToMeetPolicy(reason: "None of the names in SAN extension matched: \(subjectAlternativeNames)")
        }

         
         
         
         
         
         
        guard let commonName = self.subject.lastCommonName else {
             
            return .failsToMeetPolicy(reason: "No SAN extension and no common name")
        }

         
         
        guard let cn = String(commonName), Self.matchHostname(serverHostname: serverHostname, dnsName: cn) else {
            return .failsToMeetPolicy(reason: "Common name \(commonName) does not match expected hostname")
        }

        return .meetsPolicy
    }

    private static func matchHostname(
        serverHostname: ServerIdentityPolicy.PreparedServerHostname?,
        dnsName: String
    ) -> Bool {
        guard let serverHostname else {
             
            return false
        }

         
        guard let validatedHostname = AnalysedCertificateHostname(baseName: dnsName.utf8) else {
             
            return false
        }
        return validatedHostname.validMatchForName(serverHostname)
    }

    private static func matchIpAddress(
        serverIP: ServerIdentityPolicy.IPAddress,
        certificateIP: ServerIdentityPolicy.IPAddress
    ) -> Bool {
         
        switch (serverIP, certificateIP) {
        case (.v4(var addr1), .v4(var addr2)):
            return memcmp(&addr1, &addr2, MemoryLayout<in_addr>.size) == 0
        case (.v6(var addr1), .v6(var addr2)):
            return memcmp(&addr1, &addr2, MemoryLayout<in6_addr>.size) == 0
        default:
             
            return false
        }
    }
}

extension DistinguishedName {
     
    var lastCommonName: RelativeDistinguishedName.Attribute.Value? {
        for rdn in self.reversed() {
            for ava in rdn.reversed() {
                if ava.type == .RDNAttributeType.commonName {
                    return ava.value
                }
            }
        }

        return nil
    }
}

private let asciiIDNAIdentifier: ArraySlice<UInt8> = Array("xn--".utf8)[...]
private let asciiCapitals: ClosedRange<UInt8> = (UInt8(ascii: "A")...UInt8(ascii: "Z"))
private let asciiLowercase: ClosedRange<UInt8> = (UInt8(ascii: "a")...UInt8(ascii: "z"))
private let asciiNumbers: ClosedRange<UInt8> = (UInt8(ascii: "0")...UInt8(ascii: "9"))
private let asciiHyphen: UInt8 = UInt8(ascii: "-")
private let asciiPeriod: UInt8 = UInt8(ascii: ".")
private let asciiAsterisk: UInt8 = UInt8(ascii: "*")

extension Collection {
     
     
    fileprivate func splitAroundIndex(_ index: Index?) -> (SubSequence, SubSequence) {
        guard let index = index else {
            return (self[...], self[self.endIndex...])
        }

        let subsequentIndex = self.index(after: index)
        return (self[..<index], self[subsequentIndex...])
    }
}

extension Sequence<UInt8> {
    fileprivate func caseInsensitiveElementsEqual(_ other: some Sequence<UInt8>) -> Bool {
        self.elementsEqual(other) { $0.lowercased() == $1.lowercased() }
    }
}

extension UInt8 {
     
     
    fileprivate var isValidDNSCharacter: Bool {
        switch self {
        case asciiCapitals, asciiLowercase, asciiNumbers, asciiHyphen, asciiPeriod:
            return true
        default:
            return false
        }
    }

    fileprivate func lowercased() -> UInt8 {
        asciiCapitals.contains(self) ? self | 0x20 : self
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
private struct AnalysedCertificateHostname<
    BaseNameType: BidirectionalCollection
> where BaseNameType.Element == UInt8 {
    private var name: NameType

    fileprivate init?(baseName: BaseNameType) {
        var baseName = baseName[...]

         
        if baseName.last == .some(asciiPeriod) {
            baseName = baseName.dropLast()
        }

         
        var index = baseName.startIndex
        var firstPeriodIndex: BaseNameType.Index?
        var asteriskIndex: BaseNameType.Index?

        while index < baseName.endIndex {
            switch baseName[index] {
            case asciiPeriod where firstPeriodIndex == nil:
                 
                 
                firstPeriodIndex = index

            case asciiCapitals, asciiLowercase, asciiNumbers, asciiHyphen, asciiPeriod:
                 
                break

            case asciiAsterisk where asteriskIndex == nil && firstPeriodIndex == nil:
                 
                asteriskIndex = index

            case asciiAsterisk:
                 
                return nil

            default:
                 
                return nil
            }

            baseName.formIndex(after: &index)
        }

         
        if let asteriskIndex = asteriskIndex {
             
            if baseName.prefix(4).caseInsensitiveElementsEqual(asciiIDNAIdentifier) {
                return nil
            }

            self.name = .wildcard(baseName, asteriskIndex: asteriskIndex, firstPeriodIndex: firstPeriodIndex)
        } else {
            self.name = .singleName(baseName)
        }
    }

     
    fileprivate func validMatchForName(
        _ target: ServerIdentityPolicy.PreparedServerHostname
    ) -> Bool {
        switch self.name {
        case .singleName(let baseName):
             
            return baseName.caseInsensitiveElementsEqual(target.bytes)

        case .wildcard(let baseName, asteriskIndex: let asteriskIndex, firstPeriodIndex: let firstPeriodIndex):
             
             
             
             
             
             
             
             
             
             
            let (wildcardLabel, remainingComponents) = baseName.splitAroundIndex(firstPeriodIndex)
            let (targetFirstLabel, targetRemainingComponents) = target.bytes.splitAroundIndex(target.firstPeriodIndex)

            guard remainingComponents.caseInsensitiveElementsEqual(targetRemainingComponents) else {
                 
                return false
            }

            guard targetFirstLabel.count >= wildcardLabel.count else {
                 
                return false
            }

            let (wildcardLabelPrefix, wildcardLabelSuffix) = wildcardLabel.splitAroundIndex(asteriskIndex)
            let targetBeforeWildcard = targetFirstLabel.prefix(wildcardLabelPrefix.count)
            let targetAfterWildcard = targetFirstLabel.suffix(wildcardLabelSuffix.count)

            let leadingBytesMatch = targetBeforeWildcard.caseInsensitiveElementsEqual(wildcardLabelPrefix)
            let trailingBytesMatch = targetAfterWildcard.caseInsensitiveElementsEqual(wildcardLabelSuffix)

            return leadingBytesMatch && trailingBytesMatch
        }
    }
}

extension AnalysedCertificateHostname {
    private enum NameType {
        case wildcard(
            BaseNameType.SubSequence,
            asteriskIndex: BaseNameType.Index,
            firstPeriodIndex: BaseNameType.Index?
        )
        case singleName(BaseNameType.SubSequence)
    }
}
