 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1
 
 
 
 
 
 
 
 
 
 
 
 
 
@usableFromInline
enum DirectoryString: DERParseable, DERSerializable, Hashable {
    case teletexString(ASN1TeletexString)
    case printableString(ASN1PrintableString)
    case universalString(ASN1UniversalString)
    case utf8String(ASN1UTF8String)
    case bmpString(ASN1BMPString)

    @inlinable
    init(derEncoded rootNode: ASN1Node) throws {
        switch rootNode.identifier {
        case .teletexString:
            self = .teletexString(try ASN1TeletexString(derEncoded: rootNode))
        case .printableString:
            self = .printableString(try ASN1PrintableString(derEncoded: rootNode))
        case .universalString:
            self = .universalString(try ASN1UniversalString(derEncoded: rootNode))
        case .utf8String:
            self = .utf8String(try ASN1UTF8String(derEncoded: rootNode))
        case .bmpString:
            self = .bmpString(try ASN1BMPString(derEncoded: rootNode))
        default:
            throw ASN1Error.unexpectedFieldType(rootNode.identifier)
        }
    }

    @inlinable
    func serialize(into coder: inout DER.Serializer) throws {
        switch self {
        case .teletexString(let string):
            try string.serialize(into: &coder)
        case .printableString(let string):
            try string.serialize(into: &coder)
        case .universalString(let string):
            try string.serialize(into: &coder)
        case .utf8String(let string):
            try string.serialize(into: &coder)
        case .bmpString(let string):
            try string.serialize(into: &coder)
        }
    }
}
