import Foundation

struct SharedProfileFile: Equatable, Sendable {
    let data: Data
}

 
 
 
 
 
 
 
enum ImportedFileBytes {
    static func read(_ url: URL, fileManager: FileManager = .default) throws -> Data {
        let copy = fileManager.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString)-\(url.lastPathComponent)")
        do {
            try fileManager.copyItem(at: url, to: copy)
        } catch {
            return try Data(contentsOf: url)
        }
        defer { try? fileManager.removeItem(at: copy) }
        return try Data(contentsOf: copy, options: [.alwaysMapped])
    }
}

enum ProfileShareInboxError: LocalizedError, Equatable {
    case unavailable
    case empty
    case tooLarge(maximumBytes: Int)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Clash's shared import storage is unavailable."
        case .empty:
            return "The shared configuration is empty."
        case .tooLarge(let maximumBytes):
            return "The shared configuration exceeds the \(maximumBytes / 1_048_576) MB limit."
        }
    }
}

 
 
 
 
struct ProfileShareInbox {
     
     
     
     
     
     
     
     
    static let defaultMaximumBytes = 128 * 1_048_576

    private let inboxURL: URL
    private let maximumBytes: Int
    private let fileManager: FileManager

    init?(
        containerURL: URL? = ClashAppIdentifiers.appGroupContainer,
        maximumBytes: Int = defaultMaximumBytes,
        fileManager: FileManager = .default
    ) {
        guard let containerURL else { return nil }
        self.inboxURL = containerURL.appendingPathComponent("share-inbox", isDirectory: true)
        self.maximumBytes = maximumBytes
        self.fileManager = fileManager
    }

     
     
     
    func enqueue(fileAt url: URL) throws {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size > 0 else { throw ProfileShareInboxError.empty }
        guard size <= maximumBytes else { throw ProfileShareInboxError.tooLarge(maximumBytes: maximumBytes) }
        try fileManager.createDirectory(
            at: inboxURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let name = "\(UUID().uuidString.lowercased()).yaml"
         
         
        let partial = inboxURL.appendingPathComponent(".\(name).partial")
        try fileManager.copyItem(at: url, to: partial)
        try fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                      ofItemAtPath: partial.path)
        try fileManager.moveItem(at: partial, to: inboxURL.appendingPathComponent(name))
    }

    func enqueue(_ data: Data) throws {
        guard !data.isEmpty else { throw ProfileShareInboxError.empty }
        guard data.count <= maximumBytes else {
            throw ProfileShareInboxError.tooLarge(maximumBytes: maximumBytes)
        }
        try fileManager.createDirectory(
            at: inboxURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let destination = inboxURL.appendingPathComponent("\(UUID().uuidString.lowercased()).yaml")
        try data.write(
            to: destination,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

     
     
     
     
    @discardableResult
    func removePartialCopies(olderThan age: TimeInterval, now: Date = Date()) -> [URL] {
        let names = (try? fileManager.contentsOfDirectory(atPath: inboxURL.path)) ?? []
        var removed: [URL] = []
        for name in names where name.hasPrefix(".") && name.hasSuffix(".partial") {
            let url = inboxURL.appendingPathComponent(name)
             
             
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            guard let written = [values?.creationDate, values?.contentModificationDate].compactMap({ $0 }).max(),
                  now.timeIntervalSince(written) > age else { continue }
            if (try? fileManager.removeItem(at: url)) != nil { removed.append(url) }
        }
        return removed
    }

    func dequeueAll() throws -> [SharedProfileFile] {
        guard fileManager.fileExists(atPath: inboxURL.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var received: [SharedProfileFile] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where file.pathExtension.lowercased() == "yaml" {
             
            let data = try Data(contentsOf: file, options: [.alwaysMapped])
            try fileManager.removeItem(at: file)
            guard !data.isEmpty, data.count <= maximumBytes else { continue }
            received.append(SharedProfileFile(data: data))
        }
        return received
    }
}
