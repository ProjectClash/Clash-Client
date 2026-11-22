import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashMemoryLedger: Equatable {
    struct Row: Equatable {
         
         
        let name: String
         
        let footprintBytes: Int64
         
        let deltaBytes: Int64
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        var peakBytes: Int64?

         
         
         
         
         
         
         
         
         
         
         
         
        var peakSpendBytes: Int64 {
            guard let peakBytes else { return deltaBytes }
            return max(peakBytes - (footprintBytes - deltaBytes), deltaBytes)
        }
    }

    let rows: [Row]

     
     
     
     
    static func lastRun(from lines: [String]) -> ClashMemoryLedger {
        var parsed = lines.compactMap(probe(of:))
        if let start = parsed.lastIndex(where: {
            $0.0 == "start-first-statement"
        }) {
            parsed = Array(parsed[start...])
        }
        var rows: [Row] = []
        for (index, probe) in parsed.enumerated() {
            rows.append(Row(
                name: probe.0,
                footprintBytes: probe.1,
                deltaBytes: index == 0 ? 0 : probe.1 - parsed[index - 1].1,
                peakBytes: probe.2
            ))
        }
        return ClashMemoryLedger(rows: rows)
    }

     
     
    static var phaseFile: URL? {
        ClashAppIdentifiers.appGroupContainer?
            .appendingPathComponent(MemorySampleLog.startupPhaseFileName)
    }

     
     
    static func lastRunOfPhaseFile() -> ClashMemoryLedger? {
        phaseFile.flatMap(lastRun(of:))
    }

     
    static func lastRun(of url: URL) -> ClashMemoryLedger? {
        lastRunLines(of: url).map(lastRun(from:))
    }

     
     
     
     
     
     
     
     
     
     
    static func lastRunLines(of url: URL) -> [String]? {
        lastRunRead(of: url)?.lines
    }

     
     
     
     
     
     
     
     
     
     
     
    static func lastRunRead(of url: URL, first: Int = 64 * 1024,
                            limit: Int = 1024 * 1024) -> (lines: [String], bytesRead: Int)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let lineBreak = UInt8(ascii: "\n")
        var bytesRead = 0
        var span = max(first, 1)
        while true {
            guard let size = try? handle.seekToEnd() else { return nil }
            let wanted = UInt64(min(span, limit))
            let whole = wanted >= size
             
            let offset = whole ? 0 : size - wanted - 1
            guard (try? handle.seek(toOffset: offset)) != nil,
                  var data = try? handle.readToEnd() else { return nil }
            bytesRead += data.count
            if !whole {
                let beginsALine = data.first == lineBreak
                data = data.dropFirst()
                if !beginsALine {
                    data = data.firstIndex(of: lineBreak).map { data[data.index(after: $0)...] } ?? Data()
                }
            }
            if let last = data.last, last != lineBreak {
                data = data.lastIndex(of: lineBreak).map { data[...$0] } ?? Data()
            }
            let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
            if let opening = lines.lastIndex(where: opensRun) {
                return (Array(lines[opening...]), bytesRead)
            }
            if whole || span >= limit { return (lines, bytesRead) }
            span *= 2
        }
    }

     
     
     
    private static func probe(of line: String) -> (String, Int64, Int64?)? {
         
        func mebibytes(after key: String, in line: String) -> Int64? {
            guard let range = line.range(of: key) else { return nil }
            let magnitude = line[range.upperBound...]
                .prefix { $0.isNumber || $0 == "." }
            guard let value = Double(magnitude) else { return nil }
            return Int64((value * 1_048_576).rounded())
        }
        guard let phaseRange = line.range(of: "go-phase="),
              let fpRange = line.range(of: "fp="),
              phaseRange.upperBound <= fpRange.lowerBound
        else { return nil }
         
         
         
         
        let name = line[phaseRange.upperBound..<fpRange.lowerBound]
            .trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty,
              let footprint = mebibytes(after: "fp=", in: line)
        else { return nil }
         
         
         
         
         
        return (name, footprint, mebibytes(after: "peak=", in: line))
    }

     
    private static func opensRun(_ line: String) -> Bool {
        probe(of: line)?.0 == "start-first-statement"
    }

     
     
     
     
     
    func unprobedRemainder(pressureFootprintBytes: Int64) -> Int64? {
        guard let last = rows.last else { return nil }
        let gap = pressureFootprintBytes - last.footprintBytes
        return gap > 0 ? gap : nil
    }
}
