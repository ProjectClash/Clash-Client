import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public enum ClashKernelRefusalHint {
     
     
     
     
     
     
     
     
     
     
     
    public static func nodeOrdinal(in sentence: String) -> Int? {
        var rest = sentence[...]
        while let range = rest.range(of: #"proxy "#) {
            defer { rest = rest[range.upperBound...] }
            if range.lowerBound > rest.startIndex {
                let before = rest[rest.index(before: range.lowerBound)]
                if before.isLetter || before == "-" || before == "_" { continue }
            }
            let digits = rest[range.upperBound...].prefix { $0.isASCII && $0.isNumber }
            guard !digits.isEmpty, rest[digits.endIndex...].first == ":",
                  let index = Int(digits), index < Int.max else { continue }
             
            return index + 1
        }
        return nil
    }

     
     
     
    public static func lines(for sentence: String, locale: Locale = .current) -> [String] {
         
         
         
         
         
         
         
         
        var lines: [String] = []
        if sentence.contains(#"invalid REALITY public key"#) {
            lines.append(ClashCopy.string(
                "REALITY's public key has to be base64url that decodes to exactly 32 bytes. Ask the provider for this node's key, or correct it in the node editor.",
                locale: locale
            ))
            lines.append(ClashCopy.string(
                "If the provider says to turn on post-quantum key exchange, that switch is in the node editor under More Fields → REALITY.",
                locale: locale
            ))
        }
        if let ordinal = nodeOrdinal(in: sentence) {
            lines.append(ClashCopy.format(
                "The core counts from zero, so this is node %@ in the configuration's proxy list.",
                locale: locale, String(ordinal)
            ))
        }
        return lines
    }
}
