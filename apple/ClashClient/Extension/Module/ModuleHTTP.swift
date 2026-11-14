#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 

enum ModuleHTTPVersion: String, Equatable, Sendable {
    case http10 = "HTTP/1.0"
    case http11 = "HTTP/1.1"
}

 
 
enum ModuleHTTPWhitespace {
    static let optional = CharacterSet(charactersIn: " \t")
}

struct ModuleHTTPField: Equatable, Sendable {
    var name: String
    var value: String
}

 
struct ModuleHTTPHeaders: Equatable, Sendable {
    var fields: [ModuleHTTPField]

    init(_ fields: [ModuleHTTPField] = []) {
        self.fields = fields
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }

    func values(_ name: String) -> [String] {
        fields.filter { Self.same($0.name, name) }.map(\.value)
    }

    func first(_ name: String) -> String? {
        fields.first { Self.same($0.name, name) }?.value
    }

    func contains(_ name: String) -> Bool {
        fields.contains { Self.same($0.name, name) }
    }

     
     
    func tokens(_ name: String) -> [String] {
        values(name).flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: ModuleHTTPWhitespace.optional).lowercased() }
            .filter { !$0.isEmpty }
    }

    mutating func add(_ name: String, _ value: String) {
        fields.append(ModuleHTTPField(name: name, value: value))
    }

    mutating func remove(_ name: String) {
        fields.removeAll { Self.same($0.name, name) }
    }

     
     
    mutating func set(_ name: String, _ value: String) {
        guard let index = fields.firstIndex(where: { Self.same($0.name, name) }) else { return add(name, value) }
        fields[index].value = value
        var position = index + 1
        while position < fields.count {
            if Self.same(fields[position].name, name) {
                fields.remove(at: position)
            } else {
                position += 1
            }
        }
    }
}

struct ModuleHTTPRequestHead: Equatable, Sendable {
    var method: String
     
    var target: String
    var version: ModuleHTTPVersion
    var headers: ModuleHTTPHeaders

     
    var keepsAlive: Bool {
        let connection = headers.tokens("Connection")
        if connection.contains("close") { return false }
        return version == .http11 || connection.contains("keep-alive")
    }

     
    var expectsContinue: Bool {
        version == .http11
            && headers.first("Expect")?.trimmingCharacters(in: ModuleHTTPWhitespace.optional).lowercased() == "100-continue"
    }

    var asksForUpgrade: Bool {
        headers.tokens("Connection").contains("upgrade") && headers.contains("Upgrade")
    }
}

struct ModuleHTTPResponseHead: Equatable, Sendable {
    var version: ModuleHTTPVersion
    var status: Int
    var reason: String
    var headers: ModuleHTTPHeaders

     
    var isInterim: Bool { (100..<200).contains(status) && status != 101 }

     
     
     
    mutating func dropContentLengthIfTransferEncoded() {
        if headers.contains("Transfer-Encoding") { headers.remove("Content-Length") }
    }

     
     
    mutating func writeFraming(_ framing: ModuleHTTPFraming) {
        headers.writeFraming(framing)
    }

    func keepsAlive(framing: ModuleHTTPFraming) -> Bool {
        if framing == .untilClose { return false }
         
         
        if version == .http10, headers.contains("Transfer-Encoding") { return false }
        let connection = headers.tokens("Connection")
        if connection.contains("close") { return false }
        return version == .http11 || connection.contains("keep-alive")
    }
}

extension ModuleHTTPRequestHead {
     
     
    mutating func writeFraming(_ framing: ModuleHTTPFraming) {
        headers.writeFraming(framing)
    }
}

extension ModuleHTTPHeaders {
     
     
     
     
     
     
     
     
    mutating func writeFraming(_ framing: ModuleHTTPFraming) {
        if contains("Transfer-Encoding") {
            let codings = tokens("Transfer-Encoding")
            remove("Content-Length")
            if codings.isEmpty { remove("Transfer-Encoding") } else { set("Transfer-Encoding", codings.joined(separator: ", ")) }
            return
        }
        switch framing {
        case .length(let count): set("Content-Length", String(count))
        case .none where contains("Content-Length"):
             
            if let value = try? ModuleHTTPFraming.contentLength(self) { set("Content-Length", String(value)) }
        case .none, .chunked, .untilClose: break
        }
    }
}

struct ModuleHTTPLimits: Equatable, Sendable {
    var maximumHeadBytes: Int
    var maximumStartLineBytes: Int
    var maximumFields: Int
    var maximumChunkLineBytes: Int

    static let request = ModuleHTTPLimits(maximumHeadBytes: 32 * 1024, maximumStartLineBytes: 8 * 1024,
                                           maximumFields: 128, maximumChunkLineBytes: 1024)
    static let response = ModuleHTTPLimits(maximumHeadBytes: 64 * 1024, maximumStartLineBytes: 8 * 1024,
                                            maximumFields: 256, maximumChunkLineBytes: 1024)
}

enum ModuleHTTPError: Error, Equatable, Sendable {
    case headTooLarge
    case startLineTooLong
    case tooManyFields
    case malformedStartLine
    case unsupportedVersion
    case malformedField
    case obsoleteLineFolding
    case conflictingContentLength
    case invalidContentLength
    case unsupportedTransferCoding
    case malformedChunk
    case chunkLineTooLong
    case truncatedBody
     
    case transferEncodingInHTTP10
     
    case unserializableField
     
    case multipleHosts

     
    var status: Int {
        switch self {
        case .headTooLarge, .tooManyFields: return 431
        case .startLineTooLong: return 414
        case .unsupportedVersion: return 505
        case .unsupportedTransferCoding: return 501
        case .unserializableField: return 502
        default: return 400
        }
    }
}

enum ModuleHTTPParse<Head: Equatable>: Equatable {
    case needMore
    case head(Head, consumed: Int)
}

 
 
 
 
struct ModuleHTTPHeadScan: Equatable, Sendable {
     
    fileprivate var begin: Int?
     
    fileprivate var index = 0
    fileprivate var lineStart = 0
    fileprivate var lines = 0
     
     
    private(set) var examined = 0

    init() {}

    fileprivate mutating func count(_ bytes: Int) { examined += bytes }
}

enum ModuleHTTPParser {
    static func request(_ data: Data, limits: ModuleHTTPLimits = .request) throws -> ModuleHTTPParse<ModuleHTTPRequestHead> {
        var scan = ModuleHTTPHeadScan()
        return try request(data, limits: limits, scan: &scan)
    }

    static func response(_ data: Data, limits: ModuleHTTPLimits = .response) throws -> ModuleHTTPParse<ModuleHTTPResponseHead> {
        var scan = ModuleHTTPHeadScan()
        return try response(data, limits: limits, scan: &scan)
    }

    static func request(_ data: Data, limits: ModuleHTTPLimits = .request,
                        scan: inout ModuleHTTPHeadScan) throws -> ModuleHTTPParse<ModuleHTTPRequestHead> {
        guard let (lines, consumed) = try headLines(data, limits: limits, scan: &scan) else {
            return .needMore
        }
        let parts = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty, parts[0].allSatisfy(isTokenCharacter), !parts[1].isEmpty,
              isValidTarget(parts[1]) else {
            throw ModuleHTTPError.malformedStartLine
        }
        guard let version = ModuleHTTPVersion(rawValue: String(parts[2])) else {
            throw parts[2].hasPrefix("HTTP/") ? ModuleHTTPError.unsupportedVersion : ModuleHTTPError.malformedStartLine
        }
        let head = ModuleHTTPRequestHead(method: String(parts[0]), target: String(parts[1]), version: version,
                                          headers: try fields(lines.dropFirst(), limits: limits))
         
         
        guard head.headers.values("Host").count <= 1 else { throw ModuleHTTPError.multipleHosts }
        return .head(head, consumed: consumed)
    }

     
     
     
    static func response(_ data: Data, limits: ModuleHTTPLimits = .response,
                         scan: inout ModuleHTTPHeadScan) throws -> ModuleHTTPParse<ModuleHTTPResponseHead> {
        guard let (lines, consumed) = try headLines(data, limits: limits, scan: &scan) else {
            return .needMore
        }
        let parts = lines[0].split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2, let version = ModuleHTTPVersion(rawValue: String(parts[0])) else {
            throw lines[0].hasPrefix("HTTP/") ? ModuleHTTPError.unsupportedVersion : ModuleHTTPError.malformedStartLine
        }
        guard parts[1].count == 3, parts[1].allSatisfy({ $0.isASCII && $0.isNumber }), let status = Int(parts[1]) else {
            throw ModuleHTTPError.malformedStartLine
        }
        let reason = parts.count == 3 ? String(parts[2]) : ""
        guard isValidFieldText(reason) else { throw ModuleHTTPError.malformedStartLine }
        let head = ModuleHTTPResponseHead(version: version, status: status, reason: reason,
                                           headers: try fields(lines.dropFirst(), limits: limits))
        return .head(head, consumed: consumed)
    }

     
     
    static func isValidTarget(_ target: Substring) -> Bool {
        target.unicodeScalars.allSatisfy { $0.value > 0x20 && $0.value != 0x7F }
    }

     
     
    static func isValidFieldText<S: StringProtocol>(_ text: S) -> Bool {
        text.unicodeScalars.allSatisfy { $0.value != 0x0D && $0.value != 0x0A && $0.value != 0 }
    }

     
     
    static let maximumMethodBytes = 32

     
     
     
     
     
     
     
     
     
     
    static func mayBeginWithAMethod(_ data: Data, scan: ModuleHTTPHeadScan) -> Bool {
        guard let begin = scan.begin else { return true }
        var method = 0
        for byte in data.dropFirst(begin) {
            if byte == 0x20 { return method > 0 }
            guard isTokenCharacter(Character(Unicode.Scalar(byte))) else { return false }
            method += 1
            guard method <= maximumMethodBytes else { return false }
        }
        return true
    }

     
     
     
     
     
    static func mayBeRequest(_ data: Data) -> Bool {
        let bytes = data.drop { $0 == 0x0D || $0 == 0x0A }
        var index = bytes.startIndex
        var method = 0
        while index < bytes.endIndex, bytes[index] != 0x20 {
            guard isTokenCharacter(Character(Unicode.Scalar(bytes[index]))) else { return false }
            method += 1
            guard method <= maximumMethodBytes else { return false }
            index += 1
        }
        guard index < bytes.endIndex else { return true }
        guard method > 0 else { return false }
        index += 1
        var target = 0
        while index < bytes.endIndex, bytes[index] != 0x20 {
            guard bytes[index] > 0x20, bytes[index] != 0x7F else { return false }
            target += 1
            index += 1
        }
        guard index < bytes.endIndex else { return true }
        guard target > 0 else { return false }
        index += 1
         
        let version = Array("HTTP/1.".utf8)
        for expected in version {
            guard index < bytes.endIndex else { return true }
            guard bytes[index] == expected else { return false }
            index += 1
        }
        guard index < bytes.endIndex else { return true }
        guard bytes[index] == 0x30 || bytes[index] == 0x31 else { return false }
        index += 1
        guard index < bytes.endIndex else { return true }
        if bytes[index] == 0x0D {
            index += 1
            guard index < bytes.endIndex else { return true }
        }
        return bytes[index] == 0x0A
    }

     
    static func isTokenCharacter(_ character: Character) -> Bool {
        guard let value = character.asciiValue else { return false }
        switch value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return true
        default: return "!#$%&'*+-.^_`|~".contains(character)
        }
    }

     
     
     
     
     
    private static func headLines(_ data: Data, limits: ModuleHTTPLimits,
                                  scan: inout ModuleHTTPHeadScan) throws -> ([String], Int)? {
        let base = data.startIndex
        var index = scan.index
        if scan.begin == nil {
            while index < data.count, data[base + index] == 0x0D || data[base + index] == 0x0A {
                index += 1
                if index > limits.maximumHeadBytes { throw ModuleHTTPError.headTooLarge }
            }
            scan.count(index - scan.index)
            guard index < data.count else {
                scan.index = index
                return nil
            }
            scan.begin = index
            scan.lineStart = index
        }
        let begin = scan.begin ?? 0
        let limit = min(data.count, begin + limits.maximumHeadBytes + 4)
        let from = index
        defer { scan.count(index - from) }
        while index < limit {
            if data[base + index] == 0x0A {
                var lineEnd = index
                if lineEnd > scan.lineStart, data[base + lineEnd - 1] == 0x0D { lineEnd -= 1 }
                if lineEnd == scan.lineStart {
                    guard scan.lines > 0 else { throw ModuleHTTPError.malformedStartLine }
                    let end = index + 1
                    scan.index = end
                    return (lines(of: data, from: begin, to: end, scan: &scan), end)
                }
                if scan.lines == 0, lineEnd - scan.lineStart > limits.maximumStartLineBytes {
                    throw ModuleHTTPError.startLineTooLong
                }
                guard scan.lines <= limits.maximumFields else { throw ModuleHTTPError.tooManyFields }
                scan.lines += 1
                scan.lineStart = index + 1
            }
            index += 1
        }
        scan.index = index
        if scan.lines == 0, index - scan.lineStart > limits.maximumStartLineBytes {
            throw ModuleHTTPError.startLineTooLong
        }
        if index - begin >= limits.maximumHeadBytes { throw ModuleHTTPError.headTooLarge }
        return nil
    }

     
    private static func lines(of data: Data, from begin: Int, to end: Int, scan: inout ModuleHTTPHeadScan) -> [String] {
        let bytes = [UInt8](data[(data.startIndex + begin)..<(data.startIndex + end)])
        scan.count(bytes.count)
        var lines: [String] = []
        var lineStart = 0
        for (index, byte) in bytes.enumerated() where byte == 0x0A {
            var lineEnd = index
            if lineEnd > lineStart, bytes[lineEnd - 1] == 0x0D { lineEnd -= 1 }
            if lineEnd == lineStart { break }
            lines.append(String(bytes: bytes[lineStart..<lineEnd], encoding: .isoLatin1) ?? "")
            lineStart = index + 1
        }
        return lines
    }

    private static func fields(_ lines: ArraySlice<String>, limits: ModuleHTTPLimits) throws -> ModuleHTTPHeaders {
        guard lines.count <= limits.maximumFields else { throw ModuleHTTPError.tooManyFields }
        var headers = ModuleHTTPHeaders()
        for line in lines {
            if line.first == " " || line.first == "\t" { throw ModuleHTTPError.obsoleteLineFolding }
            guard let colon = line.firstIndex(of: ":") else { throw ModuleHTTPError.malformedField }
            let name = line[..<colon]
             
            guard !name.isEmpty, name.allSatisfy(isTokenCharacter) else { throw ModuleHTTPError.malformedField }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: ModuleHTTPWhitespace.optional)
            guard isValidFieldText(value) else { throw ModuleHTTPError.malformedField }
            headers.add(String(name), value)
        }
        return headers
    }
}

 
enum ModuleHTTPFraming: Equatable, Sendable {
    case none
    case length(Int64)
    case chunked
    case untilClose

    static func ofRequest(_ head: ModuleHTTPRequestHead) throws -> ModuleHTTPFraming {
         
         
        if head.method == "CONNECT" { return .none }
         
         
        if head.headers.contains("Transfer-Encoding") {
             
            guard !head.headers.contains("Content-Length") else { throw ModuleHTTPError.conflictingContentLength }
             
            guard head.version == .http11 else { throw ModuleHTTPError.transferEncodingInHTTP10 }
            let codings = head.headers.tokens("Transfer-Encoding")
            guard !codings.isEmpty else { throw ModuleHTTPError.malformedField }
            guard codings == ["chunked"] else { throw ModuleHTTPError.unsupportedTransferCoding }
            return .chunked
        }
        guard let length = try contentLength(head.headers) else { return .none }
        return length == 0 ? .none : .length(length)
    }

    static func ofResponse(_ head: ModuleHTTPResponseHead, requestMethod: String) throws -> ModuleHTTPFraming {
        if requestMethod == "HEAD" || (100..<200).contains(head.status) || head.status == 204 || head.status == 304 {
            return .none
        }
         
        if requestMethod == "CONNECT", (200..<300).contains(head.status) { return .none }
        if head.headers.contains("Transfer-Encoding") {
            let codings = head.headers.tokens("Transfer-Encoding")
            guard !codings.isEmpty else { throw ModuleHTTPError.malformedField }
             
             
             
             
             
             
            return codings.last == "chunked" ? .chunked : .untilClose
        }
        guard let length = try contentLength(head.headers) else { return .untilClose }
        return length == 0 ? .none : .length(length)
    }

     
     
    static func contentLength(_ headers: ModuleHTTPHeaders) throws -> Int64? {
        let parts = headers.values("Content-Length")
            .flatMap { $0.split(separator: ",", omittingEmptySubsequences: false) }
            .map { $0.trimmingCharacters(in: ModuleHTTPWhitespace.optional) }
        guard let first = parts.first else { return nil }
        guard !first.isEmpty, first.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int64(first) else {
            throw ModuleHTTPError.invalidContentLength
        }
        guard parts.allSatisfy({ $0 == first }) else { throw ModuleHTTPError.conflictingContentLength }
        return value
    }
}

 
struct ModuleHTTPBodyReader: Sendable {
    private enum State: Equatable, Sendable {
        case length(Int64)
        case chunkSize([UInt8])
        case chunkData(Int64)
        case chunkDataEnd(sawCR: Bool)
         
         
        case trailer(total: Int, line: Int, sawCR: Bool)
        case untilClose
        case done
    }

    private var state: State
    private let limits: ModuleHTTPLimits

    init(_ framing: ModuleHTTPFraming, limits: ModuleHTTPLimits = .response) {
        switch framing {
        case .none: state = .done
        case .length(let count): state = .length(count)
        case .chunked: state = .chunkSize([])
        case .untilClose: state = .untilClose
        }
        self.limits = limits
    }

    var isComplete: Bool { state == .done }

     
     
    mutating func consume(_ data: Data) throws -> (raw: Int, payload: Data) {
        let bytes = [UInt8](data)
        var payload = Data()
        var index = 0
        reading: while index < bytes.count {
            switch state {
            case .done:
                break reading
            case .untilClose:
                payload.append(contentsOf: bytes[index...])
                index = bytes.count
            case .length(let remaining):
                let take = Int(min(Int64(bytes.count - index), remaining))
                payload.append(contentsOf: bytes[index..<(index + take)])
                index += take
                state = remaining == Int64(take) ? .done : .length(remaining - Int64(take))
            case .chunkSize(var line):
                let byte = bytes[index]
                index += 1
                if byte == 0x0A {
                     
                    guard line.last == 0x0D else { throw ModuleHTTPError.malformedChunk }
                    line.removeLast()
                    let size = try Self.chunkSize(line)
                    state = size == 0 ? .trailer(total: 0, line: 0, sawCR: false) : .chunkData(size)
                } else {
                    line.append(byte)
                    guard line.count <= limits.maximumChunkLineBytes else { throw ModuleHTTPError.chunkLineTooLong }
                    state = .chunkSize(line)
                }
            case .chunkData(let remaining):
                let take = Int(min(Int64(bytes.count - index), remaining))
                payload.append(contentsOf: bytes[index..<(index + take)])
                index += take
                state = remaining == Int64(take) ? .chunkDataEnd(sawCR: false) : .chunkData(remaining - Int64(take))
            case .chunkDataEnd(let sawCR):
                let byte = bytes[index]
                index += 1
                if !sawCR, byte == 0x0D {
                    state = .chunkDataEnd(sawCR: true)
                } else if sawCR, byte == 0x0A {
                    state = .chunkSize([])
                } else {
                    throw ModuleHTTPError.malformedChunk
                }
            case .trailer(let total, let line, let sawCR):
                let byte = bytes[index]
                index += 1
                guard total < limits.maximumHeadBytes else { throw ModuleHTTPError.headTooLarge }
                switch byte {
                case 0x0D:
                    guard !sawCR else { throw ModuleHTTPError.malformedChunk }
                    state = .trailer(total: total + 1, line: line, sawCR: true)
                case 0x0A:
                    guard sawCR else { throw ModuleHTTPError.malformedChunk }
                    state = line == 0 ? .done : .trailer(total: total + 1, line: 0, sawCR: false)
                default:
                    guard !sawCR, line < limits.maximumHeadBytes else { throw ModuleHTTPError.malformedChunk }
                    state = .trailer(total: total + 1, line: line + 1, sawCR: false)
                }
            }
        }
        return (index, payload)
    }

     
     
    mutating func endOfStream() throws {
        switch state {
        case .untilClose, .done: state = .done
        default: throw ModuleHTTPError.truncatedBody
        }
    }

     
     
    private static func chunkSize(_ line: [UInt8]) throws -> Int64 {
        var digits = 0
        var size: Int64 = 0
        for byte in line {
            let value: Int64
            switch byte {
            case 0x30...0x39: value = Int64(byte - 0x30)
            case 0x41...0x46: value = Int64(byte - 0x41 + 10)
            case 0x61...0x66: value = Int64(byte - 0x61 + 10)
            default: value = -1
            }
            if value < 0 { break }
            digits += 1
            guard digits <= 15 else { throw ModuleHTTPError.malformedChunk }
            size = size * 16 + value
        }
        guard digits > 0 else { throw ModuleHTTPError.malformedChunk }
        var rest = line[digits...]
        if rest.isEmpty { return size }
         
        while let first = rest.first, first == 0x20 || first == 0x09 { rest = rest.dropFirst() }
        guard rest.first == 0x3B, !rest.contains(0x0D), !rest.contains(0x00) else { throw ModuleHTTPError.malformedChunk }
        return size
    }
}

enum ModuleHTTPSerializer {
     
     
    static func head(_ head: ModuleHTTPRequestHead) throws -> Data {
        guard !head.method.isEmpty, head.method.allSatisfy(ModuleHTTPParser.isTokenCharacter),
              !head.target.isEmpty, ModuleHTTPParser.isValidTarget(head.target[...]) else {
            throw ModuleHTTPError.unserializableField
        }
        return try lines(["\(head.method) \(head.target) \(head.version.rawValue)"], head.headers)
    }

    static func head(_ head: ModuleHTTPResponseHead) throws -> Data {
        guard (100...999).contains(head.status), ModuleHTTPParser.isValidFieldText(head.reason) else {
            throw ModuleHTTPError.unserializableField
        }
        return try lines(["\(head.version.rawValue) \(head.status) \(head.reason)"], head.headers)
    }

     
    static func chunk(_ payload: Data) -> Data {
        guard !payload.isEmpty else { return Data() }
        return ModuleWire.join(Data(String(payload.count, radix: 16).utf8), Data([0x0D, 0x0A]), payload, Data([0x0D, 0x0A]))
    }

    static let lastChunk = Data([0x30, 0x0D, 0x0A, 0x0D, 0x0A])

     
     
    private static func lines(_ start: [String], _ headers: ModuleHTTPHeaders) throws -> Data {
        for field in headers.fields {
            guard !field.name.isEmpty, field.name.allSatisfy(ModuleHTTPParser.isTokenCharacter),
                  ModuleHTTPParser.isValidFieldText(field.value) else { throw ModuleHTTPError.unserializableField }
        }
        var out = Data()
        for line in start + headers.fields.map({ "\($0.name): \($0.value)" }) {
            out += line.data(using: .isoLatin1) ?? Data(line.utf8)
            out += Data([0x0D, 0x0A])
        }
        out += Data([0x0D, 0x0A])
        return out
    }
}
#endif
