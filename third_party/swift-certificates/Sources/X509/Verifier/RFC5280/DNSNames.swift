 
 
 
 
 
 
 
 
 
 
 
 
 

@usableFromInline
let ASCII_PERIOD = UInt8(ascii: ".")

@usableFromInline
let ASCII_ASTERISK = UInt8(ascii: "*")

@usableFromInline
let ASCII_HYPHEN = UInt8(ascii: "-")

@usableFromInline
let ASCII_LOWERCASE_A = UInt8(ascii: "a")

@usableFromInline
let ASCII_LOWERCASE_Z = UInt8(ascii: "z")

@usableFromInline
let ASCII_UPPERCASE_A = UInt8(ascii: "A")

@usableFromInline
let ASCII_UPPERCASE_Z = UInt8(ascii: "Z")

@usableFromInline
let ASCII_ZERO = UInt8(ascii: "0")

@usableFromInline
let ASCII_NINE = UInt8(ascii: "9")

@usableFromInline
let ASCII_UNDERSCORE = UInt8(ascii: "_")

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension NameConstraintsPolicy {
     
     
     
     
     
     
     
     
     
     
     
     
     
    @inlinable
    static func dnsNameMatchesConstraint(dnsName: String.UTF8View, constraint: String.UTF8View) -> Bool {
         
        guard dnsName.isValidDNSName(isConstraint: false) && constraint.isValidDNSName(isConstraint: true) else {
            return false
        }

         
         
         
        if constraint.count == 0 {
            return true
        }

         
        let dnsName = dnsName[...]
        var constraint = constraint[...]

         
        if constraint.last == ASCII_PERIOD {
            constraint = constraint.dropLast()
        }

         
        var reverseDNSNameLabels = ReverseDNSLabelSequence(dnsName).makeIterator()
        var reverseConstraintLabels = ReverseDNSLabelSequence(constraint).makeIterator()

         
         
         
         
         
        while true {
            let nextDNSNameLabel = reverseDNSNameLabels.next()
            let nextConstraintLabel = reverseConstraintLabels.next()

            switch (nextDNSNameLabel, nextConstraintLabel) {
            case (.none, .none):
                 
                return true
            case (.some, .none):
                 
                return true
            case (.none, .some):
                 
                 
                 
                return false
            case (.some(let dnsLabel), _) where dnsLabel.count == 0:
                 
                return false
            case (.some, .some(let constraintLabel)) where constraintLabel.count == 0:
                 
                guard reverseConstraintLabels.hasMoreLabels else {
                     
                    return true
                }
                 
                return false
            case (.some(let dnsLabel), .some(let constraintLabel))
            where dnsLabel.caseInsensitiveASCIIMatch(constraintLabel):
                 
                continue
            case (.some, .some):
                 
                return false
            }
        }
    }
}

extension String.UTF8View {
     
    @usableFromInline
    static let maximumLabelLength = 63

    @inlinable
    func isValidDNSName(isConstraint: Bool) -> Bool {
        var bytes = self[...]
        var labelCount = 0
        var isWildcard = false

         
        if bytes.count > 253 {
            return false
        }

         
         
        if bytes.first == ASCII_ASTERISK {
            bytes = bytes.dropFirst()
            guard let next = bytes.popFirst(), next == ASCII_PERIOD else {
                 
                return false
            }

            labelCount += 1
            isWildcard = true
        }

         
         
         
        while bytes.count > 0 {
            let label: String.UTF8View.SubSequence
            if let nextPeriod = bytes.firstIndex(of: ASCII_PERIOD) {
                label = bytes[..<nextPeriod]

                let indexAfterPeriod = bytes.index(after: nextPeriod)
                bytes = bytes[indexAfterPeriod...]
            } else {
                 
                label = bytes
                bytes = bytes[bytes.endIndex...]
            }

            labelCount += 1

             
            if label.count == 0 && !(labelCount == 1 && isConstraint) {
                return false
            }

             
            if label.first == ASCII_HYPHEN || label.last == ASCII_HYPHEN {
                return false
            }

             
            if label.count > Self.maximumLabelLength {
                return false
            }

             
             
             
             
             
             
            switch label.labelContents {
            case .allASCII(nonNumerics: let nonNumerics) where nonNumerics > 0:
                 
                continue
            case .allASCII where bytes.count > 0:
                 
                continue
            case .allASCII:
                 
                assert(bytes.count == 0)
                return false
            case .nonASCII:
                 
                return false
            }
        }

         
        if isWildcard && labelCount < 3 {
            return false
        }

         
        return true

    }
}

@usableFromInline
struct ReverseDNSLabelSequence: Sequence {
    @usableFromInline
    var base: String.UTF8View.SubSequence

    @inlinable
    init(_ base: String.UTF8View.SubSequence) {
        self.base = base
    }

    @inlinable
    func makeIterator() -> Iterator {
        return Iterator(self.base)
    }

    @usableFromInline
    struct Iterator: IteratorProtocol {
        @usableFromInline
        var base: String.UTF8View.SubSequence?

        @inlinable
        init(_ base: String.UTF8View.SubSequence) {
            self.base = base
        }

        @inlinable mutating func next() -> String.UTF8View.SubSequence? {
             
            guard let base = self.base else {
                return nil
            }

             
             
            guard let periodIndex = base.lastIndex(of: ASCII_PERIOD) else {
                 
                 
                let label = base
                self.base = nil
                return label
            }
             
             
            let labelStartIndex = base.index(after: periodIndex)
            let label = base[labelStartIndex...]
            self.base = base[..<periodIndex]
            return label
        }

        @inlinable var hasMoreLabels: Bool {
            return self.base != nil
        }
    }
}

extension String.UTF8View.SubSequence {
    @usableFromInline
    static let asciiCaseInsensitiveMask: UInt8 = ~(1 << 5)

    @inlinable
    func caseInsensitiveASCIIMatch(_ other: Self) -> Bool {
        guard self.count == other.count else {
            return false
        }

        return self.elementsEqual(
            other,
            by: { selfByte, otherByte in
                (selfByte & Self.asciiCaseInsensitiveMask) == (otherByte & Self.asciiCaseInsensitiveMask)
            }
        )
    }

    @usableFromInline
    enum LabelContents {
        case allASCII(nonNumerics: Int)
        case nonASCII
    }

    @inlinable
    var labelContents: LabelContents {
        var nonNumerics = 0

        for byte in self {
            switch byte {
            case ASCII_ZERO...ASCII_NINE:
                ()
            case ASCII_LOWERCASE_A...ASCII_LOWERCASE_Z,
                ASCII_UPPERCASE_A...ASCII_UPPERCASE_Z,
                ASCII_HYPHEN, ASCII_UNDERSCORE:
                nonNumerics += 1
            default:
                return .nonASCII
            }
        }

        return .allASCII(nonNumerics: nonNumerics)
    }
}
