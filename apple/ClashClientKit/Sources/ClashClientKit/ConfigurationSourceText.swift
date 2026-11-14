import Foundation

 
 
 
 
 
 
public final class ConfigurationSourceText: Sendable {
    public enum Failure: Error, Equatable {
         
        case tooLarge
    }

     
    public let byteCount: Int
    private let bytes: Data

    public init(contentsOf url: URL) throws {
        bytes = try Data(contentsOf: url, options: [.alwaysMapped])
        byteCount = bytes.count
        guard byteCount < Int(UInt32.max) else { throw Failure.tooLarge }
    }

     
     
    public func buildIndex(progress: ((Double) -> Void)? = nil) throws -> ConfigurationSourceIndex {
        try bytes.withUnsafeBytes { raw -> ConfigurationSourceIndex in
            let base = raw.bindMemory(to: UInt8.self)
            let count = base.count
            var starts: [UInt32] = [0]
            starts.reserveCapacity(count / 48 + 1)
            var outline = SectionScanner()
            var lineStart = 0
            var line = 0
            var longest = 0
            var widest = 0
            let step = max(count / 64, 1 << 20)
            var nextReport = step
            while true {
                let end = Self.newline(in: base, from: lineStart) ?? count
                outline.read(base, from: lineStart, to: end, line: line)
                let length = end > lineStart && base[end - 1] == 0x0D ? end - lineStart - 1 : end - lineStart
                longest = max(longest, length)
                widest = max(widest, length + Self.tabs(in: base, from: lineStart, to: lineStart + length)
                    * (SourceLineWidth.tabColumns - 1))
                guard end < count else { break }
                lineStart = end + 1
                line += 1
                starts.append(UInt32(lineStart))
                if lineStart >= nextReport {
                    nextReport += step
                    try Task.checkCancellation()
                    progress?(Double(lineStart) / Double(count))
                }
            }
            progress?(1)
            return ConfigurationSourceIndex(starts: starts, byteCount: count, sections: outline.finish(),
                                            longestLineBytes: longest, widestLineColumns: widest)
        }
    }

     
    public func line(_ number: Int, in index: ConfigurationSourceIndex) -> String {
        let range = index.byteRange(ofLine: number)
        guard !range.isEmpty else { return "" }
        return bytes.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: UInt8.self)
            var end = range.upperBound
            if end > range.lowerBound, base[end - 1] == 0x0D { end -= 1 }
            return String(decoding: UnsafeBufferPointer(rebasing: base[range.lowerBound..<end]), as: UTF8.self)
        }
    }

     
     
     
     
    public func search(_ query: String, in index: ConfigurationSourceIndex, batchSize: Int = 256,
                       onBatch: ([ConfigurationSourceMatch]) -> Void) throws {
        let needle = query.utf8.map(Self.folded)
        guard let first = needle.first else { return }
        try bytes.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: UInt8.self)
            let count = base.count
            guard count >= needle.count else { return }
            var batch: [ConfigurationSourceMatch] = []
            batch.reserveCapacity(batchSize)
            var line = 0
            let last = count - needle.count
            var position = 0
            var nextCheck = 1 << 22
            while position <= last {
                if position >= nextCheck {
                    nextCheck += 1 << 22
                    try Task.checkCancellation()
                }
                if Self.folded(base[position]) != first { position += 1; continue }
                var offset = 1
                while offset < needle.count, Self.folded(base[position + offset]) == needle[offset] { offset += 1 }
                guard offset == needle.count else { position += 1; continue }
                while line + 1 < index.lineCount, index.start(ofLine: line + 1) <= position { line += 1 }
                batch.append(ConfigurationSourceMatch(line: line, column: position - index.start(ofLine: line),
                                                      length: needle.count))
                position += needle.count
                if batch.count >= batchSize {
                    onBatch(batch)
                    batch.removeAll(keepingCapacity: true)
                    try Task.checkCancellation()
                }
            }
            if !batch.isEmpty { onBatch(batch) }
        }
    }

    private static func folded(_ byte: UInt8) -> UInt8 {
        (0x41...0x5A).contains(byte) ? byte | 0x20 : byte
    }

    private static func tabs(in base: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) -> Int {
        guard let origin = base.baseAddress else { return 0 }
        var found = 0
        var position = start
        while position < end, let tab = memchr(origin + position, 0x09, end - position) {
            found += 1
            position = origin.distance(to: tab.assumingMemoryBound(to: UInt8.self)) + 1
        }
        return found
    }

    private static func newline(in base: UnsafeBufferPointer<UInt8>, from start: Int) -> Int? {
        guard start < base.count, let origin = base.baseAddress else { return nil }
        guard let found = memchr(origin + start, 0x0A, base.count - start) else { return nil }
        return origin.distance(to: found.assumingMemoryBound(to: UInt8.self))
    }
}

 
public struct ConfigurationSourceIndex: Sendable {
    private let starts: [UInt32]
    private let byteCount: Int
     
    public let sections: [ConfigurationSourceSection]
     
     
    public let longestLineBytes: Int
     
    public let widestLineColumns: Int

    init(starts: [UInt32], byteCount: Int, sections: [ConfigurationSourceSection], longestLineBytes: Int,
         widestLineColumns: Int) {
        self.starts = starts
        self.byteCount = byteCount
        self.sections = sections
        self.longestLineBytes = longestLineBytes
        self.widestLineColumns = widestLineColumns
    }

     
     
    public var lineCount: Int { starts.count }

     
     
    public func line(containingByte offset: Int) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if Int(starts[middle]) <= offset { low = middle } else { high = middle - 1 }
        }
        return low
    }

    func start(ofLine line: Int) -> Int { Int(starts[line]) }

     
     
    func byteRange(ofLine line: Int) -> Range<Int> {
        guard line >= 0, line < starts.count else { return 0..<0 }
        let start = Int(starts[line])
        let end = line + 1 < starts.count ? Int(starts[line + 1]) - 1 : byteCount
        return start..<max(start, end)
    }
}

 
 
 
 
 
 
 
public enum SourceLineWidth {
     
     
    public static let tabColumns = 8

     
     
    @inlinable
    public static func columns(ofUTF16 unit: UInt16) -> Int {
        if unit == 0x09 { return tabColumns }
        if unit < 0x80 { return 1 }
        if unit < 0x800 || (0xD800...0xDFFF).contains(unit) { return 2 }
        return 3
    }

     
     
     
     
     
     
     
    public static func widestColumns(
        in source: NSString, range: NSRange, afterLineFeed: ((Int) -> Void)? = nil
    ) -> Int {
        var columns = 0
        var widest = 0
        for index in range.location..<NSMaxRange(range) {
            let unit = source.character(at: index)
            switch unit {
            case 0x0A:
                afterLineFeed?(index + 1)
                fallthrough
            case 0x0D, 0x2028, 0x2029:
                if columns > widest { widest = columns }
                columns = 0
            default:
                columns += Self.columns(ofUTF16: unit)
            }
        }
        return max(widest, columns)
    }

     
     
     
     
     
     
    public static let widestScrolledWidth: Double = 100_000

     
    public static let roomPastTheLine: Double = 128

     
     
     
     
    public static func documentWidth(columns: Int, columnWidth: Double, insets: Double) -> Double? {
        let wanted = Double(columns) * columnWidth + insets + roomPastTheLine
        return wanted > widestScrolledWidth ? nil : wanted.rounded(.up)
    }

     
     
     
     
     
     
     
     
     
    public static func nextDocumentWidth(
        current: Double, columns: Int, columnWidth: Double, insets: Double, exact: Bool
    ) -> Double? {
        guard let fitted = documentWidth(columns: columns, columnWidth: columnWidth, insets: insets) else { return nil }
        if exact || current == 0 { return fitted }
        if fitted - roomPastTheLine / 2 > current {
            return min(max(fitted, current * 1.5), widestScrolledWidth).rounded(.up)
        }
        return current
    }

     
     
     
     
    public static func linesToMeasure(in source: NSString, edited: NSRange) -> NSRange {
        let location = min(edited.location, source.length)
        return source.paragraphRange(for: NSRange(location: location, length: min(edited.length, source.length - location)))
    }

     
     
     
     
    public static func edited(_ earlier: NSRange?, then edit: NSRange, changeInLength delta: Int) -> NSRange {
        guard var range = earlier else { return edit }
        let replacedEnd = edit.location + edit.length - delta
        if replacedEnd <= range.location {
            range.location += delta
        } else if edit.location < NSMaxRange(range) {
             
            let start = min(range.location, edit.location)
            let end = max(NSMaxRange(range) + delta, NSMaxRange(edit))
            return NSRange(location: start, length: max(0, end - start))
        }
        return NSUnionRange(range, edit)
    }
}

 
 
public struct ConfigurationSourceSection: Equatable, Sendable {
    public let name: String
    public let line: Int
    public let items: Int

    public init(name: String, line: Int, items: Int) {
        self.name = name
        self.line = line
        self.items = items
    }
}

 
 
public struct ConfigurationSourceMatch: Equatable, Sendable {
    public let line: Int
    public let column: Int
    public let length: Int

    public init(line: Int, column: Int, length: Int) {
        self.line = line
        self.column = column
        self.length = length
    }

     
     
    public func utf16Range(in line: String) -> NSRange {
        let utf8 = line.utf8
        guard let start = utf8.index(utf8.startIndex, offsetBy: column, limitedBy: utf8.endIndex),
              let end = utf8.index(start, offsetBy: length, limitedBy: utf8.endIndex) else {
            return NSRange(location: NSNotFound, length: 0)
        }
        let location = start.utf16Offset(in: line)
        return NSRange(location: location, length: end.utf16Offset(in: line) - location)
    }
}

 
 
 
 
private struct SectionScanner {
    private var sections: [ConfigurationSourceSection] = []
    private var open: (name: String, line: Int, items: Int, itemIndent: Int?)?

    mutating func read(_ base: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int, line: Int) {
        var first = start
        while first < end, base[first] == 0x20 { first += 1 }
        guard first < end, base[first] != 0x23, base[first] != 0x0D else { return }
        let indent = first - start
        let isItem = base[first] == 0x2D && (first + 1 == end || base[first + 1] == 0x20 || base[first + 1] == 0x0D)
        if indent == 0, !isItem {
            close()
            if let name = Self.sectionKey(base, from: start, to: end) {
                open = (name, line, 0, nil)
            }
            return
        }
        guard var section = open else { return }
        if section.itemIndent == nil { section.itemIndent = isItem ? indent : -1 }
        if isItem, indent == section.itemIndent { section.items += 1 }
        open = section
    }

    mutating func finish() -> [ConfigurationSourceSection] {
        close()
        return sections
    }

    private mutating func close() {
        if let section = open { sections.append(ConfigurationSourceSection(name: section.name, line: section.line, items: section.items)) }
        open = nil
    }

     
    private static func sectionKey(_ base: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) -> String? {
        var keyStart = start
        var keyEnd: Int
        var cursor: Int
        let opening = base[start]
        if opening == 0x22 || opening == 0x27 {
            keyStart = start + 1
            keyEnd = keyStart
            while keyEnd < end, base[keyEnd] != opening { keyEnd += 1 }
            guard keyEnd < end else { return nil }
            cursor = keyEnd + 1
            guard cursor < end, base[cursor] == 0x3A else { return nil }
        } else {
            keyEnd = start
            while keyEnd < end {
                if base[keyEnd] == 0x3A, keyEnd + 1 == end || base[keyEnd + 1] == 0x20 || base[keyEnd + 1] == 0x0D { break }
                keyEnd += 1
            }
            guard keyEnd < end else { return nil }
            cursor = keyEnd
        }
        cursor += 1
        while cursor < end, base[cursor] == 0x20 || base[cursor] == 0x0D { cursor += 1 }
        guard cursor == end || base[cursor] == 0x23 else { return nil }
        var trimmedEnd = keyEnd
        while trimmedEnd > keyStart, base[trimmedEnd - 1] == 0x20 { trimmedEnd -= 1 }
        guard trimmedEnd > keyStart else { return nil }
        return String(decoding: UnsafeBufferPointer(rebasing: base[keyStart..<trimmedEnd]), as: UTF8.self)
    }
}
