import Foundation

 
 
 
public struct BackupRecordSummary: Equatable, Sendable, Identifiable {
    public let installID: String
    public let sourceDevice: String?
    public let exportedAt: Date?
    public var id: String { installID }

    public init(installID: String, sourceDevice: String?, exportedAt: Date?) {
        self.installID = installID
        self.sourceDevice = sourceDevice
        self.exportedAt = exportedAt
    }
}

public enum BackupRecordSourceError: Error, Equatable {
     
    case noAccount
     
     
    case unavailable(String)
    case notFound(String)
}

 
 
 
 
public protocol BackupRecordSource: Sendable {
     
    func listBackups() async throws -> [BackupRecordSummary]
     
    func fetchArchive(installID: String) async throws -> Data
}

 
 
public struct DirectoryBackupRecordSource: BackupRecordSource {
     
     
    public static let autoFilePrefix = "Clash-backup-auto-"
     
    public static let legacyAutoFilePrefixes = ["Clash-backup-auto-"]
    static var readablePrefixes: [String] { [autoFilePrefix] + legacyAutoFilePrefixes }
    public static let fileSuffix = ".json"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func listBackups() async throws -> [BackupRecordSummary] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
         
         
        var newest: [String: BackupRecordSummary] = [:]
        for name in names where name.hasSuffix(Self.fileSuffix) {
            guard let prefix = Self.readablePrefixes.first(where: { name.hasPrefix($0) }) else { continue }
            let installID = String(name.dropFirst(prefix.count).dropLast(Self.fileSuffix.count))
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
                  let envelope = try? BackupEnvelope.decode(data) else { continue }
            let summary = BackupRecordSummary(installID: installID, sourceDevice: envelope.sourceDevice, exportedAt: envelope.exportedAt)
            if let held = newest[installID], (held.exportedAt ?? .distantPast).timeIntervalSince(summary.exportedAt ?? .distantPast) >= 0 { continue }
            newest[installID] = summary
        }
        return newest.values.sorted { ($0.exportedAt ?? .distantPast) > ($1.exportedAt ?? .distantPast) }
    }

     
    public func fetchArchive(installID: String) async throws -> Data {
        var best: (data: Data, at: Date)?
        for prefix in Self.readablePrefixes {
            let url = directory.appendingPathComponent(prefix + installID + Self.fileSuffix)
            guard let data = try? Data(contentsOf: url) else { continue }
            let at = (try? BackupEnvelope.decode(data))?.exportedAt ?? .distantPast
            if best == nil || at > best!.at { best = (data, at) }
        }
        guard let best else { throw BackupRecordSourceError.notFound(installID) }
        return best.data
    }
}
