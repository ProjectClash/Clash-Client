#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 

enum ModuleGateExtraction: Equatable, Sendable {
     
    case literals([[UInt8]])
     
    case ungated(String)
}

enum ModuleGateLiteral {
    static let minimumLength = 3
     
     
     
    static let maximumDepth = 100
     
    static let unreadFeatures = "uses regex features this engine does not read"
     
     
     
    static let backReferenceReason = "it uses a back-reference, which ICU can run for long stretches between "
        + "the progress reports its deadline is read on"
     
     
    static let quantifiedLookaround = "a quantified lookaround: held for the run and run on every URL"
    static let quantifiedLookaroundGroup = "a quantified group holding a lookaround: held for the run and run on every URL"
    private static let schemes = [Array("https://".utf8), Array("http://".utf8)]

     
    static func folded(_ text: String) -> [UInt8] {
        text.utf8.map { (0x41...0x5A).contains($0) ? $0 | 0x20 : $0 }
    }

     
    struct Analysis: Equatable, Sendable {
        var extraction: ModuleGateExtraction
         
         
         
        var leftOut: String?
         
        var caseInsensitive: Bool
    }

    static func extract(_ pattern: String) -> ModuleGateExtraction {
        analyze(pattern).extraction
    }

    static func leftOut(_ pattern: String) -> String? {
        analyze(pattern).leftOut
    }

    static func analyze(_ pattern: String) -> Analysis {
        let scalars = Array(pattern.unicodeScalars)
        if let feature = unreadFeature(scalars) {
            return Analysis(extraction: .ungated(feature), leftOut: "\(unreadFeatures) (\(feature))", caseInsensitive: false)
        }
        if usesBackReference(pattern) {
            return Analysis(extraction: .ungated("a back-reference"), leftOut: backReferenceReason, caseInsensitive: false)
        }
        let parser = Parser(scalars)
        func analysis(_ extraction: ModuleGateExtraction) -> Analysis {
            Analysis(extraction: extraction, leftOut: parser.hazard, caseInsensitive: parser.caseInsensitive)
        }
        func unread(_ why: String) -> Analysis {
             
             
            Analysis(extraction: .ungated(why), leftOut: "\(unreadFeatures) (\(why))", caseInsensitive: parser.caseInsensitive)
        }
        do {
            let branches = try parser.alternation(depth: 0)
            guard parser.atEnd else { return unread("an unbalanced parenthesis") }
            if let refusal = parser.gateRefusal { return analysis(.ungated(refusal)) }
            var chosen: [[UInt8]] = []
            for branch in branches {
                guard let best = best(branch.required, caseInsensitive: parser.caseInsensitive) else {
                    return analysis(.ungated(branches.count == 1 ? "no literal of three bytes outside the scheme" : "an alternative without a literal"))
                }
                chosen.append(best)
            }
            return analysis(.literals(chosen))
        } catch let refusal as Refusal {
            return unread(refusal.reason)
        } catch {
            return unread("\(error)")
        }
    }

     
     
     
     
     
    private static func unreadFeature(_ s: [Unicode.Scalar]) -> String? {
        var i = 0
        while i < s.count {
            if s[i] == "\\" {
                if i + 1 < s.count {
                    if s[i + 1] == "c" { return "\\c" }
                    if s[i + 1] == "Q" { return "\\Q…\\E" }
                }
                i += 2
                continue
            }
            if s[i] == "(", i + 1 < s.count, s[i + 1] == "?" {
                if i + 2 < s.count, s[i + 2] == "#" { return "a (?#…) comment" }
                var j = i + 2
                while j < s.count, s[j] == "-" || s[j].properties.isAlphabetic {
                    if s[j] == "x" { return "the x flag" }
                    j += 1
                }
            }
            i += 1
        }
        return nil
    }

     
     
     
     
    static func usesBackReference(_ pattern: String) -> Bool {
        let s = Array(pattern.unicodeScalars)
        var i = 0
        while i + 1 < s.count {
            guard s[i] == "\\" else {
                i += 1
                continue
            }
            let e = s[i + 1]
            let next: Unicode.Scalar? = i + 2 < s.count ? s[i + 2] : nil
            if ("1"..."9").contains(e) { return true }
            if e == "k", let next, "<{'".unicodeScalars.contains(next) { return true }
            if e == "g", let next, "<{'-".unicodeScalars.contains(next) || ("0"..."9").contains(next) { return true }
            i += 2
        }
        return false
    }

    private static func best(_ required: [[UInt8]], caseInsensitive: Bool) -> [UInt8]? {
        required.map { $0.map { (0x41...0x5A).contains($0) ? $0 | 0x20 : $0 } }
            .filter { literal in
                literal.count >= minimumLength
                    && !schemes.contains { scheme in contains(scheme, literal) }
                    && (!caseInsensitive || literal.allSatisfy { $0 < 0x80 })
            }
            .max { $0.count < $1.count }
    }

    private static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        return (0...(haystack.count - needle.count)).contains { start in
            haystack[start..<(start + needle.count)].elementsEqual(needle)
        }
    }

     
    private struct Refusal: Error {
        let reason: String
    }

     
    private struct Branch {
         
        var required: [[UInt8]] = []
         
        var nullable = true
         
        var looksAround = false
    }

     
    private struct Built {
        var branch = Branch()
        var run: [UInt8] = []

        mutating func flush() {
            if !run.isEmpty { branch.required.append(run) }
            run = []
        }

         
        mutating func add(_ bytes: [UInt8]?, _ repeated: Quantifier?) {
            if (repeated?.minimum ?? 1) >= 1 { branch.nullable = false }
            guard let bytes else { return flush() }
            switch repeated?.minimum {
            case nil:
                run += bytes
            case 0?:
                flush()
            default:
                run += bytes
                flush()
                run = bytes
            }
        }
    }

     
    private struct Quantifier {
        let minimum: Int
        let unbounded: Bool
        let lazy: Bool
    }

     
     
     
     
     
    private final class Parser {
        private let s: [Unicode.Scalar]
        private var i = 0
        private(set) var caseInsensitive = false
         
        private(set) var gateRefusal: String?
         
         
        private(set) var hazard: String?

        init(_ s: [Unicode.Scalar]) {
            self.s = s
        }

        var atEnd: Bool { i >= s.count }

        private func refuseGate(_ why: String) {
            if gateRefusal == nil { gateRefusal = why }
        }

        private func flagHazard(_ why: String) {
            if hazard == nil { hazard = why }
        }

        func alternation(depth: Int) throws -> [Branch] {
            guard depth <= ModuleGateLiteral.maximumDepth else {
                throw Refusal(reason: "groups nested deeper than \(ModuleGateLiteral.maximumDepth)")
            }
            var branches = [try sequence(depth)]
            while i < s.count, s[i] == "|" {
                i += 1
                branches.append(try sequence(depth))
            }
            return branches
        }

        private func has(_ text: String) -> Bool {
            let needle = Array(text.unicodeScalars)
            return i + needle.count <= s.count && Array(s[i..<(i + needle.count)]) == needle
        }

         
         
        private func quantifier() throws -> Quantifier? {
            guard i < s.count else { return nil }
            let minimum: Int
            let unbounded: Bool
            switch s[i] {
            case "?":
                (minimum, unbounded) = (0, false)
                i += 1
            case "*":
                (minimum, unbounded) = (0, true)
                i += 1
            case "+":
                (minimum, unbounded) = (1, true)
                i += 1
            case "{":
                guard let close = s[i...].firstIndex(of: "}") else { throw Refusal(reason: "an unclosed {") }
                let body = String(String.UnicodeScalarView(s[(i + 1)..<close]))
                let parts = body.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                guard let low = parts.first.flatMap({ Int($0) }),
                      parts.count == 1 || parts[1].isEmpty || Int(parts[1]) != nil else {
                    throw Refusal(reason: "a { that is not a count")
                }
                minimum = low
                unbounded = parts.count == 2 && parts[1].isEmpty
                i = close + 1
            default:
                return nil
            }
            var lazy = false
            if i < s.count, s[i] == "?" || s[i] == "+" {
                lazy = s[i] == "?"
                i += 1
            }
            return Quantifier(minimum: minimum, unbounded: unbounded, lazy: lazy)
        }

         
         
         
         
        private func skipClass() throws {
            var depth = 0
            func open() {
                i += 1
                depth += 1
                if i < s.count, s[i] == "^" { i += 1 }
                if i < s.count, s[i] == "]" { i += 1 }
            }
            open()
            while i < s.count, depth > 0 {
                switch s[i] {
                case "\\":
                     
                    if i + 1 < s.count, s[i + 1] == "c" || s[i + 1] == "Q" { throw Refusal(reason: "\\\(s[i + 1]) in a class") }
                    i += 2
                case "[":
                    refuseGate("a class holding a nested [")
                    open()
                case "]":
                    depth -= 1
                    i += 1
                default:
                    i += 1
                }
            }
            guard depth == 0 else { throw Refusal(reason: "an unclosed [") }
        }

         
        private func hex(_ most: Int) throws -> Unicode.Scalar {
            var end = i
            while end < s.count, end - i < most, s[end].properties.isASCIIHexDigit { end += 1 }
            guard end > i,
                  let value = UInt32(String(String.UnicodeScalarView(s[i..<end])), radix: 16),
                  let scalar = Unicode.Scalar(value) else { throw Refusal(reason: "a bad escape") }
            i = end
            return scalar
        }

         
         
         
         
        private func sequence(_ depth: Int) throws -> Branch {
            var built = Built()
            while i < s.count {
                let c = s[i]
                if c == "|" || c == ")" { break }
                switch c {
                case "\\":
                    try escape(&built)
                case ".":
                    i += 1
                    built.add(nil, try quantifier())
                case "^", "$":
                    i += 1
                    try zeroWidth(&built, "an anchor")
                case "[":
                    try skipClass()
                    built.add(nil, try quantifier())
                case "(":
                    try group(&built, depth)
                case "*", "+", "?", "{":
                    throw Refusal(reason: "a quantifier with nothing before it")
                default:
                    i += 1
                    built.add(Array(String(c).utf8), try quantifier())
                }
            }
            built.flush()
            return built.branch
        }

         
         
        private func zeroWidth(_ built: inout Built, _ what: String) throws {
            built.flush()
            if let repeated = try quantifier(), repeated.lazy, repeated.unbounded {
                flagHazard("ICU may never return on it: a lazy repeat of \(what), which can match nothing")
            }
        }

        private func literal(_ built: inout Built, _ scalar: Unicode.Scalar) throws {
            built.add(Array(String(scalar).utf8), try quantifier())
        }

         
        private func escape(_ built: inout Built) throws {
            guard i + 1 < s.count else { throw Refusal(reason: "a pattern ending in a backslash") }
            let e = s[i + 1]
            i += 2
            switch e {
            case "d", "D", "w", "W", "s", "S", "h", "H", "v", "V", "R", "X":
                built.add(nil, try quantifier())
            case "N", "p", "P":
                if i < s.count, s[i] == "{" {
                    guard let close = s[i...].firstIndex(of: "}") else { throw Refusal(reason: "an unclosed {") }
                    i = close + 1
                } else if e != "N" {
                    i += 1
                }
                built.add(nil, try quantifier())
            case "<", ">":
                 
                 
                built.add(nil, try quantifier())
            case "b", "B", "A", "z", "Z", "G":
                try zeroWidth(&built, "an anchor")
            case "x":
                if i < s.count, s[i] == "{" {
                    guard let close = s[i...].firstIndex(of: "}") else { throw Refusal(reason: "an unclosed {") }
                    i += 1
                    let scalar = try hex(close - i)
                    guard i == close else { throw Refusal(reason: "a bad escape") }
                    i = close + 1
                    try literal(&built, scalar)
                } else {
                     
                    try literal(&built, try hex(2))
                }
            case "u":
                let start = i
                let scalar = try hex(4)
                guard i - start == 4 else { throw Refusal(reason: "a bad escape") }
                try literal(&built, scalar)
            case "t": try literal(&built, "\t")
            case "n": try literal(&built, "\n")
            case "r": try literal(&built, "\r")
            case "f": try literal(&built, "\u{0C}")
            case "e": try literal(&built, "\u{1B}")
            case "a": try literal(&built, "\u{07}")
            case "0":
                 
                refuseGate("an octal escape")
                let start = i
                while i < s.count, i - start < 3, ("0"..."7").contains(s[i]) { i += 1 }
                built.add(nil, try quantifier())
            case "1"..."9":
                refuseGate("a back-reference")
                while i < s.count, ("0"..."9").contains(s[i]) { i += 1 }
                try zeroWidth(&built, "a back-reference")
            case "k":
                refuseGate("a back-reference")
                if i < s.count, s[i] == "<", let close = s[i...].firstIndex(of: ">") { i = close + 1 }
                try zeroWidth(&built, "a back-reference")
            default:
                 
                if e.properties.isAlphabetic { throw Refusal(reason: "the escape \\\(e)") }
                try literal(&built, e)
            }
        }

         
         
        private func group(_ built: inout Built, _ depth: Int) throws {
            i += 1
            var looksAround = false
            if has("?:") || has("?>") {
                i += 2
            } else if has("?=") || has("?!") {
                i += 2
                looksAround = true
            } else if has("?<=") || has("?<!") {
                i += 3
                looksAround = true
            } else if has("?<") {
                guard let close = s[(i + 2)...].firstIndex(of: ">") else { throw Refusal(reason: "an unclosed group name") }
                i = close + 1
            } else if has("?") {
                 
                if try flags() { return }
            }
            built.flush()
            let inner = try alternation(depth: depth + 1)
            guard i < s.count, s[i] == ")" else { throw Refusal(reason: "an unclosed group") }
            i += 1
            let repeated = try quantifier()
            let innerNullable = looksAround || inner.contains { $0.nullable }
            let innerLooksAround = looksAround || inner.contains { $0.looksAround }
            if let repeated {
                 
                 
                 
                 
                 
                 
                 
                 
                if repeated.lazy, repeated.unbounded, innerNullable {
                    flagHazard("ICU may never return on it: a lazy repeat of a group that can match nothing")
                } else if looksAround {
                    refuseGate(ModuleGateLiteral.quantifiedLookaround)
                } else if innerLooksAround {
                    refuseGate(ModuleGateLiteral.quantifiedLookaroundGroup)
                }
            }
            let required = (repeated?.minimum ?? 1) >= 1
            if !looksAround, inner.count == 1, required { built.branch.required += inner[0].required }
            if !looksAround, !innerNullable, required { built.branch.nullable = false }
            built.branch.looksAround = built.branch.looksAround || innerLooksAround
        }

         
         
         
        private func flags() throws -> Bool {
            i += 1
            var flags: [Unicode.Scalar] = []
            while i < s.count, s[i] != ":", s[i] != ")" {
                flags.append(s[i])
                i += 1
            }
            guard i < s.count, flags.allSatisfy({ "-imsw".unicodeScalars.contains($0) }) else {
                throw Refusal(reason: "an unknown group")
            }
            if flags.contains("i") { caseInsensitive = true }
            let closesHere = s[i] == ")"
            i += 1
            return closesHere
        }
    }
}

 
 
 
 
 
 
 
 
 
struct ModuleAhoCorasick: Sendable {
     
    private let label: [UInt8]
    private let fail: [Int32]
     
     
     
    private let hasChild: ModuleRankedBits
    private let branching: ModuleRankedBits
    private let branchStart: [Int32]
    private let branchBytes: [UInt8]
    private let branchTargets: [Int32]
     
     
    private let owns: ModuleRankedBits
    private let ownStart: [Int32]
    private let own: [Int32]
     
     
    private let linked: ModuleRankedBits
    private let outputTargets: [Int32]
    let needleCount: Int
     
    var nodeCount: Int { fail.count }

    init(_ needles: [[UInt8]]) {
        needleCount = needles.count
        let trie = Self.trie(needles)
        let nodes = trie.parent.count
        label = trie.label
         
        var children = [Int32](repeating: 0, count: nodes)
        for node in 1..<max(1, nodes) { children[Int(trie.parent[node])] += 1 }
        let hasChild = ModuleRankedBits(count: nodes) { children[$0] > 0 }
        let branching = ModuleRankedBits(count: nodes) { children[$0] > 1 }
        var branchStart: [Int32] = [0]
        branchStart.reserveCapacity(branching.setCount + 1)
        for node in 0..<nodes where children[node] > 1 { branchStart.append(branchStart[branchStart.count - 1] + children[node]) }
        children = []
        var branchBytes = [UInt8](repeating: 0, count: Int(branchStart[branchStart.count - 1]))
        var branchTargets = [Int32](repeating: 0, count: branchBytes.count)
        var filled = [Int32](repeating: 0, count: branching.setCount)
        for node in 1..<max(1, nodes) {
            let up = Int(trie.parent[node])
            guard branching.contains(up) else { continue }
            let r = branching.rank(up)
            let edge = Int(branchStart[r] + filled[r])
            branchBytes[edge] = trie.label[node]
            branchTargets[edge] = Int32(node)
            filled[r] += 1
        }
        filled = []
        self.hasChild = hasChild
        self.branching = branching
        self.branchStart = branchStart
        self.branchBytes = branchBytes
        self.branchTargets = branchTargets
         
        var counts = [Int32](repeating: 0, count: nodes)
        for end in trie.ends where end >= 0 { counts[Int(end)] += 1 }
        let owns = ModuleRankedBits(count: nodes) { counts[$0] > 0 }
        var ownStart: [Int32] = [0]
        ownStart.reserveCapacity(owns.setCount + 1)
        for node in 0..<nodes where counts[node] > 0 { ownStart.append(ownStart[ownStart.count - 1] + counts[node]) }
        counts = []
        var own = [Int32](repeating: 0, count: Int(ownStart[ownStart.count - 1]))
        var cursor = Array(ownStart.dropLast())
        for (needle, end) in trie.ends.enumerated() where end >= 0 {
            let r = owns.rank(Int(end))
            own[Int(cursor[r])] = Int32(needle)
            cursor[r] += 1
        }
        cursor = []
        self.owns = owns
        self.ownStart = ownStart
        self.own = own
         
        var fail = [Int32](repeating: 0, count: nodes)
        var outputLink = [Int32](repeating: -1, count: nodes)
        var queue: [Int32] = []
        queue.reserveCapacity(nodes)
        func eachChild(_ node: Int, _ body: (Int) -> Void) {
            guard hasChild.contains(node) else { return }
            guard branching.contains(node) else { return body(node + 1) }
            let r = branching.rank(node)
            for edge in Int(branchStart[r])..<Int(branchStart[r + 1]) { body(Int(branchTargets[edge])) }
        }
        eachChild(0) { queue.append(Int32($0)) }
        var head = 0
        while head < queue.count {
            let node = Int(queue[head])
            head += 1
            eachChild(node) { child in
                let byte = trie.label[child]
                var back = Int(fail[node])
                var target = 0
                while true {
                    if let next = Self.child(back, byte, label: trie.label, hasChild, branching, branchStart, branchBytes, branchTargets) {
                        target = next
                        break
                    }
                    if back == 0 { break }
                    back = Int(fail[back])
                }
                fail[child] = Int32(target)
                outputLink[child] = owns.contains(target) ? Int32(target) : outputLink[target]
                queue.append(Int32(child))
            }
        }
        queue = []
        let linked = ModuleRankedBits(count: nodes) { outputLink[$0] >= 0 }
        var outputTargets: [Int32] = []
        outputTargets.reserveCapacity(linked.setCount)
        for node in 0..<nodes where outputLink[node] >= 0 { outputTargets.append(outputLink[node]) }
        self.fail = fail
        self.linked = linked
        self.outputTargets = outputTargets
    }

     
     
     
     
     
    private static func trie(_ needles: [[UInt8]]) -> (parent: [Int32], label: [UInt8], ends: [Int32]) {
        let order = needles.indices.filter { !needles[$0].isEmpty }.sorted { needles[$0].lexicographicallyPrecedes(needles[$1]) }
        var parent: [Int32] = [0]
        var label: [UInt8] = [0]
        var ends = [Int32](repeating: -1, count: needles.count)
         
        var path: [Int32] = [0]
        var previous: [UInt8] = []
        for id in order {
            let needle = needles[id]
            var shared = 0
            let most = min(previous.count, needle.count)
            while shared < most, previous[shared] == needle[shared] { shared += 1 }
            path.removeSubrange((shared + 1)...)
            for depth in shared..<needle.count {
                parent.append(path[depth])
                label.append(needle[depth])
                path.append(Int32(parent.count - 1))
            }
            ends[id] = path[needle.count]
            previous = needle
        }
        return (ModuleRegexTable.exactly(parent), ModuleRegexTable.exactly(label), ends)
    }

    private static func child(_ node: Int, _ byte: UInt8, label: [UInt8], _ hasChild: ModuleRankedBits, _ branching: ModuleRankedBits,
                              _ branchStart: [Int32], _ branchBytes: [UInt8], _ branchTargets: [Int32]) -> Int? {
        guard hasChild.contains(node) else { return nil }
        guard branching.contains(node) else { return label[node + 1] == byte ? node + 1 : nil }
        let r = branching.rank(node)
        var low = Int(branchStart[r])
        var high = Int(branchStart[r + 1]) - 1
        while low <= high {
            let middle = (low + high) / 2
            let value = branchBytes[middle]
            if value == byte { return Int(branchTargets[middle]) }
            if value < byte { low = middle + 1 } else { high = middle - 1 }
        }
        return nil
    }

     
     
    func forEachMatch(in haystack: [UInt8], _ body: (Int) -> Void) {
        var node = 0
        for byte in haystack {
            while true {
                if let next = Self.child(node, byte, label: label, hasChild, branching, branchStart, branchBytes, branchTargets) {
                    node = next
                    break
                }
                if node == 0 { break }
                node = Int(fail[node])
            }
            var output = node
            while output >= 0 {
                if owns.contains(output) {
                    let r = owns.rank(output)
                    for index in Int(ownStart[r])..<Int(ownStart[r + 1]) { body(Int(own[index])) }
                }
                output = linked.contains(output) ? Int(outputTargets[linked.rank(output)]) : -1
            }
        }
    }
}

 
 
 
struct ModuleRankedBits: Sendable {
    private let words: [UInt64]
     
    private let before: [Int32]
    let setCount: Int

    init(count: Int, _ isSet: (Int) -> Bool) {
        var words = [UInt64](repeating: 0, count: (count + 63) >> 6)
        for index in 0..<count where isSet(index) { words[index >> 6] |= 1 << UInt64(index & 63) }
        var before = [Int32](repeating: 0, count: words.count)
        var total = 0
        for word in words.indices {
            before[word] = Int32(total)
            total += words[word].nonzeroBitCount
        }
        self.words = words
        self.before = before
        setCount = total
    }

    func contains(_ index: Int) -> Bool {
        words[index >> 6] & (1 << UInt64(index & 63)) != 0
    }

    func rank(_ index: Int) -> Int {
        Int(before[index >> 6]) + (words[index >> 6] & ((1 << UInt64(index & 63)) &- 1)).nonzeroBitCount
    }
}

 
struct ModuleCandidateSet: Equatable, Sendable {
    private(set) var words: [UInt64]

     
    init(capacity: Int) {
        words = [UInt64](repeating: 0, count: (capacity + 0x3f) >> 6)
    }

    mutating func insert(_ index: Int) {
        words[index >> 6] |= 1 << UInt64(index & 63)
    }

    mutating func remove(_ index: Int) {
        words[index >> 6] &= ~(1 << UInt64(index & 63))
    }

     
    mutating func formUnion(_ other: ModuleCandidateSet) {
        for word in words.indices { words[word] |= other.words[word] }
    }

     
    mutating func formIntersection(_ other: ModuleCandidateSet) {
        for word in words.indices { words[word] &= other.words[word] }
    }

    func contains(_ index: Int) -> Bool {
        words[index >> 6] & (1 << UInt64(index & 63)) != 0
    }

     
    func forEach(_ body: (Int) -> Bool) {
        for word in words.indices {
            var bits = words[word]
            while bits != 0 {
                if !body(word << 6 | bits.trailingZeroBitCount) { return }
                bits &= bits - 1
            }
        }
    }

     
    var count: Int { words.reduce(0) { $0 + $1.nonzeroBitCount } }

    var isEmpty: Bool { words.allSatisfy { $0 == 0 } }
}

struct ModuleGateMetrics: Equatable, Sendable {
    var rules = 0
    var patternBytes = 0
    var compileFailed = 0
    var gateLiterals = 0
    var gateBytes = 0
    var ungated = 0
     
     
    var regexTimeouts = 0
     
     
     
     
    var overBudget = 0
     
     
     
    var outputTooLarge = 0
}

 
 
 
 
 
final class ModuleProgramRoom {
     
    private(set) var left: Int64?
     
    private(set) var taken: Int64 = 0
     
     
     
     
     
    private let probe: (() -> Int64?)?
    private let keepClear: Int64
     
    private var chargedSinceAsked: Int64?
     
    private var stopped = false
     
    static let askEveryBytes: Int64 = 96 << 10

    init(_ bytes: Int64?, probe: (() -> Int64?)? = nil, keepClear: Int64 = ModuleLadderThresholds.iOS.relief) {
        left = bytes.map { max(0, $0) }
        self.probe = bytes == nil ? nil : probe
        self.keepClear = keepClear
    }

     
     
    func take(_ cost: Int64) -> Bool {
        let cost = max(0, cost)
         
         
        if cost == 0 { return true }
        if let left {
            guard !stopped, cost <= left else { return false }
            if let probe {
                let since = (chargedSinceAsked ?? Self.askEveryBytes) + cost
                if since >= Self.askEveryBytes {
                    chargedSinceAsked = 0
                    if let now = probe(), now <= keepClear {
                        stopped = true
                        self.left = 0
                        return false
                    }
                } else {
                    chargedSinceAsked = since
                }
            }
            self.left = left - cost
        }
        taken += cost
        return true
    }

     
    func give(_ cost: Int64) {
        let cost = max(0, min(cost, taken))
        taken -= cost
        if let left, !stopped { self.left = left + cost }
    }
}

 
 
 
 
 
 
final class ModuleRegexTable {
     
    enum Reading {
        case leftOut(String)
        case ungated
        case literals([[UInt8]], caseInsensitive: Bool)
    }

     
    struct CarriedKey: Hashable {
        let pattern: String
        let options: NSRegularExpression.Options.RawValue
    }

    let maximumPinned: Int
    let cacheCapacity: Int
     
     
    let room: ModuleProgramRoom
     
     
     
     
    private var patternText: [UInt8] = []
    private var patternEnds: [Int32] = []
     
     
     
    private enum Kept: UInt8 {
        case leftOut
        case ungated
        case gated
    }

     
     
    private var ids: [String: Int32] = [:]
    private var readings: [Kept] = []
    private var leftOutWhy: [Int32: String] = [:]
    private var pinned: [Int32: NSRegularExpression] = [:]
    private var pinUsers: [Int32: Int] = [:]
     
    private var gated = 0
    private var cache: [Int32: NSRegularExpression] = [:]
    private var recency: [Int32] = []
    private var carried: [CarriedKey: NSRegularExpression] = [:]

    init(maximumPinned: Int = ModuleGatedMatcher.maximumPinned, cacheCapacity: Int = 128,
         room: ModuleProgramRoom = ModuleProgramRoom(nil)) {
        self.maximumPinned = maximumPinned
        self.cacheCapacity = max(1, cacheCapacity)
        self.room = room
    }

     
     
    func read(_ pattern: String) -> (id: Int32, reading: Reading) {
        if let id = ids[pattern] {
            switch readings[Int(id)] {
            case .leftOut: return (id, .leftOut(leftOutWhy[id] ?? ""))
            case .ungated: return (id, .ungated)
            case .gated:
                let analysis = ModuleGateLiteral.analyze(pattern)
                guard case .literals(let found) = analysis.extraction else { return (id, .ungated) }
                return (id, .literals(found, caseInsensitive: analysis.caseInsensitive))
            }
        }
        let id = Int32(patternEnds.count)
        patternText.append(contentsOf: pattern.utf8)
        patternEnds.append(Int32(patternText.count))
        ids[pattern] = id
        let reading: Reading
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let analysis = ModuleGateLiteral.analyze(pattern)
            if let why = analysis.leftOut {
                reading = .leftOut(why)
            } else {
                switch analysis.extraction {
                case .ungated:
                    reading = .ungated
                    readings.append(.ungated)
                     
                     
                     
                     
                case .literals(let found):
                    reading = .literals(found, caseInsensitive: analysis.caseInsensitive)
                    readings.append(.gated)
                    gated += 1
                }
            }
        } catch {
            reading = .leftOut("it does not compile: \(error.localizedDescription)")
        }
        if case .leftOut(let why) = reading {
            readings.append(.leftOut)
            leftOutWhy[id] = why
        }
        return (id, reading)
    }

     
     
     
    func pin(_ id: Int32) -> Bool {
        if pinned[id] != nil {
            pinUsers[id, default: 0] += 1
            return true
        }
        guard pinned.count < maximumPinned, room.take(ModuleEngineBudget.chargedPerCompiledRegex) else { return false }
        guard let regex = try? NSRegularExpression(pattern: pattern(id)) else {
            room.give(ModuleEngineBudget.chargedPerCompiledRegex)
            return false
        }
        pinned[id] = regex
        pinUsers[id] = 1
        return true
    }

     
    func unpin(_ id: Int32) {
        guard let users = pinUsers[id] else { return }
        if users > 1 {
            pinUsers[id] = users - 1
        } else {
            pinUsers[id] = nil
            if pinned.removeValue(forKey: id) != nil { room.give(ModuleEngineBudget.chargedPerCompiledRegex) }
        }
    }

     
     
    func regex(_ id: Int32) -> NSRegularExpression? {
        guard id >= 0, Int(id) < patternEnds.count else { return nil }
        if let regex = pinned[id] { return regex }
        if let regex = cache[id] {
            if recency.last != id {
                recency.removeAll { $0 == id }
                recency.append(id)
            }
            return regex
        }
        let text = pattern(id)
        guard let regex = carried[CarriedKey(pattern: text, options: 0)] ?? (try? NSRegularExpression(pattern: text)) else { return nil }
        cache[id] = regex
        recency.append(id)
        if recency.count > cacheCapacity { cache[recency.removeFirst()] = nil }
        return regex
    }

     
    var patternCount: Int { patternEnds.count }

     
    private func span(_ id: Int32) -> Range<Int> {
        (id == 0 ? 0 : Int(patternEnds[Int(id) - 1]))..<Int(patternEnds[Int(id)])
    }

     
    func pattern(_ id: Int32) -> String {
        String(decoding: patternText[span(id)], as: UTF8.self)
    }

     
    func patternBytes(_ id: Int32) -> Int { span(id).count }

     
    var pinnedCount: Int { pinned.count }

     
    var cachedCount: Int { cache.count }

     
     
     
    func dropCache() {
        cache.removeAll()
        recency.removeAll()
    }

     
     
     
    var compiledAtMost: Int { pinned.count + min(gated, cacheCapacity) }

     
    func carries(_ key: CarriedKey) -> Bool { carried[key] != nil }

     
     
     
    func holdsPinned(_ key: CarriedKey) -> Bool {
        key.options == 0 && ids[key.pattern].map { pinned[$0] != nil } == true
    }

     
    var carriedCount: Int { carried.count }

     
     
    func carry(_ keys: [CarriedKey]) -> Result<[NSRegularExpression], Error> {
        var fresh: [CarriedKey: NSRegularExpression] = [:]
        var out: [NSRegularExpression] = []
        for key in keys {
            if let known = carried[key] ?? fresh[key] {
                out.append(known)
                continue
            }
            if key.options == 0, let id = ids[key.pattern], let regex = pinned[id] {
                fresh[key] = regex
                out.append(regex)
                continue
            }
            do {
                let regex = try NSRegularExpression(pattern: key.pattern, options: NSRegularExpression.Options(rawValue: key.options))
                fresh[key] = regex
                out.append(regex)
            } catch {
                return .failure(error)
            }
        }
        carried.merge(fresh) { old, _ in old }
        return .success(out)
    }

     
     
    func settle() {
         
        patternText = Self.exactly(patternText)
        patternEnds = Self.exactly(patternEnds)
        ids = [:]
        readings = []
        leftOutWhy = [:]
    }

     
    static func exactly<Element>(_ array: [Element]) -> [Element] {
        Array(unsafeUninitializedCapacity: array.count) { buffer, count in
            _ = buffer.initialize(from: array)
            count = array.count
        }
    }
}

 
 
 
 
 
 
final class ModuleGatedMatcher {
     
     
     
     
     
    static let evaluationDeadline: TimeInterval = 0.020
     
     
    static let timeoutsBeforeLeftOut = 3
     
     
     
     
     
     
     
     
    static let maximumPinned = Int.max
    static let overBudgetReason = "left out for memory: what was left as the rules were built holds no more regexes "
        + "of rules without a literal to gate them on"

    private(set) var metrics: ModuleGateMetrics
     
     
     
     
     
     
     
     
    private(set) var leftOut: [Int: String]
    var gateEnabled = true
    private(set) var regexExecutions = 0

     
    let table: ModuleRegexTable
    private let ids: [Int32]
     
    let pinnedPatterns: Set<Int32>
    private let automaton: ModuleAhoCorasick
     
     
     
    private let literalRules: [Int32]
    private let literalRuleEnds: [Int32]
    private let ungated: ModuleCandidateSet
    private var usable: ModuleCandidateSet
    private var timeouts: [Int: Int] = [:]
     
     
     
     
     
     
    private let caseInsensitive: ModuleCandidateSet

     
     
     
    init(patterns: [String], cacheCapacity: Int = 128, maximumPinned: Int = ModuleGatedMatcher.maximumPinned,
         table shared: ModuleRegexTable? = nil) {
        let table = shared ?? ModuleRegexTable(maximumPinned: maximumPinned, cacheCapacity: cacheCapacity)
        self.table = table
        var metrics = ModuleGateMetrics(rules: patterns.count, patternBytes: patterns.reduce(0) { $0 + $1.utf8.count })
        var leftOut: [Int: String] = [:]
        var literalIDs: [[UInt8]: Int] = [:]
        var literals: [[UInt8]] = []
        var rulesOfLiteral: [[Int32]] = []
        var ids: [Int32] = []
        ids.reserveCapacity(patterns.count)
        var ungated = ModuleCandidateSet(capacity: patterns.count)
        var usable = ModuleCandidateSet(capacity: patterns.count)
        var caseInsensitive = ModuleCandidateSet(capacity: patterns.count)
         
        var pinnedHere = Set<Int32>()
        for (rule, pattern) in patterns.enumerated() {
            let (id, reading) = table.read(pattern)
            ids.append(id)
            switch reading {
            case .leftOut(let why):
                metrics.compileFailed += 1
                leftOut[rule] = why
            case .ungated:
                guard table.pin(id) else {
                    metrics.overBudget += 1
                    leftOut[rule] = Self.overBudgetReason
                    continue
                }
                usable.insert(rule)
                if pinnedHere.insert(id).inserted { metrics.ungated += 1 }
                ungated.insert(rule)
            case .literals(let found, let folds):
                usable.insert(rule)
                if folds { caseInsensitive.insert(rule) }
                for literal in found {
                    let id: Int
                    if let known = literalIDs[literal] {
                        id = known
                    } else {
                        id = literals.count
                        literalIDs[literal] = id
                        literals.append(literal)
                        rulesOfLiteral.append([])
                    }
                    rulesOfLiteral[id].append(Int32(rule))
                }
            }
        }
        metrics.gateLiterals = literals.count
        metrics.gateBytes = literals.reduce(0) { $0 + $1.count }
        self.ids = ids
        self.pinnedPatterns = pinnedHere
        self.metrics = metrics
        self.leftOut = leftOut
        self.automaton = ModuleAhoCorasick(literals)
        var literalRules: [Int32] = []
        literalRules.reserveCapacity(rulesOfLiteral.reduce(0) { $0 + $1.count })
        var literalRuleEnds: [Int32] = []
        literalRuleEnds.reserveCapacity(rulesOfLiteral.count)
        for rules in rulesOfLiteral {
            literalRules.append(contentsOf: rules)
            literalRuleEnds.append(Int32(literalRules.count))
        }
        self.literalRules = literalRules
        self.literalRuleEnds = literalRuleEnds
        self.ungated = ungated
        self.usable = usable
        self.caseInsensitive = caseInsensitive
         
        if shared == nil { table.settle() }
    }

     
     
     
     
    var compiledAtMost: Int { table.compiledAtMost }

     
    var cachedRegexCount: Int { table.cachedCount }

     
     
    func patternID(_ rule: Int) -> Int32 { ids[rule] }

     
     
    func candidates(_ urls: [String]) -> ModuleCandidateSet {
        guard gateEnabled else { return usable }
        var set = ungated
        for url in urls {
            let bytes = ModuleGateLiteral.folded(url)
            automaton.forEachMatch(in: bytes) { literal in
                let start = literal == 0 ? 0 : Int(literalRuleEnds[literal - 1])
                for at in start..<Int(literalRuleEnds[literal]) { set.insert(Int(literalRules[at])) }
            }
            if bytes.contains(where: { $0 >= 0x80 }) { set.formUnion(caseInsensitive) }
        }
         
        set.formIntersection(usable)
        return set
    }

     
    func regex(_ rule: Int) -> NSRegularExpression? {
        guard rule >= 0, rule < ids.count, usable.contains(rule) else { return nil }
        return table.regex(ids[rule])
    }

     
     
     
     
    func firstMatch(_ urls: [String], budget: inout ModuleRequestBudget,
                    where accept: (Int) -> Bool) -> (rule: Int, url: String, match: NSTextCheckingResult)? {
        var found: (rule: Int, url: String, match: NSTextCheckingResult)?
        var spent = false
        candidates(urls).forEach { rule in
            guard accept(rule) else { return true }
            guard !spent else {
                budget.noteStop()
                return true
            }
            switch run(rule, on: urls, budget: &budget) {
            case .match(let url, let match):
                found = (rule, url, match)
                return false
            case .none:
                return true
            case .budgetSpent:
                spent = true
                return true
            }
        }
        return found
    }

    func allMatches(_ urls: [String], budget: inout ModuleRequestBudget,
                    where accept: (Int) -> Bool) -> [(rule: Int, url: String, match: NSTextCheckingResult)] {
        var found: [(rule: Int, url: String, match: NSTextCheckingResult)] = []
        var spent = false
        candidates(urls).forEach { rule in
            guard accept(rule) else { return true }
            guard !spent else {
                budget.noteStop()
                return true
            }
            switch run(rule, on: urls, budget: &budget) {
            case .match(let url, let match): found.append((rule, url, match))
            case .none: break
            case .budgetSpent: spent = true
            }
            return true
        }
        return found
    }

    typealias Match = (rule: Int, url: String, match: NSTextCheckingResult)

     
     
     
     
     
     
     
     
    func forEachMatch(_ urls: [String], budget: inout ModuleRequestBudget, where accept: (Int) -> Bool,
                      known: (Int) -> Match?? = { _ in nil }, _ body: (Match, inout ModuleRequestBudget) -> Bool,
                      miss: (Int) -> Void = { _ in }) {
        var spent = false
        candidates(urls).forEach { rule in
            guard accept(rule) else { return true }
            if let answer = known(rule) {
                guard let hit = answer else { return true }
                return body(hit, &budget)
            }
            guard !spent else {
                budget.noteStop()
                return true
            }
            switch run(rule, on: urls, budget: &budget) {
            case .match(let url, let match):
                return body((rule, url, match), &budget)
            case .none:
                miss(rule)
                return true
            case .budgetSpent:
                spent = true
                return true
            }
        }
    }

     
     
     
    func firstMatch(_ urls: [String], where accept: (Int) -> Bool) -> (rule: Int, url: String, match: NSTextCheckingResult)? {
        var budget = ModuleRequestBudget.unlimited
        return firstMatch(urls, budget: &budget, where: accept)
    }

    func allMatches(_ urls: [String], where accept: (Int) -> Bool) -> [(rule: Int, url: String, match: NSTextCheckingResult)] {
        var budget = ModuleRequestBudget.unlimited
        return allMatches(urls, budget: &budget, where: accept)
    }

    private enum Run {
        case match(String, NSTextCheckingResult)
        case none
         
         
        case budgetSpent
    }

     
    enum Evaluated {
        case match(Match)
         
        case none
         
        case budgetSpent
    }

     
     
     
     
    func evaluated(_ rule: Int, _ urls: [String], budget: inout ModuleRequestBudget) -> Evaluated {
        switch run(rule, on: urls, budget: &budget) {
        case .match(let url, let match): return .match((rule, url, match))
        case .none: return .none
        case .budgetSpent: return .budgetSpent
        }
    }

    private func run(_ rule: Int, on urls: [String], budget: inout ModuleRequestBudget) -> Run {
        guard let regex = regex(rule) else { return .none }
        for url in urls {
            guard !budget.isSpent else {
                budget.noteStop()
                return .budgetSpent
            }
             
            let allowed = min(Self.evaluationDeadline, budget.remainingSeconds)
            regexExecutions += 1
            let started = ModuleRequestBudget.threadNanoseconds()
            let evaluation = Self.evaluate(regex, on: url, deadline: allowed)
            budget.charge(ModuleRequestBudget.threadNanoseconds() &- started)
            switch evaluation {
            case .match(let match):
                return .match(url, match)
            case .noMatch:
                continue
            case .timedOut where allowed < Self.evaluationDeadline:
                budget.noteStop()
                return .budgetSpent
            case .timedOut:
                if timedOut(rule) { return .none }
            }
        }
        return .none
    }

     
    private func timedOut(_ rule: Int) -> Bool {
        metrics.regexTimeouts += 1
        timeouts[rule, default: 0] += 1
        guard timeouts[rule, default: 0] >= Self.timeoutsBeforeLeftOut else { return false }
        leaveOutForTheRun(rule, because: String(format: "it ran past %.0f ms of processing %d times: left out for the rest of the run",
                                                 Self.evaluationDeadline * 1_000, Self.timeoutsBeforeLeftOut))
        return true
    }

     
     
    private(set) var leftOutDuringRun: Set<Int> = []

     
     
    func leaveOutForTheRun(_ rule: Int, because reason: String) {
        guard rule >= 0, rule < ids.count else { return }
        leftOut[rule] = reason
        leftOutDuringRun.insert(rule)
         
         
        if usable.contains(rule), ungated.contains(rule) { table.unpin(ids[rule]) }
        usable.remove(rule)
    }

     
    func pattern(_ rule: Int) -> String? {
        rule >= 0 && rule < ids.count ? table.pattern(ids[rule]) : nil
    }

     
    func patternBytes(_ rule: Int) -> Int {
        rule >= 0 && rule < ids.count ? table.patternBytes(ids[rule]) : 0
    }

    enum Evaluation {
        case match(NSTextCheckingResult)
        case noMatch
         
        case timedOut
    }

     
     
     
     
    static func evaluate(_ regex: NSRegularExpression, on url: String,
                         deadline: TimeInterval = ModuleGatedMatcher.evaluationDeadline) -> Evaluation {
        var clock = ModuleRegexDeadline(deadline)
        var outcome = Evaluation.noMatch
        regex.enumerateMatches(in: url, options: [.reportProgress], range: NSRange(url.startIndex..., in: url)) { result, _, stop in
            if let result {
                outcome = .match(result)
                stop.pointee = true
                return
            }
            if clock.isPast() {
                outcome = .timedOut
                stop.pointee = true
            }
        }
        return outcome
    }
}
#endif
