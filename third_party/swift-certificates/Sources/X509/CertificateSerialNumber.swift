 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate {
     
     
     
     
     
     
     
    public struct SerialNumber {
         
        public var bytes: ArraySlice<UInt8>

         
         
        @inlinable
        public init(bytes: ArraySlice<UInt8>) {
            self.bytes = ArraySlice(normalisingToASN1IntegerForm: bytes)
        }

         
         
        @inlinable
        public init(bytes: [UInt8]) {
            self.bytes = ArraySlice(normalisingToASN1IntegerForm: bytes[...])
        }

         
         
        @inlinable
        public init<Bytes: Collection>(bytes: Bytes) where Bytes.Element == UInt8 {
            self.bytes = ArraySlice(normalisingToASN1IntegerForm: bytes)
        }

         
         
         
         
         
         
         
         
         
         
        @inlinable
        public init<Number: FixedWidthInteger>(_ number: Number) {
             
            self.bytes = ArraySlice(IntegerBytesCollection(number))
        }

         
         
         
         
        @inlinable
        public init() {
            var rng = SystemRandomNumberGenerator()
            self.init(generator: &rng)
        }

         
         
         
         
         
        @inlinable
        internal init(generator: inout some RandomNumberGenerator) {
             
            self.bytes = ArraySlice(normalisingToASN1IntegerForm: generator.bytes(count: 20))
        }
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.SerialNumber: Hashable {}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.SerialNumber: Sendable {}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate.SerialNumber: CustomStringConvertible {
    public var description: String {
        return self.bytes.lazy.map { String($0, radix: 16) }.joined(separator: ":")
    }
}

#if swift(>=5.8)
@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, macCatalyst 16.4, visionOS 1.0, *)
extension Certificate.SerialNumber: ExpressibleByIntegerLiteral {
     
     
     
    @inlinable
    public init(integerLiteral number: StaticBigInt) {
        var bytes = [UInt8]()
        let wordCount = (number.bitWidth - 1) / (MemoryLayout<UInt>.size * 8) + 1
        bytes.reserveCapacity(wordCount / MemoryLayout<UInt>.size)

        for wordIndex in (0..<wordCount).reversed() {
            bytes.appendBigEndianBytes(number[wordIndex])
        }

        self.bytes = ArraySlice(normalisingToASN1IntegerForm: bytes)
    }
}
#endif

extension [UInt8] {
    @inlinable
    mutating func appendBigEndianBytes(_ number: UInt) {
        let number = number.bigEndian

        for byte in 0..<(MemoryLayout<UInt>.size) {
            let shifted = number >> (byte * 8)
            self.append(UInt8(truncatingIfNeeded: shifted))
        }
    }
}
