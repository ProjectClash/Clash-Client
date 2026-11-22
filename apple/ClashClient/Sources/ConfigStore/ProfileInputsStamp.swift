import CryptoKit
import Foundation

enum ProfileInputsStamp {
    static let fileName = "published-inputs.json"
    private static let schemaVersion = 1
    private static let storeDirectoryName = "store"

    private struct Record: Codable {
        let schemaVersion: Int
        let profileID: String
        let revision: String
        let inputs: String
    }

    private struct Inputs: Encodable {
        let appendRules: [String]
        let prependRules: Bool
        let legacyRuntimePatchJSON: String?
    }

    private static func url(workingDirectory: URL) -> URL {
        workingDirectory
            .appendingPathComponent(storeDirectoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private static func digest(of profile: Profile) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(Inputs(
            appendRules: profile.override.appendRules,
            prependRules: profile.override.prependRules,
            legacyRuntimePatchJSON: profile.legacyRuntimePatchJSON
        )) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func record(_ pointer: ActiveConfigurationPointer, profile: Profile, workingDirectory: URL) {
        let file = url(workingDirectory: workingDirectory)
        let record = Record(
            schemaVersion: schemaVersion,
            profileID: pointer.profileID,
            revision: pointer.revision,
            inputs: digest(of: profile)
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func read(workingDirectory: URL) -> Record? {
        guard let data = try? Data(contentsOf: url(workingDirectory: workingDirectory)) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    static func inputsChanged(_ pointer: ActiveConfigurationPointer, workingDirectory: URL) -> Bool {
        guard let profile = storedProfile(pointer.profileID, workingDirectory: workingDirectory) else {
            return false
        }
        guard let record = read(workingDirectory: workingDirectory) else { return true }
        return record.schemaVersion != schemaVersion
            || record.profileID != pointer.profileID
            || record.revision != pointer.revision
            || record.inputs != digest(of: profile)
    }

    private static func storedProfile(_ profileID: String, workingDirectory: URL) -> Profile? {
        let file = workingDirectory
            .appendingPathComponent(storeDirectoryName, isDirectory: true)
            .appendingPathComponent("profiles.json")
        return ProfileStore(fileURL: file).load().first { $0.id == profileID }
    }
}
