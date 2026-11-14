import Clash
import CryptoKit
import Foundation

 
 
 
 
 
 
 
 
 
 
 
enum NodeLibraries {
     
     
    static func directory(container: URL) -> URL {
        container.appendingPathComponent("node-libraries", isDirectory: true)
    }

     
     
     
    static func storedConfigurationURLs(container: URL) -> [URL] {
         
        ((try? storedRevisions(container: container, strict: false)) ?? []).map(\.configuration)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

     
     
     
     
    struct IncompleteRead: Error, Equatable {
        let reason: String
    }

     
     
     
     
     
    static func storedConfigurationTexts(container: URL) throws -> [String] {
        let files = FileManager.default
        var texts: [String] = []
        for revision in try storedRevisions(container: container, strict: true) {
            guard files.fileExists(atPath: revision.configuration.path) else {
                if files.fileExists(atPath: revision.manifest.path) {
                    throw IncompleteRead(reason: "no text beside \(revision.manifest.path)")
                }
                continue
            }
            let text: String
            do {
                text = try String(contentsOf: revision.configuration, encoding: .utf8)
            } catch {
                throw IncompleteRead(reason: "\(revision.configuration.path): \(error.localizedDescription)")
            }
            if text.contains("x-clash-node-library"), ConfigTransforms.nodeLibraryPath(in: text) == nil {
                throw IncompleteRead(reason: "\(revision.configuration.path): library path unreadable")
            }
            if text.contains(ConfigTransforms.ruleIndexKey), ConfigTransforms.ruleIndexPath(in: text) == nil {
                throw IncompleteRead(reason: "\(revision.configuration.path): rule index path unreadable")
            }
            texts.append(text)
        }
        return texts
    }

     
     
     
    struct StoredReferences: Equatable {
        var libraries: Set<String> = []
        var seeds: Set<String> = []
         
         
         
        var libraryNames: Set<String> = []
        var ruleIndexes: Set<String> = []
         
         
        var ruleIndexNames: Set<String> = []
         
         
        var dashboards: Set<String> = []

         
        func keptLibraries(in directory: URL) -> Set<String> {
            libraries.union(libraryNames.map { directory.appendingPathComponent($0).path })
        }

         
        func keptRuleIndexes(in directory: URL) -> Set<String> {
            ruleIndexes.union(ruleIndexNames.map { directory.appendingPathComponent($0).path })
        }
    }

     
     
     
     
     
     
     
    static func storedReferences(container: URL, chunkBytes: Int = 1 << 20) throws -> StoredReferences {
        let files = FileManager.default
        var references = StoredReferences()
        for revision in try storedRevisions(container: container, strict: true) {
            guard files.fileExists(atPath: revision.configuration.path) else {
                if files.fileExists(atPath: revision.manifest.path) {
                    throw IncompleteRead(reason: "no text beside \(revision.manifest.path)")
                }
                continue
            }
            do {
                try scanReferences(in: revision.configuration, into: &references, chunkBytes: chunkBytes)
            } catch let incomplete as IncompleteRead {
                throw incomplete
            } catch {
                throw IncompleteRead(reason: "\(revision.configuration.path): \(error.localizedDescription)")
            }
        }
        return references
    }

     
     
     
    static func dashboardPath(_ rest: String) -> String? {
        var value = rest.trimmingCharacters(in: .whitespaces)
        if let quote = value.first, quote == "'" || quote == "\"" {
            guard let close = value.lastIndex(of: quote), close > value.startIndex else { return nil }
            value = String(value[...close])
        } else if let comment = value.range(of: #" #"#) {
            value = String(value[..<comment.lowerBound])
        }
        guard case .some(.some(let path)) = ConfigTransforms.nodeLibraryPathField(#"path: "# + value) else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == #"~"# || trimmed == #"null"# ? nil : trimmed
    }

     
     
     
     
     
     
     
    static func scanReferences(in file: URL, into references: inout StoredReferences, chunkBytes: Int = 1 << 20) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let seedMarker = Array(ProviderSeeds.referenceMarker.utf8)
        let dashboardOpener = Array(#"external-ui:"#.utf8)

         
         
         
        struct Reference {
            let key: String
            let bytes: [UInt8]
            var mentioned = false
            var inBlock = false
            var path: String?
            init(_ key: String) { self.key = key; self.bytes = Array(key.utf8) }
        }
        var tracked = [Reference(ConfigTransforms.nodeLibraryKey), Reference(ConfigTransforms.ruleIndexKey)]
        var pending: [UInt8] = []
        var pendingIsLineStart = true

        func contains(_ bytes: ArraySlice<UInt8>, _ needle: [UInt8]) -> Bool {
            guard bytes.count >= needle.count else { return false }
            var index = bytes.startIndex
            while index <= bytes.endIndex - needle.count {
                if bytes[index..<(index + needle.count)].elementsEqual(needle) { return true }
                index += 1
            }
            return false
        }
        func seeds(in bytes: ArraySlice<UInt8>) {
            guard bytes.count >= seedMarker.count + 64 else { return }
            var index = bytes.startIndex
            while index <= bytes.endIndex - seedMarker.count - 64 {
                if bytes[index..<(index + seedMarker.count)].elementsEqual(seedMarker) {
                    let hex = bytes[(index + seedMarker.count)..<(index + seedMarker.count + 64)]
                    if hex.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }) {
                        references.seeds.insert(String(decoding: hex, as: UTF8.self))
                    }
                }
                index += 1
            }
        }
        func line(_ bytes: ArraySlice<UInt8>, isLineStart: Bool, reference: inout Reference) {
            guard contains(bytes, reference.bytes) || reference.inBlock else { return }
            let text = String(decoding: bytes, as: UTF8.self)
            let opener = reference.key + ":"
            if isLineStart, text.hasPrefix(opener) {
                reference.mentioned = true
                reference.inBlock = text.dropFirst(opener.count)
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                return
            }
            if reference.inBlock {
                guard isLineStart, text.first == " " else {
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { reference.inBlock = false }
                    if contains(bytes, reference.bytes) { reference.mentioned = true }
                    return
                }
                let field = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path = ConfigTransforms.nodeLibraryPathField(field) {
                    if let path { reference.path = path }
                    reference.inBlock = false
                }
                return
            }
            reference.mentioned = true
        }
        func line(_ bytes: ArraySlice<UInt8>, isLineStart: Bool) {
            seeds(in: bytes)
            for index in tracked.indices { line(bytes, isLineStart: isLineStart, reference: &tracked[index]) }
            if isLineStart, bytes.starts(with: dashboardOpener),
               let path = dashboardPath(String(decoding: bytes.dropFirst(dashboardOpener.count), as: UTF8.self)) {
                references.dashboards.insert(path)
            }
        }

         
         
         
         
        var utf8 = UTF8Stream()
         
         
        while try autoreleasepool(invoking: { () throws -> Bool in
            guard let chunk = try handle.read(upToCount: chunkBytes), !chunk.isEmpty else { return false }
            if !utf8.feed(chunk) { throw IncompleteRead(reason: "\(file.path): not UTF-8") }
            var start = chunk.startIndex
            for index in chunk.indices where chunk[index] == 0x0A {
                pending.append(contentsOf: chunk[start..<index])
                line(pending[...], isLineStart: pendingIsLineStart)
                pending.removeAll(keepingCapacity: true)
                pendingIsLineStart = true
                start = index + 1
            }
            pending.append(contentsOf: chunk[start..<chunk.endIndex])
            if pending.count > chunkBytes {
                 
                 
                 
                seeds(in: pending[...])
                for index in tracked.indices where contains(pending[...], tracked[index].bytes) {
                    tracked[index].mentioned = true
                }
                let tail = max(seedMarker.count + 64, ConfigTransforms.nodeLibraryKey.utf8.count,
                               ConfigTransforms.ruleIndexKey.utf8.count)
                pending = Array(pending.suffix(tail))
                pendingIsLineStart = false
            }
            return true
        }) {}
        if !pending.isEmpty { line(pending[...], isLineStart: pendingIsLineStart) }
        if !utf8.isComplete { throw IncompleteRead(reason: "\(file.path): not UTF-8") }

         
         
        var whole: String?
        func wholeText() throws -> String {
            if let whole { return whole }
            let text = try String(contentsOf: file, encoding: .utf8)
            whole = text
            return text
        }
        let library = tracked[0], index = tracked[1]
        if let path = library.path {
            references.libraries.insert(path)
        } else if library.mentioned {
            let text = try wholeText()
            if let path = ConfigTransforms.nodeLibraryPath(in: text) {
                references.libraries.insert(path)
            } else {
                 
                 
                 
                 
                references.libraryNames.formUnion(libraryFileNames(in: text))
            }
        }
        if let path = index.path {
            references.ruleIndexes.insert(path)
        } else if index.mentioned {
            let text = try wholeText()
            if let path = ConfigTransforms.ruleIndexPath(in: text) {
                references.ruleIndexes.insert(path)
            } else {
                references.ruleIndexNames.formUnion(ruleIndexFileNames(in: text))
            }
        }
    }

     
    static func libraryFileNames(in text: String) -> Set<String> {
        fileNames(in: text, prefix: "nodes-", suffix: ".library")
    }

     
    static func ruleIndexFileNames(in text: String) -> Set<String> {
        fileNames(in: text, prefix: ruleIndexPrefix, suffix: ".index")
    }

     
     
    static let ruleIndexPrefix = "rules-"

    private static func fileNames(in text: String, prefix: String, suffix: String) -> Set<String> {
        var names: Set<String> = []
        var rest = text[...]
        while let start = rest.range(of: prefix) {
            let tail = rest[start.lowerBound...]
            let end = tail.firstIndex { $0.isWhitespace || "\"',]}#".contains($0) } ?? tail.endIndex
            let candidate = tail[..<end]
            if candidate.hasSuffix(suffix), !candidate.contains("/") { names.insert(String(candidate)) }
            rest = rest[start.upperBound...]
        }
        return names
    }

    private struct StoredRevision {
        let configuration: URL
        let manifest: URL
    }

     
     
     
    private static func storedRevisions(container: URL, strict: Bool) throws -> [StoredRevision] {
        let profiles = container.appendingPathComponent("working/store/profiles", isDirectory: true)
        let files = FileManager.default
        func list(_ directory: URL) throws -> [String] {
            var isDirectory: ObjCBool = false
            guard files.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return []
            }
            do {
                return try files.contentsOfDirectory(atPath: directory.path)
            } catch {
                guard strict else { return [] }
                throw IncompleteRead(reason: "\(directory.path): \(error.localizedDescription)")
            }
        }
        var stored: [StoredRevision] = []
        for id in try list(profiles) {
            let revisions = profiles.appendingPathComponent(id).appendingPathComponent("revisions", isDirectory: true)
            for revision in try list(revisions) {
                let directory = revisions.appendingPathComponent(revision, isDirectory: true)
                stored.append(StoredRevision(configuration: directory.appendingPathComponent("config.resolved.yaml"),
                                             manifest: directory.appendingPathComponent("manifest.json")))
            }
        }
        return stored
    }

     
    static func named(in texts: [String]) -> Set<String> {
        Set(texts.compactMap(ConfigTransforms.nodeLibraryPath(in:)))
    }

     
     
     
     
     
    static let unstoredGrace: TimeInterval = 10 * 60

     
     
    static let catalogLibraryLifetime: TimeInterval = 7 * 24 * 3600

     
     
     
     
     
     
    static func prunable(container: URL, now: Date = Date()) -> [URL] {
        prunable(container: container, now: now, references: Result { try storedReferences(container: container) })
    }

     
     
    static func prunable(container: URL, now: Date = Date(),
                         references read: Result<StoredReferences, Error>) -> [URL] {
        guard let references = try? read.get() else { return [] }
        let files = FileManager.default
        func modified(_ url: URL) -> Date {
            (try? files.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date ?? .distantPast
        }
         
         
        func lastUsed(_ url: URL) -> Date {
            max(modified(url), modified(url.appendingPathExtension(Self.proofExtension)))
        }
        var items: [URL] = []
        let libraries = directory(container: container)
        let kept = Set(references.keptLibraries(in: libraries).union(references.keptRuleIndexes(in: libraries))
            .map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path })
        for name in (try? files.contentsOfDirectory(atPath: libraries.path)) ?? []
        where Self.isLibraryOrIndex(name) {
            let url = libraries.appendingPathComponent(name)
            guard !kept.contains(url.resolvingSymlinksInPath().path) else { continue }
            let lifetime = name.hasPrefix("nodes-p") ? catalogLibraryLifetime : unstoredGrace
            if now.timeIntervalSince(lastUsed(url)) >= lifetime { items.append(url) }
        }
        let seeds = ProviderSeeds.directory(workingDirectory: container.appendingPathComponent("working", isDirectory: true))
        for name in (try? files.contentsOfDirectory(atPath: seeds.path)) ?? []
        where name.count == 64 && !references.seeds.contains(name) {
            let url = seeds.appendingPathComponent(name)
            if now.timeIntervalSince(modified(url)) >= ProviderSeeds.unnamedGrace { items.append(url) }
        }
        return items
    }

     
     
    static let proofExtension = "proof"

     
     
     
    static func isLibraryOrIndex(_ name: String) -> Bool {
        guard !name.hasSuffix("." + proofExtension), !name.contains(".clashsum-") else { return false }
        return name.hasPrefix("nodes-") || (name.hasPrefix(ruleIndexPrefix) && name.hasSuffix(".index"))
    }

     
     
     
    static func prune(container: URL) {
        prune(container: container, references: Result { try storedReferences(container: container) })
    }

     
    static func prune(container: URL, references read: Result<StoredReferences, Error>) {
        let libraries = directory(container: container)
        do {
            let references = try read.get()
             
             
            ProviderSeeds.prune(
                directory: ProviderSeeds.directory(workingDirectory: container.appendingPathComponent("working", isDirectory: true)),
                keepingNamed: references.seeds)
             
             
             
             
            try ConfigTransforms.pruneNodeLibraries(in: libraries, keepingAll: references.keptLibraries(in: libraries))
             
             
            try ConfigTransforms.pruneRuleIndexes(in: libraries, keepingAll: references.keptRuleIndexes(in: libraries))
        } catch let incomplete as IncompleteRead {
            ClashLogStore.shared.append("node libraries not pruned  reason=stored configuration unread: \(incomplete.reason)",
                                       stream: .app, level: .warning)
        } catch {
            ClashLogStore.shared.append("node libraries not pruned  reason=\(error.localizedDescription)",
                                       stream: .app, level: .warning)
        }
    }

     
     
     
     
    static func isUnavailable(_ message: String?) -> Bool {
        guard let message else { return false }
        return message.contains(ClashNodeLibraryUnavailablePrefix) || message.contains(ClashRuleIndexUnavailablePrefix)
    }

     
     
     
     
     
     
     
     
     
     
    static func storedConfiguration(sha256: String, container: URL,
                                    runsAs: (String, (String) -> Bool) -> String? = { _, _ in nil }) -> String? {
        let wanted = sha256.lowercased()
         
         
         
        var urls = storedConfigurationURLs(container: container)
        if let store = try? ConfigResourceStore(containerURL: container),
           let pointer = try? store.activeIdentity() {
            let active = container.appendingPathComponent(
                "working/store/profiles/\(pointer.profileID)/revisions/\(pointer.revision)/config.resolved.yaml")
            if let index = urls.firstIndex(where: { $0.standardizedFileURL == active.standardizedFileURL }) {
                urls.insert(urls.remove(at: index), at: 0)
            }
        }
        for url in urls {
             
             
             
             
             
             
            let text: String
            switch storedText(at: url, wanted: wanted) {
            case .matches(let stored): return stored
            case .other(let stored): text = stored
            case .unreadable: continue
            }
            if let running = runsAs(text, { sha256Hex(of: $0) == wanted }) { return running }
        }
        return nil
    }

    private enum StoredText {
         
        case matches(String?)
        case other(String)
        case unreadable
    }

     
     
    private static func storedText(at url: URL, wanted: String) -> StoredText {
        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        if hex(SHA256.hash(data: data)) == wanted { return .matches(String(data: data, encoding: .utf8)) }
        return String(data: data, encoding: .utf8).map(StoredText.other) ?? .unreadable
    }

     
    static func sha256Hex(of text: String) -> String {
        var text = text
        return hex(text.withUTF8 { SHA256.hash(data: UnsafeRawBufferPointer($0)) })
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

 
 
 
struct UTF8Stream {
    private var pending = 0

     
    mutating func feed<Bytes: Sequence>(_ bytes: Bytes) -> Bool where Bytes.Element == UInt8 {
        for byte in bytes {
            if pending > 0 {
                guard byte & 0xC0 == 0x80 else { return false }
                pending -= 1
                continue
            }
            switch byte {
            case 0x00...0x7F: continue
            case 0xC2...0xDF: pending = 1
            case 0xE0...0xEF: pending = 2
            case 0xF0...0xF4: pending = 3
            default: return false
            }
        }
        return true
    }

     
    var isComplete: Bool { pending == 0 }
}
