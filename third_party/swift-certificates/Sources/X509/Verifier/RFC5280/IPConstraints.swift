 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension NameConstraintsPolicy {
     
     
     
     
     
     
     
     
    @inlinable
    static func ipAddressMatchesConstraint(ipAddress: ASN1OctetString, constraint: ASN1OctetString) -> Bool {
        switch (ipAddress.bytes.count, constraint.bytes.count) {
        case (4, 8):
             
            return addressIsInSubnet(address: ipAddress.bytes, subnet: constraint.bytes)
        case (16, 32):
             
            return addressIsInSubnet(address: ipAddress.bytes, subnet: constraint.bytes)
        default:
             
            return false
        }
    }
}

extension ArraySlice<UInt8> {
    @inlinable
    var isValidCIDRMask: Bool {
         
         
        if self.first == 0 {
            return false
        }

         
         
        guard let firstInterestingIndex = self.firstIndex(where: { $0 != 0xff }) else {
             
            return true
        }

        let byte = self[firstInterestingIndex]

         
        let leadingOneCount = (~byte).leadingZeroBitCount

         
        if (byte << leadingOneCount) != 0 {
            return false
        }

         
        let nextIndex = self.index(after: firstInterestingIndex)
        return self[nextIndex...].allSatisfy { $0 == 0 }
    }

    @inlinable
    subscript(offset offset: Int) -> UInt8 {
        return self[self.startIndex + offset]
    }
}

@inlinable
func addressIsInSubnet(address: ArraySlice<UInt8>, subnet: ArraySlice<UInt8>) -> Bool {
    assert(subnet.count == (address.count * 2))

    let base = subnet.prefix(subnet.count / 2)
    let mask = subnet.suffix(subnet.count / 2)

    guard mask.isValidCIDRMask else {
        return false
    }

    for offset in 0..<address.count {
        let maskByte = mask[offset: offset]
        if (address[offset: offset] & maskByte) != (base[offset: offset] & maskByte) {
            return false
        }
    }

    return true
}
