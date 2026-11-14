import Foundation
import ObjectiveC

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ClashMacExceptionRecorder {
     
    static let limit = 20
     
    static let frames = 12

    private static let lock = NSLock()
    nonisolated(unsafe) private static var previous: objc_exception_preprocessor?
    nonisolated(unsafe) private static var installed = false
    nonisolated(unsafe) private static var written: Set<String> = []
    nonisolated(unsafe) private static var write: (String) -> Void = writer(to: .shared)
     
     
     
    private static let writingKey = #"ClashMacExceptionRecorder.writing"#

     
     
     
     
    static func writer(to store: ClashLogStore) -> (String) -> Void {
        { line in store.appendDiagnostic(line, stream: .app, level: .error) }
    }

     
     
    static func install() {
        lock.lock()
        defer { lock.unlock() }
        guard !installed else { return }
        installed = true
         
         
         
        _ = write
         
         
         
        previous = objc_setExceptionPreprocessor { thrown in
            ClashMacExceptionRecorder.lock.lock()
            let previous = ClashMacExceptionRecorder.previous
            ClashMacExceptionRecorder.lock.unlock()
            let carried = previous.map { $0(thrown) } ?? thrown
            if let exception = carried as? NSException { ClashMacExceptionRecorder.record(exception) }
            return carried
        }
    }

     
     
    static func record(_ exception: NSException) {
        lock.lock()
        let full = written.count >= limit
        lock.unlock()
        guard !full else { return }
        let thread = Thread.current.threadDictionary
        guard thread[writingKey] == nil else { return }
        let name = exception.name.rawValue
        let reason = exception.reason
        let key = identity(name: name, reason: reason, addresses: exception.callStackReturnAddresses)
        lock.lock()
        guard written.count < limit, written.insert(key).inserted else {
            lock.unlock()
            return
        }
        let write = self.write
        lock.unlock()
         
         
        let text = line(name: name, reason: reason,
                        symbols: Array(throwSite(exception.callStackSymbols).prefix(frames)))
        thread[writingKey] = true
        defer { thread.removeObject(forKey: writingKey) }
        write(text)
    }

     
     
     
     
     
     
     
     
    static func identity(name: String, reason: String?, addresses: [NSNumber]) -> String {
        var key = String.UnicodeScalarView()
        let scalars = Array((reason ?? "").unicodeScalars)
        var index = 0
        while index < scalars.count {
            var end = index
            if scalars[index] == "0", index + 1 < scalars.count, scalars[index + 1] == "x" {
                end = index + 2
                while end < scalars.count, scalars[end].properties.isASCIIHexDigit { end += 1 }
                if end == index + 2 { end = index }
            }
            if end == index {
                while end < scalars.count, ("0"..."9").contains(scalars[end]) { end += 1 }
            }
            if end > index {
                key.append("#")
                index = end
            } else {
                key.append(scalars[index])
                index += 1
            }
        }
        let place = addresses.prefix(frames + 8).map { String($0.uintValue, radix: 16) }.joined(separator: ",")
        return name + "\u{1F}" + String(key) + "\u{1F}" + place
    }

     
     
     
     
    static func throwSite(_ symbols: [String]) -> ArraySlice<String> {
        guard let thrown = symbols.firstIndex(where: { $0.contains("objc_exception_throw") }) else { return symbols[...] }
        return symbols[(thrown + 1)...]
    }

     
     
     
     
     
    static func line(name: String, reason: String?, symbols: [String]) -> String {
        let said = reason ?? #"(no reason)"#
        var text = #"Objective-C exception thrown (it may still be caught): \#(name): \#(said)"#
        if !symbols.isEmpty {
            text += #" -- thrown at: "# + symbols.joined(separator: #" | "#)
        }
        return text.replacingOccurrences(of: "\r\n", with: #"\n"#)
            .replacingOccurrences(of: "\n", with: #"\n"#)
            .replacingOccurrences(of: "\r", with: #"\n"#)
    }


}
