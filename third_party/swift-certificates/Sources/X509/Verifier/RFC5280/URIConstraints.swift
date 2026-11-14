 
 
 
 
 
 
 
 
 
 
 
 
 

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if os(Windows)
import WinSDK
#elseif canImport(Glibc)
import Glibc
import CoreFoundation
#elseif canImport(Musl)
import Musl
import CoreFoundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
import CoreFoundation
#endif

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension NameConstraintsPolicy {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @inlinable
    static func uriNameMatchesConstraint(uriName: String, constraint: String) -> Bool {
         
         
        guard let parsed = URL(string: uriName), let host = parsed.host else {
            return false
        }

        if host.isIPAddress {
             
            return false
        }

         
        return Self.dnsNameMatchesConstraint(dnsName: host.utf8, constraint: constraint.utf8)

    }
}

extension String {
    @inlinable
    var isIPAddress: Bool {
        #if os(Windows)
        var v4: IN_ADDR = IN_ADDR()
        var v6: IN6_ADDR = IN6_ADDR()
        return self.withCString(encodedAs: UTF16.self) {
            return InetPtonW(AF_INET, $0, &v4) == 1 || InetPtonW(AF_INET6, $0, &v6) == 1
        }
        #else
         
        var ipv4Addr = in_addr()
        var ipv6Addr = in6_addr()
        return self.withCString { ptr in
            return inet_pton(AF_INET, ptr, &ipv4Addr) == 1 || inet_pton(AF_INET6, ptr, &ipv6Addr) == 1
        }
        #endif
    }
}
