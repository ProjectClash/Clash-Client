 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

 
 
 
 
 
@usableFromInline
struct CMSVersion: RawRepresentable, Hashable, Sendable {
    @usableFromInline
    var rawValue: Int

    @inlinable
    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    @usableFromInline static let v0 = Self(rawValue: 0)
    @usableFromInline static let v1 = Self(rawValue: 1)
    @usableFromInline static let v2 = Self(rawValue: 2)
    @usableFromInline static let v3 = Self(rawValue: 3)
    @usableFromInline static let v4 = Self(rawValue: 4)
    @usableFromInline static let v5 = Self(rawValue: 5)
}

extension CMSVersion: CustomStringConvertible {
    @inlinable
    var description: String {
        "CMSv\(rawValue)"
    }
}
