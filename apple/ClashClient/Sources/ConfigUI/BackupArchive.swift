import Foundation
import ClashClientKit
#if canImport(UIKit)
import UIKit
#endif

enum BackupRestoreScope: String, CaseIterable, Identifiable {
    case profilesOnly
    case allData

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profilesOnly: return "Profiles only"
        case .allData: return "All data"
        }
    }
}

struct BackupRestoreResult: Equatable {
    let importedProfiles: Int
    let totalProfiles: Int
    let scope: BackupRestoreScope
    var registrationFailures: [String] = []
}

struct BackupRestorePreview: Equatable {
    struct Change: Equatable, Identifiable {
        enum Kind: String, Equatable {
            case added
            case updated
            case unchanged
            case removed

            var title: String { rawValue.capitalized }
        }

        let profileID: String
        let label: String
        let kind: Kind
        var id: String { "\(kind.rawValue):\(profileID)" }
    }

    let changes: [Change]
    let totalProfilesAfterRestore: Int
    let globalConfigChanges: Bool
    let referencedScriptCount: Int
    let omittedRemoteSourceCount: Int
     
     
     
     
    var rebindRequiredProviderCount: Int = 0

    var addedCount: Int { count(.added) }
    var updatedCount: Int { count(.updated) }
    var unchangedCount: Int { count(.unchanged) }
    var removedCount: Int { count(.removed) }

    private func count(_ kind: Change.Kind) -> Int {
        changes.filter { $0.kind == kind }.count
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct BackupArchive: Codable, Equatable {
    static let currentSchemaVersion = 6

     
     
    var configurationLibrary: ConfigurationLibraryArchive?
     
     
     
     
     
     
     
    var librarySourcesInSidecars: [LibrarySourceInSidecar]?

    struct LibrarySourceInSidecar: Codable, Equatable {
        let source: ConfigurationSourceVersion
        let profileID: String
    }
    var schemaVersion = BackupArchive.currentSchemaVersion
    var profiles: [Profile]
    var sidecars: [String: String]    
     
     
     
    var publicResources: [String: [String: Data]]
    var globalConfig: OverrideSpec
     
     
    var runtimeConfig: OverrideSpec?
     
     
     
     
    var configurationModelVersion: Int?
     
     
     
     
     
    var scripts: [ConfigScript]
     
     
     
    var scriptConfigurationModelVersion: Int?
     
     
     
     
    var omittedRemoteSourceCount: Int
     
     
     
     
     
    var effectiveSources: [String: String]?
     
    var effectiveStage: String?
     
    var activeProfileID: String?
     
    var sourceInstallID: String?
    var sourceDevice: String?
    var exportedAt: Date?
     
     
     
    var modules: ModuleBackupSection? = nil
     
     
     
    var modulesLeftOut: ModuleBackupSection.LeftOut? = nil

     
     
     
    var leftOutProfileLabels: [String] = []

     
     
     
     
     
    var sidecarFiles: [String: FileText] = [:]
    var effectiveSourceFiles: [String: FileText] = [:]

    static let effectiveStageAfterClientTransforms = "afterClientTransforms"
    static let autoInstallIDKey = "clash.backup.autoInstallID"

     
     
    static func autoInstallID(defaults: UserDefaults = GlobalConfig.appGroupDefaults) -> String {
        if let existing = defaults.string(forKey: autoInstallIDKey), UUID(uuidString: existing) != nil {
            return existing
        }
        let fresh = UUID().uuidString.lowercased()
        defaults.set(fresh, forKey: autoInstallIDKey)
        return fresh
    }

     
    static func localDeviceName() -> String {
        #if canImport(UIKit) && !os(watchOS)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }

    enum BackupError: Error, Equatable {
         
         
        case incompleteProfiles([String])
        case unsupportedSchema(Int)
        case unsupportedConfigurationModel(Int)
        case incompatibleConfigurationModel
        case conflictingConfigurationModel
        case configurationMigrationBlocked(LegacyGlobalConfigMigrationBlocker)
        case unsupportedScriptConfigurationModel(Int)
        case incompatibleScriptConfigurationModel
        case conflictingScriptConfigurationModel
        case missingReferencedScript
        case invalidScript
        case unsafeProfileID(String)
        case rollbackFailed
    }

    init(
        profiles: [Profile],
        sidecars: [String: String],
        publicResources: [String: [String: Data]] = [:],
        globalConfig: OverrideSpec,
        runtimeConfig: OverrideSpec? = nil,
        configurationModelVersion: Int? = nil,
        scripts: [ConfigScript] = [],
        scriptConfigurationModelVersion: Int? = nil,
        omittedRemoteSourceCount: Int = 0,
        effectiveSources: [String: String]? = nil,
        effectiveStage: String? = nil,
        activeProfileID: String? = nil,
        sourceInstallID: String? = nil,
        sourceDevice: String? = nil,
        exportedAt: Date? = nil,
        configurationLibrary: ConfigurationLibraryArchive? = nil
    ) {
        self.configurationLibrary = configurationLibrary
        self.profiles = profiles
        self.sidecars = sidecars
        self.publicResources = publicResources
        self.globalConfig = globalConfig
        self.runtimeConfig = runtimeConfig
        self.configurationModelVersion = configurationModelVersion
        self.scripts = scripts
        self.scriptConfigurationModelVersion = scriptConfigurationModelVersion
        self.omittedRemoteSourceCount = omittedRemoteSourceCount
        self.effectiveSources = effectiveSources
        self.effectiveStage = effectiveStage
        self.activeProfileID = activeProfileID
        self.sourceInstallID = sourceInstallID
        self.sourceDevice = sourceDevice
        self.exportedAt = exportedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case configurationLibrary
        case librarySourcesInSidecars
        case profiles
        case sidecars
        case publicResources
        case globalConfig
        case runtimeConfig
        case configurationModelVersion
        case scripts
        case scriptConfigurationModelVersion
        case omittedRemoteSourceCount
        case effectiveSources
        case effectiveStage
        case activeProfileID
        case sourceInstallID
        case sourceDevice
        case exportedAt
         
        case modules = "adBlock"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        configurationLibrary = try container.decodeIfPresent(ConfigurationLibraryArchive.self, forKey: .configurationLibrary)
        librarySourcesInSidecars = try container.decodeIfPresent([LibrarySourceInSidecar].self,
                                                                 forKey: .librarySourcesInSidecars)
        profiles = try container.decode([Profile].self, forKey: .profiles)
        sidecars = try container.decode([String: String].self, forKey: .sidecars)
        publicResources = try container.decodeIfPresent(
            [String: [String: Data]].self,
            forKey: .publicResources
        ) ?? [:]
        globalConfig = try container.decode(OverrideSpec.self, forKey: .globalConfig)
        runtimeConfig = try container.decodeIfPresent(
            OverrideSpec.self,
            forKey: .runtimeConfig
        )
        configurationModelVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .configurationModelVersion
        )
        scripts = try container.decodeIfPresent(
            [ConfigScript].self,
            forKey: .scripts
        ) ?? []
        scriptConfigurationModelVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .scriptConfigurationModelVersion
        )
        omittedRemoteSourceCount = try container.decodeIfPresent(
            Int.self,
            forKey: .omittedRemoteSourceCount
        ) ?? 0
        effectiveSources = try container.decodeIfPresent([String: String].self, forKey: .effectiveSources)
        effectiveStage = try container.decodeIfPresent(String.self, forKey: .effectiveStage)
        activeProfileID = try container.decodeIfPresent(String.self, forKey: .activeProfileID)
        sourceInstallID = try container.decodeIfPresent(String.self, forKey: .sourceInstallID)
        sourceDevice = try container.decodeIfPresent(String.self, forKey: .sourceDevice)
         
        if let seconds = try? container.decodeIfPresent(Date.self, forKey: .exportedAt) {
            exportedAt = seconds
        } else if let text = try container.decodeIfPresent(String.self, forKey: .exportedAt) {
            exportedAt = Self.iso8601.date(from: text) ?? Self.iso8601Fractional.date(from: text)
        } else {
            exportedAt = nil
        }
         
         
        if container.contains(.modules), (try? container.decodeNil(forKey: .modules)) != true {
            let read = try? container.decode(ModuleBackupSection.Lenient.self, forKey: .modules)
            modules = read?.section
            modulesLeftOut = read == nil ? ModuleBackupSection.LeftOut(names: [], reason: "section-unreadable") : read?.leftOut
        }
    }

    private static let iso8601 = ISO8601DateFormatter()
    private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        let portable = try sanitizedForPortableStorage()
        var standIns = LargeValues()
        let skeleton = try encoder.encode(standIns.leavingOut(portable))


        if standIns.isEmpty { return skeleton }
         
        return try standIns.writing(into: skeleton) ?? encoder.encode(portable.readWhole())
    }

     
    nonisolated(unsafe) static var writtenByHandFromBytes = 1 << 20



     
     
    static let writtenFilePrefix = "clash-backup-archive-"

     
     
     
     
     
     
    struct FileText: Equatable {
        enum Piece: Equatable {
            case text(String)
             
            case bytes(Range<Int>)
        }

         
        let file: Data
        let pieces: [Piece]

        init(file: Data, pieces: [Piece]) {
            self.file = file
            self.pieces = pieces
        }

         
         
         
         
         
         
         
         
         
         
        init?(mapping url: URL) {
            guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
            let start = data.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
            let valid = data.withUnsafeBytes { raw in
                Self.isUTF8(UnsafeBufferPointer(rebasing: raw.bindMemory(to: UInt8.self)[start...]))
            }
            guard valid else { return nil }
            self.init(file: data, pieces: [.bytes(start..<data.count)])
        }

         
        var range: Range<Int>? {
            guard pieces.count == 1, case .bytes(let range) = pieces[0] else { return nil }
            return range
        }

         
        func forEachPiece(_ body: (UnsafeBufferPointer<UInt8>) throws -> Void) rethrows {
            try file.withUnsafeBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                for piece in pieces {
                    switch piece {
                    case .bytes(let range): try body(UnsafeBufferPointer(rebasing: bytes[range]))
                    case .text(let text):
                        var text = text
                        try text.withUTF8 { try body($0) }
                    }
                }
            }
        }

         
         
         
        func string() -> String {
            let count = pieces.reduce(0) { total, piece in
                switch piece {
                case .bytes(let range): return total + range.count
                case .text(let text): return total + text.utf8.count
                }
            }
             
            return String(unsafeUninitializedCapacity: count) { buffer in
                var at = 0
                forEachPiece { piece in
                    guard let base = piece.baseAddress, let into = buffer.baseAddress else { return }
                    (into + at).update(from: base, count: piece.count)
                    at += piece.count
                }
                return at
            }
        }

         
        func hasBytes(of data: Data) -> Bool {
            guard let range, range.count == data.count else { return false }
            return file.withUnsafeBytes { mine in
                data.withUnsafeBytes { theirs in
                    range.isEmpty || memcmp(mine.baseAddress! + range.lowerBound, theirs.baseAddress!, range.count) == 0
                }
            }
        }

         
         
         
        @_optimize(speed)
        static func isUTF8(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
            guard let base = bytes.baseAddress else { return true }
            let count = bytes.count
            var index = 0
            while index < count {
                while index + 8 <= count,
                      UnsafeRawPointer(base + index).loadUnaligned(as: UInt64.self) & 0x8080_8080_8080_8080 == 0 {
                    index += 8
                }
                guard index < count else { break }
                let lead = base[index]
                if lead < 0x80 { index += 1; continue }
                func continuation(_ offset: Int) -> UInt8? {
                    guard index + offset < count, base[index + offset] & 0xC0 == 0x80 else { return nil }
                    return base[index + offset]
                }
                switch lead {
                case 0xC2...0xDF:
                    guard continuation(1) != nil else { return false }
                    index += 2
                case 0xE0...0xEF:
                    guard let second = continuation(1), continuation(2) != nil,
                          !(lead == 0xE0 && second < 0xA0), !(lead == 0xED && second >= 0xA0) else { return false }
                    index += 3
                case 0xF0...0xF4:
                    guard let second = continuation(1), continuation(2) != nil, continuation(3) != nil,
                          !(lead == 0xF0 && second < 0x90), !(lead == 0xF4 && second >= 0x90) else { return false }
                    index += 4
                default:
                    return false
                }
            }
            return true
        }
    }

     
     
     
    func readWhole() -> BackupArchive {
        guard !sidecarFiles.isEmpty || !effectiveSourceFiles.isEmpty else { return self }
        var copy = self
        for (id, text) in sidecarFiles { copy.sidecars[id] = text.string() }
        if !effectiveSourceFiles.isEmpty {
            var effective = copy.effectiveSources ?? [:]
            for (id, text) in effectiveSourceFiles { effective[id] = text.string() }
            copy.effectiveSources = effective
        }
        copy.sidecarFiles = [:]
        copy.effectiveSourceFiles = [:]
        return copy
    }

     
     
    private struct LargeValues {
        private enum Text {
            case string(String)
            case file(FileText)
        }

        private let marker = "@@clash-large-\(UUID().uuidString)-"
        private var texts: [(token: String, text: Text)] = []
        private var files: [(token: String, data: Data)] = []

        var isEmpty: Bool { texts.isEmpty && files.isEmpty }

        private mutating func stand(_ text: String) -> String {
            guard text.utf8.count >= BackupArchive.writtenByHandFromBytes else { return text }
            let token = marker + "t\(texts.count)@@"
            texts.append((token, .string(text)))
            return token
        }

         
        private mutating func stand(_ text: FileText) -> String {
            let token = marker + "t\(texts.count)@@"
            texts.append((token, .file(text)))
            return token
        }

        private mutating func stand(_ data: Data) -> Data {
            guard data.count >= BackupArchive.writtenByHandFromBytes else { return data }
            let token = marker + "b\(files.count)@@"
            files.append((token, data))
            return Data(token.utf8)
        }

         
        mutating func leavingOut(_ archive: BackupArchive) -> BackupArchive {
            var light = archive
            light.sidecars = archive.sidecars.mapValues { stand($0) }
            for (id, text) in archive.sidecarFiles { light.sidecars[id] = stand(text) }
            light.effectiveSources = archive.effectiveSources?.mapValues { stand($0) }
            if !archive.effectiveSourceFiles.isEmpty {
                var effective = light.effectiveSources ?? [:]
                for (id, text) in archive.effectiveSourceFiles { effective[id] = stand(text) }
                light.effectiveSources = effective
            }
            light.sidecarFiles = [:]
            light.effectiveSourceFiles = [:]
            if var library = archive.configurationLibrary {
                library.payloads = library.payloads.map { payload in
                    ConfigurationSourcePayload(record: payload.record, original: stand(payload.original),
                                               documentJSON: stand(payload.documentJSON), resourceFiles: payload.resourceFiles,
                                               ruleBaselineJSON: payload.ruleBaselineJSON.map { stand($0) })
                }
                light.configurationLibrary = library
            }
            return light
        }

         
         
         
        func writing(into skeleton: Data) throws -> Data? {
            var places: [(range: Range<Data.Index>, write: (ArchiveFile) throws -> Void)] = []
            for (token, text) in texts {
                guard let range = skeleton.range(of: Data(token.utf8)) else { return nil }
                places.append((range, { file in
                    switch text {
                    case .string(var string): try string.withUTF8 { try file.writeEscaped($0) }
                    case .file(let text): try text.forEachPiece { try file.writeEscaped($0) }
                    }
                }))
            }
            for (token, data) in files {
                 
                let base64 = Data(token.utf8).base64EncodedString()
                guard let range = skeleton.range(of: Data(base64.replacingOccurrences(of: "/", with: "\\/").utf8))
                        ?? skeleton.range(of: Data(base64.utf8)) else { return nil }
                places.append((range, { try $0.writeBase64(data) }))
            }
            places.sort { $0.range.lowerBound < $1.range.lowerBound }
            return try ArchiveFile.writing { file in
                var at = skeleton.startIndex
                for place in places {
                    try file.write(skeleton[at..<place.range.lowerBound])
                    try place.write(file)
                    at = place.range.upperBound
                }
                try file.write(skeleton[at...])
            }
        }
    }

     
     
     
     
     
    private final class ArchiveFile {
        private let descriptor: Int32
        private var buffer: [UInt8] = []
        private static let bufferBytes = 1 << 20

        private init(descriptor: Int32) {
            self.descriptor = descriptor
            buffer.reserveCapacity(Self.bufferBytes)
        }

        static func writing(_ body: (ArchiveFile) throws -> Void) throws -> Data {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(BackupArchive.writtenFilePrefix + UUID().uuidString + ".json")
            let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
             
            defer { _ = unlink(url.path) }
            do {
                let file = ArchiveFile(descriptor: descriptor)
                try body(file)
                try file.flush()
            } catch {
                Darwin.close(descriptor)
                throw error
            }
            guard Darwin.close(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            return try Data(contentsOf: url, options: .alwaysMapped)
        }

        func write(_ data: Data) throws {
            try data.withUnsafeBytes { try write(UnsafeBufferPointer(start: $0.bindMemory(to: UInt8.self).baseAddress, count: $0.count)) }
        }

        func write(_ bytes: UnsafeBufferPointer<UInt8>) throws {
            if buffer.count + bytes.count > Self.bufferBytes { try flush() }
            if bytes.count >= Self.bufferBytes {
                try writeOut(bytes)
            } else {
                buffer.append(contentsOf: bytes)
            }
        }

         
         
         
        @_optimize(speed)
        func writeEscaped(_ bytes: UnsafeBufferPointer<UInt8>) throws {
            guard let base = bytes.baseAddress else { return }
            let hex = Array("0123456789abcdef".utf8)
            var run = 0
            var index = 0
            while index < bytes.count {
                let byte = base[index]
                if byte >= 0x20, byte != UInt8(ascii: "\""), byte != UInt8(ascii: "\\") {
                    index += 1
                    continue
                }
                if index > run { try write(UnsafeBufferPointer(start: base + run, count: index - run)) }
                if buffer.count + 6 > Self.bufferBytes { try flush() }
                buffer.append(UInt8(ascii: "\\"))
                switch byte {
                case UInt8(ascii: "\""), UInt8(ascii: "\\"): buffer.append(byte)
                case 0x0A: buffer.append(UInt8(ascii: "n"))
                case 0x0D: buffer.append(UInt8(ascii: "r"))
                case 0x09: buffer.append(UInt8(ascii: "t"))
                default:
                    buffer.append(contentsOf: [UInt8(ascii: "u"), UInt8(ascii: "0"), UInt8(ascii: "0"),
                                               hex[Int(byte >> 4)], hex[Int(byte & 0x0F)]])
                }
                index += 1
                run = index
            }
            if bytes.count > run { try write(UnsafeBufferPointer(start: base + run, count: bytes.count - run)) }
        }

         
         
        func writeBase64(_ data: Data) throws {
            let piece = 3 << 20
            var start = data.startIndex
            while start < data.endIndex {
                let end = data.index(start, offsetBy: piece, limitedBy: data.endIndex) ?? data.endIndex
                try write(data[start..<end].base64EncodedData())
                start = end
            }
        }

        func flush() throws {
            guard !buffer.isEmpty else { return }
            try buffer.withUnsafeBufferPointer { try writeOut($0) }
            buffer.removeAll(keepingCapacity: true)
        }

        private func writeOut(_ bytes: UnsafeBufferPointer<UInt8>) throws {
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(descriptor, base + offset, bytes.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                offset += written
            }
        }
    }

    static func decode(_ data: Data) throws -> BackupArchive {
        let archive = try JSONDecoder().decode(BackupArchive.self, from: data)
        guard archive.schemaVersion <= currentSchemaVersion else {
            throw BackupError.unsupportedSchema(archive.schemaVersion)
        }
        return try archive.sanitizedForPortableStorage()
    }

    private static func configurationLibraryStore(workingDir: URL) -> ConfigurationLibraryStore {
        let directory = workingDir.appendingPathComponent("configuration-library")
        #if canImport(UIKit)
        return ConfigurationLibraryStore(directory: directory, beginAccess: ConfigStoreSuspensionShield.beginLibraryAccess)
        #else
        return ConfigurationLibraryStore(directory: directory)
        #endif
    }

     

    static func collect(
        workingDir: URL,
        defaults: UserDefaults = GlobalConfig.appGroupDefaults,
        credentials: CredentialStore = CredentialStore(),
        activeProfileID: String?? = nil,
        sourceInstallID: String? = nil,
        sourceDevice: String = BackupArchive.localDeviceName(),
        exportedAt: Date = Date(),
        leavingOutIncompleteProfiles: Bool = false
    ) throws -> BackupArchive {
        try ConfigurationCenterPublicationBridge.recoverReplacements(
            library: configurationLibraryStore(workingDir: workingDir), workingDir: workingDir)
        let profileStore = ProfileStore(
            fileURL: workingDir.appendingPathComponent("store/profiles.json"))
        var profiles = profileStore.load()
         
         
         
         
        var leftOut: [String] = []
        if leavingOutIncompleteProfiles {
            profiles.removeAll { profile in
                guard case .url = profile.source, isSafeProfileID(profile.id) else { return false }
                let sidecar = workingDir.appendingPathComponent("store/\(profile.id)/source.yaml")
                guard !FileManager.default.fileExists(atPath: sidecar.path) else { return false }
                leftOut.append(profile.label)
                return true
            }
        }
        var sidecars: [String: String] = [:]
        var sidecarFiles: [String: FileText] = [:]
        var publicResources: [String: [String: Data]] = [:]
        var incomplete: [String] = []
        for index in profiles.indices where isSafeProfileID(profiles[index].id) {
            let profile = profiles[index]
            let sidecar = workingDir.appendingPathComponent("store/\(profile.id)/source.yaml")
             
             
             
            let mapped = ConfigTransforms.isTooLargeToReadWhole(fileAt: sidecar) ? FileText(mapping: sidecar) : nil
            let storedSource = mapped == nil ? try? String(contentsOf: sidecar, encoding: .utf8) : nil
            if let mapped { sidecarFiles[profile.id] = mapped }
            if storedSource == nil, mapped == nil, case .url = profile.source {
                 
                 
                 
                 
                incomplete.append(profile.label)
            }
            if let yaml = storedSource {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                sidecars[profile.id] = yaml
            }
             
             
             
             
            profiles[index].providerDefinitionCredentials = nil
            let resources = collectPublicResources(
                profile: profile,
                workingDir: workingDir
            )
            publicResources[profile.id] = resources.data
            profiles[index].externalResources = resources.references.isEmpty
                ? nil : resources.references
        }
        let globalConfig = GlobalConfig.load(from: defaults)
        let completedVersion = LegacyGlobalConfigMigrationMetadata.completedVersion(
            in: defaults
        )
        let scriptVersion = LegacyGlobalScriptMigrationMetadata.completedVersion(
            in: defaults
        )
        if let scriptVersion,
           scriptVersion <= 0
            || scriptVersion > LegacyGlobalScriptMigrationPlan.currentVersion {
            throw BackupError.unsupportedScriptConfigurationModel(scriptVersion)
        }
        if LegacyGlobalScriptMigrationMetadata.phase(in: defaults) != nil
            || (scriptVersion != nil && ScriptSettings.enabled(from: defaults)) {
            throw BackupError.conflictingScriptConfigurationModel
        }
        if profiles.contains(where: { $0.postMergeScriptID != nil }),
           scriptVersion == nil {
            throw BackupError.conflictingScriptConfigurationModel
        }
        let portableScripts = try portableScripts(
            referencedBy: profiles,
            from: ScriptLibrary.load(from: defaults),
            requireSelfContained: true
        )
        guard incomplete.isEmpty else {
            throw BackupError.incompleteProfiles(incomplete)
        }
         
         
         
         
         
        var effectiveSources: [String: String] = [:]
        var effectiveSourceFiles: [String: FileText] = [:]
        for profile in profiles where isSafeProfileID(profile.id) {
             
             
             
             
            if let file = sidecarFiles[profile.id] {
                switch try effectiveDocument(ofLarge: file, profile: profile, globalConfig: globalConfig) {
                case .file(let text)?: effectiveSourceFiles[profile.id] = text
                case .string(let yaml)?: effectiveSources[profile.id] = yaml
                case nil: break
                }
                continue
            }
            guard let sidecar = sidecars[profile.id] else { continue }
            effectiveSources[profile.id] = try effectiveDocument(of: sidecar, profile: profile, globalConfig: globalConfig)
        }
         
        let resolvedActive: String? = activeProfileID ?? Self.activeProfileID(workingDir: workingDir)
        var archive = BackupArchive(
            profiles: profiles,
            sidecars: sidecars,
            publicResources: publicResources,
            globalConfig: globalConfig,
            runtimeConfig: FlClashRuntimeConfig.load(from: defaults),
            configurationModelVersion: isIdentity(globalConfig)
                ? completedVersion : nil,
            scripts: portableScripts,
            scriptConfigurationModelVersion: scriptVersion,
            effectiveSources: effectiveSources,
            effectiveStage: effectiveStageAfterClientTransforms,
            activeProfileID: resolvedActive,
            sourceInstallID: sourceInstallID ?? autoInstallID(defaults: defaults),
            sourceDevice: sourceDevice,
            exportedAt: exportedAt
        )
        let library = configurationLibraryStore(workingDir: workingDir)
        var libraryArchive = try library.exportArchive()
        let profileIDs = Set(profiles.map(\.id))
        let unpublished = (libraryArchive.snapshot.pendingPublications ?? []).filter { !profileIDs.contains($0.profileID) }
        guard unpublished.isEmpty else { throw ConfigurationLibraryError.busy }
         
         
        libraryArchive.snapshot.recipes.removeAll { !profileIDs.contains($0.id) }
        libraryArchive.snapshot.pendingPublications = nil
        libraryArchive.snapshot.lastMaterializationID = nil
        libraryArchive.publications = []
        archive.sidecarFiles = sidecarFiles
        archive.effectiveSourceFiles = effectiveSourceFiles
        let carried = Self.carryingOnce(libraryArchive, sidecars: sidecars, files: sidecarFiles)
        archive.configurationLibrary = carried.archive
        archive.librarySourcesInSidecars = carried.inSidecars.isEmpty ? nil : carried.inSidecars
        archive.leftOutProfileLabels = leftOut
        archive.modules = ModuleBackupSection.collect(locations: ModuleLocations(container: workingDir.deletingLastPathComponent()))
        return archive
    }

     
     
     
     
    static func carryingOnce(_ library: ConfigurationLibraryArchive, sidecars: [String: String],
                             files: [String: FileText] = [:])
        -> (archive: ConfigurationLibraryArchive, inSidecars: [LibrarySourceInSidecar]) {
        let large = sidecars.filter { ConfigTransforms.isTooLargeToReadWhole($0.value) }.sorted { $0.key < $1.key }
        let mapped = files.sorted { $0.key < $1.key }
        guard !large.isEmpty || !mapped.isEmpty else { return (library, []) }
        var archive = library
        var inSidecars: [LibrarySourceInSidecar] = []
        archive.payloads = library.payloads.map { payload in
            guard let profileID = large.first(where: { sameBytes(payload.original, $0.value) })?.key
                    ?? mapped.first(where: { $0.value.hasBytes(of: payload.original) })?.key else { return payload }
            inSidecars.append(LibrarySourceInSidecar(source: ConfigurationSourceVersion(payload.record), profileID: profileID))
            return ConfigurationSourcePayload(record: payload.record, original: Data(), documentJSON: payload.documentJSON,
                                              resourceFiles: payload.resourceFiles, ruleBaselineJSON: payload.ruleBaselineJSON)
        }
        return (archive, inSidecars)
    }

     
     
    static func takingBack(_ library: ConfigurationLibraryArchive, _ inSidecars: [LibrarySourceInSidecar]?,
                           sidecars: [String: String]) throws -> ConfigurationLibraryArchive {
        guard let inSidecars, !inSidecars.isEmpty else { return library }
        var archive = library
        archive.payloads = try library.payloads.map { payload in
            guard payload.original.isEmpty,
                  let entry = inSidecars.first(where: { $0.source == ConfigurationSourceVersion(payload.record) }) else {
                return payload
            }
            guard let yaml = sidecars[entry.profileID] else {
                throw ConfigurationLibraryError.missingDependency(payload.record.id)
            }
            return ConfigurationSourcePayload(record: payload.record, original: Data(yaml.utf8),
                                              documentJSON: payload.documentJSON, resourceFiles: payload.resourceFiles,
                                              ruleBaselineJSON: payload.ruleBaselineJSON)
        }
        return archive
    }

    private static func sameBytes(_ data: Data, _ text: String) -> Bool {
        guard data.count == text.utf8.count else { return false }
        var text = text
        return text.withUTF8 { bytes in
            data.withUnsafeBytes { raw in raw.count == 0 || memcmp(raw.baseAddress!, bytes.baseAddress!, raw.count) == 0 }
        }
    }

     
     
     
     
     
    static func effectiveDocument(of raw: String, profile: Profile, globalConfig: OverrideSpec,
                                  refusingScripts: Bool = false) throws -> String {
        let stages: ProfileRuntimeConfigBuilder.RuntimeBuildStages
        if refusingScripts {
            try ProfilePostMergeScriptOwnershipPolicy.validate(
                postMergeScriptID: profile.postMergeScriptID,
                legacyGlobalScriptEnabled: ScriptSettings.enabled()
            )
             
            let refused: (String?, String, String) throws -> String = { id, yaml, _ in
                guard let id else { return yaml }
                guard ScriptLibrary.load().contains(where: { $0.id == id }) else { throw ScriptLibraryError.missing(id) }
                throw ScriptLibraryError.tooLarge
            }
            stages = try ProfileRuntimeConfigBuilder.buildStages(
                raw: raw, profile: profile, globalOverride: globalConfig, runtimeOverride: OverrideSpec(),
                profileScript: refused,
                configScript: { yaml, _ in
                    guard ScriptSettings.enabled() else { return yaml }
                    throw ScriptLibraryError.tooLarge
                },
                postMergeScript: refused,
                applyProviderDefinitions: true, applyProxyChain: true, applyLegacyRelayMigration: true
            )
        } else {
            stages = try ProfileRuntimeConfigBuilder.buildProductionStages(
                raw: raw, profile: profile, runtimeOverride: OverrideSpec(), globalOverride: globalConfig,
                applyProviderDefinitions: true, applyProxyChain: true, applyLegacyRelayMigration: true, scripts: .silent
            )
        }
        return try ProfileRuntimeConfigBuilder.applyingOwnLayer(of: profile, to: stages.afterClientTransforms,
                                                                 listenerWrittenBack: stages.listenerWrittenBack)
    }

    enum LargeEffectiveDocument: Equatable {
         
         
        case file(FileText)
         
         
        case string(String)
    }

     
     
     
     
     
    static func effectiveDocument(ofLarge sidecar: FileText, profile: Profile,
                                  globalConfig: OverrideSpec) throws -> LargeEffectiveDocument? {


        do {
            if let around = try effectiveDocumentAroundRules(of: sidecar, profile: profile, globalConfig: globalConfig) {
                return .file(around)
            }
            let whole = sidecar.string()
            defer { AppCore.returnFreeMemoryNow(after: whole) }
            return .string(try effectiveDocument(of: whole, profile: profile, globalConfig: globalConfig))
        } catch ScriptLibraryError.tooLarge {
            return nil
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func effectiveDocumentAroundRules(of sidecar: FileText, profile: Profile,
                                             globalConfig: OverrideSpec) throws -> FileText? {
        guard let whole = sidecar.range, !(profile.memoryTrim ?? MemoryTrimSpec()).dropsRuleLines else { return nil }
        struct Reading {
            let cut: TopLevelYAMLSections.PlacedCut
             
            let rules: Range<Int>
            let layout: RuleLines.Layout
            let matches: [String]
            let crlf: Bool
            let endsWithNewline: Bool
        }
        let reading = try sidecar.file.withUnsafeBytes { raw -> Reading? in
            let text = UnsafeBufferPointer(rebasing: raw.bindMemory(to: UInt8.self)[whole])
            guard let cut = TopLevelYAMLSections.cutting(["rules"], inBytes: text), cut.ranges.count == 1,
                  let found = cut.ranges.first?.range else { return nil }
            let section = UnsafeBufferPointer(rebasing: text[found])
            guard let layout = RuleLines.layout(section), let base = section.baseAddress else { return nil }
            let matches = try RuleLines.rules(in: section, laidOut: layout, whoseLinesHold: ["match"]).filter {
                $0.split(separator: ",", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces).uppercased() == "MATCH"
            }
            return Reading(cut: cut, rules: (whole.lowerBound + found.lowerBound)..<(whole.lowerBound + found.upperBound),
                           layout: layout, matches: matches,
                           crlf: memmem(base, section.count, "\r\n", 2) != nil,
                           endsWithNewline: section.last == UInt8(ascii: "\n"))
        }
        guard let reading else { return nil }
        let marker = "DOMAIN,clash-backup-\(UUID().uuidString.lowercased()).invalid,DIRECT"
        let standing = [marker] + reading.matches
         
        let standIn = "rules:" + "\n" + standing.map { "- " + RuleLines.written($0) + "\n" }.joined()
        guard let small = reading.cut.cut(writing: ["rules": standIn]).splicing(into: reading.cut.rest) else { return nil }
        let built: String
        do {
             
             
             
            defer { AppCore.returnFreeMemoryNow(after: small) }
            built = try effectiveDocument(of: small, profile: profile, globalConfig: globalConfig, refusingScripts: true)
        }
         
        if ConfigTransforms.sameText(built, small) { return sidecar }
        guard let builtCut = TopLevelYAMLSections.cutting(["rules"], from: built), let builtRules = builtCut.section("rules"),
              let rules = try ruleList(builtRules), let at = rules.firstIndex(of: marker),
              rules.count >= at + standing.count, Array(rules[at..<(at + standing.count)]) == standing else { return nil }
        let prepended = Array(rules[..<at]), appended = Array(rules[(at + standing.count)...])
        let section = reading.layout.pieces(ofSectionOf: reading.rules.count, prepending: prepended, appending: appended)
         
         
         
         
        let added = !prepended.isEmpty || !appended.isEmpty
        let newline = reading.crlf || (added && reading.layout.newline == "\r\n") ? "\r\n" : "\n"
        let token = "CLASHBACKUPRULES" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let placeholder = "rules:" + newline + "- " + token + (reading.endsWithNewline ? newline : "")
        guard let placed = builtCut.replacingSection("rules", with: placeholder).splicing(into: builtCut.rest),
              let found = placed.range(of: placeholder) else { return nil }
        var pieces: [FileText.Piece] = [.text(String(placed[..<found.lowerBound]))]
        for piece in section {
            switch piece {
            case .bytes(let range):
                pieces.append(.bytes((reading.rules.lowerBound + range.lowerBound)..<(reading.rules.lowerBound + range.upperBound)))
            case .text(let text):
                pieces.append(.text(text))
            }
        }
        pieces.append(.text(String(placed[found.upperBound...])))
        return FileText(file: sidecar.file, pieces: pieces.filter { $0 != .text("") })
    }

     
     
    private static func ruleList(_ section: String) throws -> [String]? {
        let json = try ConfigTransforms.yamlToJSON(section)
        guard let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let list = root["rules"] as? [Any] else { return nil }
        let rules = list.compactMap { $0 as? String }
        return rules.count == list.count ? rules : nil
    }

     
     
    static func activeProfileID(workingDir: URL) -> String? {
        (try? ConfigResourceStore(containerURL: workingDir.deletingLastPathComponent()))
            .flatMap { try? $0.activeIdentity() }?.profileID
    }

     
     
     
     
     
     
     
     
     
    private func sanitizedForPortableStorage() throws -> BackupArchive {
        var copy = self
        var sanitizedProfiles = copy.profiles
        var sanitizedSidecars: [String: String] = [:]
        var omittedRemoteSources = 0
        for (profileID, yaml) in copy.sidecars where Self.isSafeProfileID(profileID) {
            sanitizedSidecars[profileID] = yaml
        }
         
         
         
         
         
         
        _ = omittedRemoteSources
         
         
         
         
         
         
        copy.profiles = sanitizedProfiles
        copy.sidecars = sanitizedSidecars
        copy.effectiveSources = copy.effectiveSources?.filter { Self.isSafeProfileID($0.key) }
        copy.sidecarFiles = copy.sidecarFiles.filter { Self.isSafeProfileID($0.key) }
        copy.effectiveSourceFiles = copy.effectiveSourceFiles.filter { Self.isSafeProfileID($0.key) }
        let portableResources = copy.publicResources
        copy.publicResources = Self.sanitizePublicResources(
            portableResources,
            profiles: &copy.profiles
        )

        if var runtimeConfig = copy.runtimeConfig {
            runtimeConfig = FlClashRuntimeConfig.replacingGlobalFields(
                in: runtimeConfig,
                with: runtimeConfig.patchJSON,
                keys: OverridePatch.globalRuntimeKeys
            )
            copy.runtimeConfig = runtimeConfig
        }
        if copy.schemaVersion >= 4,
           copy.profiles.contains(where: { $0.postMergeScriptID != nil }),
           copy.scriptConfigurationModelVersion == nil {
            throw BackupError.conflictingScriptConfigurationModel
        }
        copy.scripts = try Self.portableScripts(
            referencedBy: copy.profiles,
            from: copy.scripts,
            requireSelfContained: copy.schemaVersion >= 4
        )
        _ = try copy.scriptConfigurationModel()
        return copy
    }

     
     
     
     
     
    private static func portableScripts(
        referencedBy profiles: [Profile],
        from scripts: [ConfigScript],
        requireSelfContained: Bool
    ) throws -> [ConfigScript] {
        var orderedIDs: [String] = []
        var seen: Set<String> = []
        for profile in profiles {
            for id in [profile.selectedScriptID, profile.postMergeScriptID].compactMap({ $0 })
            where seen.insert(id).inserted {
                orderedIDs.append(id)
            }
        }

         
         
         
         
         
         
        let referenced = seen
        for script in scripts where seen.insert(script.id).inserted {
            orderedIDs.append(script.id)
        }

         
         
         
         
         
        return try orderedIDs.compactMap { id in
            let isReferenced = referenced.contains(id)
            let matches = scripts.filter { $0.id == id }
            guard let script = matches.first else {
                if requireSelfContained, isReferenced {
                    throw BackupError.missingReferencedScript
                }
                return nil
            }
            guard matches.count == 1,
                  isValidPortableScriptIdentity(script) else {
                if isReferenced { throw BackupError.invalidScript }
                return nil
            }
             
             
             
             
             
            return script
        }
    }

    private static func isValidPortableScriptIdentity(_ script: ConfigScript) -> Bool {
        let idBytes = script.id.lengthOfBytes(using: .utf8)
        let labelBytes = script.label.lengthOfBytes(using: .utf8)
        let bodyBytes = script.body.lengthOfBytes(using: .utf8)
        return idBytes > 0
            && idBytes <= 256
            && labelBytes <= 1_024
            && bodyBytes <= 1_048_576
            && script.id.rangeOfCharacter(from: .controlCharacters) == nil
    }

    private enum ConfigurationModel: Equatable {
        case legacyGlobal
        case profileScoped(version: Int)
    }

    private enum ScriptConfigurationModel: Equatable {
        case legacyGlobal
        case profileScoped(version: Int)
    }

    private struct ScriptRestorePlan {
        let targetScripts: [ConfigScript]
        let targetVersion: Int?
        let shouldDisableLegacyWriter: Bool
        let profileIDsRequiringPreflight: Set<String>
         
         
        let importedProfiles: [Profile]
        let restoredProfiles: [Profile]
    }

    private struct RestorePreparation {
        let payload: BackupArchive
        let importedProfiles: [Profile]
        let importedIDs: Set<String>
        let existingProfiles: [Profile]
        let restoredProfiles: [Profile]
        let affectedProfileIDs: Set<String>
        let targetGlobalConfig: OverrideSpec
        let targetRuntimeConfig: OverrideSpec
        let targetConfigurationVersion: Int?
        let targetScripts: [ConfigScript]
        let targetScriptConfigurationVersion: Int?
        let shouldDisableLegacyScript: Bool
        let profileIDsRequiringPreflight: Set<String>
    }

     
     
     
    func preview(
        workingDir: URL,
        scope: BackupRestoreScope = .allData,
        defaults: UserDefaults = GlobalConfig.appGroupDefaults
    ) throws -> BackupRestorePreview {
        let preparation = try prepareRestore(
            workingDir: workingDir,
            scope: scope,
            defaults: defaults
        )
        let payload = preparation.payload
        let existing = preparation.existingProfiles
        let existingByID = Dictionary(
            existing.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var changes: [BackupRestorePreview.Change] = []

        for restored in preparation.restoredProfiles
        where preparation.affectedProfileIDs.contains(restored.id) {
            guard let local = existingByID[restored.id] else {
                changes.append(.init(
                    profileID: restored.id,
                    label: restored.label,
                    kind: .added
                ))
                continue
            }
            let localSource = Self.sourceYAML(
                workingDir: workingDir,
                profileID: restored.id
            )
            let targetSource = targetSourceYAML(
                for: restored.id,
                preparation: preparation,
                workingDir: workingDir
            )
            let localResources = Self.collectPublicResources(
                profile: local,
                workingDir: workingDir
            ).data
            let targetResources = preparation.importedIDs.contains(restored.id)
                ? payload.publicResources[restored.id] ?? [:]
                : localResources
            let kind: BackupRestorePreview.Change.Kind =
                local == restored
                    && localSource == targetSource
                    && localResources == targetResources
                ? .unchanged : .updated
            changes.append(.init(
                profileID: restored.id,
                label: restored.label,
                kind: kind
            ))
        }

        do {
            changes.append(contentsOf: existing.compactMap { local in
                guard !preparation.importedIDs.contains(local.id) else { return nil }
                return .init(profileID: local.id, label: local.label, kind: .removed)
            })
        }

        let currentGlobalConfig = GlobalConfig.load(from: defaults)
        let currentRuntimeConfig = FlClashRuntimeConfig.load(
            from: defaults
        )
        let currentConfigurationVersion =
            LegacyGlobalConfigMigrationMetadata.completedVersion(in: defaults)
        return BackupRestorePreview(
            changes: changes,
            totalProfilesAfterRestore: preparation.restoredProfiles.count,
            globalConfigChanges: scope == .allData
                && (
                    currentGlobalConfig != preparation.targetGlobalConfig
                        || currentRuntimeConfig
                            != preparation.targetRuntimeConfig
                        || currentConfigurationVersion
                            != preparation.targetConfigurationVersion
                ),
            referencedScriptCount: payload.scripts.count,
            omittedRemoteSourceCount: payload.omittedRemoteSourceCount,
            rebindRequiredProviderCount: payload.sidecars.values.reduce(into: 0) {
                $0 += Self.rebindRequiredProviders(in: $1)
            }
        )
    }

     
     
     
     
     
    static func rebindRequiredProviders(in sidecar: String) -> Int {
        guard let json = try? ConfigTransforms.yamlToJSON(sidecar),
              let root = try? JSONSerialization.jsonObject(with: Data(json.utf8))
                as? [String: Any]
        else { return 0 }
        return ["proxy-providers", "rule-providers"].reduce(into: 0) { total, key in
            guard let providers = root[key] as? [String: Any] else { return }
            total += providers.values.filter {
                ($0 as? [String: Any])?["clash-rebind-required"] as? Bool == true
            }.count
        }
    }

     
     
     
     
     
    @discardableResult
    func restore(
        workingDir: URL,
        scope: BackupRestoreScope = .allData,
        defaults: UserDefaults = GlobalConfig.appGroupDefaults,
        profileScript: (String?, String, String) throws -> String = {
            try ScriptLibrary.apply(id: $0, to: $1, profileName: $2, caller: .silent)
        },
        configScript: (String, String) throws -> String = {
            try ScriptSettings.apply(toConfigYAML: $0, profileName: $1, caller: .silent)
        },
        credentials: CredentialStore = CredentialStore()
    ) throws -> BackupRestoreResult {
        let preparation = try prepareRestore(
            workingDir: workingDir,
            scope: scope,
            defaults: defaults
        )
        if !preparation.profileIDsRequiringPreflight.isEmpty {
            try verifyRestoredProfilesCanBeGenerated(
                preparation,
                workingDir: workingDir,
                profileScript: profileScript,
                configScript: configScript
            )
        }
        let payload = preparation.payload
        let importedProfiles = preparation.importedProfiles
        let importedIDs = preparation.importedIDs
        let profileURL = workingDir.appendingPathComponent("store/profiles.json")
        let profileStore = ProfileStore(fileURL: profileURL)
        let existing = preparation.existingProfiles
        var restoredProfiles = preparation.restoredProfiles

        let library = Self.configurationLibraryStore(workingDir: workingDir)
        let libraryGeneration = try library.snapshot().generation
        var libraryArchive = try Self.takingBack(payload.configurationLibrary ?? .init(snapshot: .init(), payloads: []),
                                                 payload.librarySourcesInSidecars, sidecars: payload.sidecars)
        var registrationFailures: [String] = []
        try library.validateArchive(libraryArchive)
        guard libraryArchive.snapshot.recipes.allSatisfy({ importedIDs.contains($0.id) }),
              libraryArchive.snapshot.pendingPublications?.isEmpty ?? true else {
            throw ConfigurationLibraryError.invalidIdentifier
        }

        let affectedIDs = importedIDs.union(existing.map(\.id))
        let snapshot = try RestoreSnapshot(
            workingDir: workingDir,
            profileURL: profileURL,
            affectedProfileIDs: affectedIDs.filter(Self.isSafeProfileID),
            defaults: defaults
        )
        defer { snapshot.discard() }

        do {
            ScriptLibrary.save(preparation.targetScripts, in: defaults)
            if scope == .allData {
                if preparation.shouldDisableLegacyScript {
                    ScriptSettings.save(
                        enabled: false,
                        body: ScriptSettings.body(from: defaults),
                        in: defaults
                    )
                }
                LegacyGlobalScriptMigrationMetadata.saveCompletedVersion(
                    preparation.targetScriptConfigurationVersion,
                    in: defaults
                )
                LegacyGlobalScriptMigrationMetadata.savePhase(nil, in: defaults)
            }
            let fileManager = FileManager.default
            let storeDir = workingDir.appendingPathComponent("store", isDirectory: true)
            for profile in importedProfiles {
                let directory = storeDir.appendingPathComponent(profile.id, isDirectory: true)
                let sourceURL = directory.appendingPathComponent("source.yaml")
                if let yaml = payload.sidecars[profile.id] {
                    try fileManager.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true
                    )
                     
                     
                     
                     
                    try Data(yaml.utf8).write(
                        to: sourceURL,
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                    )
                } else if fileManager.fileExists(atPath: sourceURL.path) {
                    try fileManager.removeItem(at: sourceURL)
                }
                try ProfileExternalResourceStore.replace(
                    payload.publicResources[profile.id] ?? [:],
                    profileID: profile.id,
                    coreHomeDir: workingDir
                )
            }
            try profileStore.save(restoredProfiles)
            for profile in existing where !importedIDs.contains(profile.id)
                && Self.isSafeProfileID(profile.id) {
                let directory = storeDir.appendingPathComponent(
                    profile.id,
                    isDirectory: true
                )
                if fileManager.fileExists(atPath: directory.path) {
                    try fileManager.removeItem(at: directory)
                }
            }
            if scope == .allData {
                if Self.isIdentity(preparation.targetGlobalConfig) {
                    GlobalConfig.clear(in: defaults)
                } else {
                    GlobalConfig.save(preparation.targetGlobalConfig, in: defaults)
                }
                 
                 
                 
                 
                 
                 
                 
                 
                ModeIntentClock.stamped {
                    FlClashRuntimeConfig.save(
                        preparation.targetRuntimeConfig,
                        in: defaults
                    )
                }
                LegacyGlobalConfigMigrationMetadata.saveCompletedVersion(
                    preparation.targetConfigurationVersion,
                    in: defaults
                )
            }
             
             
             
             
            for profile in restoredProfiles where importedIDs.contains(profile.id) {
                do {
                    if let registration = try ConfigurationLegacyRegistration.prepare(profile: profile,
                        snapshot: libraryArchive.snapshot,
                        load: { try ConfigurationLegacyRegistration.payload(profile: profile, workingDir: workingDir) }) {
                        libraryArchive.snapshot = registration.snapshot
                        libraryArchive.payloads.append(contentsOf: registration.payloads)
                    }
                } catch { registrationFailures.append(profile.label + ": " + error.localizedDescription) }
                 
                 
                do {
                    if let registration = try ConfigurationLegacyRegistration.prepareCustomNodes(profile: profile,
                        snapshot: libraryArchive.snapshot,
                        load: { try ConfigurationLegacyRegistration.customNodePayload(profile: profile, workingDir: workingDir) }) {
                        libraryArchive.snapshot = registration.snapshot
                        libraryArchive.payloads.append(contentsOf: registration.payloads)
                    }
                } catch { registrationFailures.append(profile.label + ": " + error.localizedDescription) }
            }
             
             
             
            _ = try library.restoreArchive(libraryArchive, expectedGeneration: libraryGeneration)
        } catch {
            do {
                try snapshot.rollback(defaults: defaults)
            } catch {
                throw BackupError.rollbackFailed
            }
            throw error
        }

        return BackupRestoreResult(
            importedProfiles: importedProfiles.count,
            totalProfiles: restoredProfiles.count,
            scope: scope,
            registrationFailures: registrationFailures
        )
    }

    private func prepareRestore(
        workingDir: URL,
        scope: BackupRestoreScope,
        defaults: UserDefaults
    ) throws -> RestorePreparation {
        try ConfigurationCenterPublicationBridge.recoverReplacements(
            library: Self.configurationLibraryStore(workingDir: workingDir), workingDir: workingDir)
        let payload = try preparedForRestore()
        let archiveModel = try payload.configurationModel()
        let profileStore = ProfileStore(
            fileURL: workingDir.appendingPathComponent("store/profiles.json")
        )
        let existing = profileStore.load()
        var imported = payload.profiles
        let importedIDs = Set(imported.map(\.id))
         
         
         
         
         
        var restored: [Profile] = imported
        let scriptPlan = try prepareScriptRestore(
            payload: payload,
            importedProfiles: imported,
            restoredProfiles: restored,
            scope: scope,
            defaults: defaults
        )
        imported = scriptPlan.importedProfiles
        restored = scriptPlan.restoredProfiles

        let currentVersion = LegacyGlobalConfigMigrationPlan.currentVersion
        let localVersion = LegacyGlobalConfigMigrationMetadata.completedVersion(
            in: defaults
        )
        let localUsesProfiles = (localVersion ?? 0) >= currentVersion
        let localGlobal = GlobalConfig.load(from: defaults)
        let localRuntime = FlClashRuntimeConfig.load(from: defaults)
        let archivedRuntime = payload.runtimeConfig
            ?? FlClashRuntimeConfig.migrated(
                preferredProfile: imported.first,
                legacyGlobalOverride: payload.globalConfig
            )
        let targetRuntime = scope == .allData
            ? archivedRuntime : localRuntime
        var runtimePreflightIDs =
            scriptPlan.profileIDsRequiringPreflight
        if targetRuntime != localRuntime {
            runtimePreflightIDs.formUnion(restored.map(\.id))
        }

        if !localUsesProfiles {
            if case .profileScoped = archiveModel {
                throw BackupError.incompatibleConfigurationModel
            }
            return RestorePreparation(
                payload: payload,
                importedProfiles: imported,
                importedIDs: importedIDs,
                existingProfiles: existing,
                restoredProfiles: restored,
                affectedProfileIDs: affectedIDs(
                    importedIDs: importedIDs,
                    existing: existing
                ),
                targetGlobalConfig: scope == .allData
                    ? payload.globalConfig : localGlobal,
                targetRuntimeConfig: targetRuntime,
                targetConfigurationVersion: localVersion,
                targetScripts: scriptPlan.targetScripts,
                targetScriptConfigurationVersion: scriptPlan.targetVersion,
                shouldDisableLegacyScript: scriptPlan.shouldDisableLegacyWriter,
                profileIDsRequiringPreflight:
                    runtimePreflightIDs
            )
        }

         
         
         
        if scope == .profilesOnly, !Self.isIdentity(localGlobal) {
            throw BackupError.conflictingConfigurationModel
        }

        var affected = affectedIDs(
            importedIDs: importedIDs,
            existing: existing
        )
        var profileIDsRequiringPreflight =
            runtimePreflightIDs
        if scope == .allData, case .legacyGlobal = archiveModel {
            affected.formUnion(restored.map(\.id))
            profileIDsRequiringPreflight.formUnion(restored.map(\.id))
             
             
             
             
             
             
             
            let legacyRuleLayer = OverrideSpec(
                appendRules: payload.globalConfig.appendRules,
                prependRules: payload.globalConfig.prependRules
            )
            restored = restored.map {
                var profile = $0
                profile.migratedGlobalOverride = legacyRuleLayer
                return profile
            }
        }
        restored = restored.map(FlClashRuntimeConfig.sanitizedProfile)

        return RestorePreparation(
            payload: payload,
            importedProfiles: imported,
            importedIDs: importedIDs,
            existingProfiles: existing,
            restoredProfiles: restored,
            affectedProfileIDs: affected,
            targetGlobalConfig: scope == .allData ? OverrideSpec() : localGlobal,
            targetRuntimeConfig: targetRuntime,
            targetConfigurationVersion: localVersion,
            targetScripts: scriptPlan.targetScripts,
            targetScriptConfigurationVersion: scriptPlan.targetVersion,
            shouldDisableLegacyScript: scriptPlan.shouldDisableLegacyWriter,
            profileIDsRequiringPreflight: profileIDsRequiringPreflight
        )
    }

    private func configurationModel() throws -> ConfigurationModel {
        let currentVersion = LegacyGlobalConfigMigrationPlan.currentVersion
        if let version = configurationModelVersion {
            guard version > 0, version <= currentVersion else {
                throw BackupError.unsupportedConfigurationModel(version)
            }
            guard Self.isIdentity(globalConfig) else {
                throw BackupError.conflictingConfigurationModel
            }
            return .profileScoped(version: version)
        }

        let hasProfileScopedLayer = profiles.contains {
            $0.migratedGlobalOverride != nil
        }
        if schemaVersion <= 2, hasProfileScopedLayer {
            guard Self.isIdentity(globalConfig) else {
                throw BackupError.conflictingConfigurationModel
            }
             
             
             
            return .profileScoped(version: currentVersion)
        }
        if schemaVersion >= 3, hasProfileScopedLayer {
            throw BackupError.conflictingConfigurationModel
        }
        return .legacyGlobal
    }

    private func prepareScriptRestore(
        payload: BackupArchive,
        importedProfiles: [Profile],
        restoredProfiles: [Profile],
        scope: BackupRestoreScope,
        defaults: UserDefaults
    ) throws -> ScriptRestorePlan {
        guard LegacyGlobalScriptMigrationMetadata.phase(in: defaults) == nil else {
            throw BackupError.conflictingScriptConfigurationModel
        }
        let archiveModel = try payload.scriptConfigurationModel()
        var targetScripts = ScriptLibrary.load(from: defaults)
         
         
         
         
         
         
        var copies: [String: String] = [:]
        for imported in payload.scripts {
            if let existing = targetScripts.first(where: { $0.id == imported.id }) {
                guard existing != imported else { continue }
                 
                if let earlier = targetScripts.first(where: {
                    var same = $0
                    same.id = imported.id
                    return same == imported
                }) {
                    copies[imported.id] = earlier.id
                    continue
                }
                var copy = imported
                copy.id = UUID().uuidString.lowercased()
                copies[imported.id] = copy.id
                targetScripts.append(copy)
            } else {
                targetScripts.append(imported)
            }
        }
        let importedProfiles = importedProfiles.map { Self.referencing(copies, in: $0) }
        let restoredProfiles = restoredProfiles.map { Self.referencing(copies, in: $0) }
        try Self.validateScriptReferences(
            in: importedProfiles,
            scripts: targetScripts
        )
        try Self.validateScriptReferences(
            in: restoredProfiles,
            scripts: targetScripts
        )

        let currentVersion = LegacyGlobalScriptMigrationPlan.currentVersion
        let localVersion = LegacyGlobalScriptMigrationMetadata.completedVersion(
            in: defaults
        )
        let localUsesProfiles = (localVersion ?? 0) >= currentVersion
        let legacyWriterEnabled = ScriptSettings.enabled(from: defaults)
        let targetVersion: Int?
        let shouldDisableLegacyWriter: Bool
        switch archiveModel {
        case .profileScoped(let archiveVersion):
            guard localUsesProfiles else {
                throw BackupError.incompatibleScriptConfigurationModel
            }
            if scope == .profilesOnly, legacyWriterEnabled {
                throw BackupError.conflictingScriptConfigurationModel
            }
            targetVersion = scope == .allData
                ? max(localVersion ?? 0, archiveVersion)
                : localVersion
            shouldDisableLegacyWriter = scope == .allData && legacyWriterEnabled
        case .legacyGlobal:
            guard !localUsesProfiles || !legacyWriterEnabled else {
                throw BackupError.conflictingScriptConfigurationModel
            }
            targetVersion = localVersion
            shouldDisableLegacyWriter = false
        }

        var preflightIDs = Set(importedProfiles.compactMap { profile -> String? in
            profile.selectedScriptID != nil || profile.postMergeScriptID != nil
                ? profile.id : nil
        })
        if shouldDisableLegacyWriter {
            preflightIDs.formUnion(restoredProfiles.map(\.id))
        }
        return ScriptRestorePlan(
            targetScripts: targetScripts,
            targetVersion: targetVersion,
            shouldDisableLegacyWriter: shouldDisableLegacyWriter,
            profileIDsRequiringPreflight: preflightIDs,
            importedProfiles: importedProfiles,
            restoredProfiles: restoredProfiles
        )
    }

     
    private static func referencing(_ copies: [String: String], in profile: Profile) -> Profile {
        guard !copies.isEmpty else { return profile }
        var moved = profile
        if let id = moved.selectedScriptID, let copy = copies[id] { moved.selectedScriptID = copy }
        if let id = moved.postMergeScriptID, let copy = copies[id] { moved.postMergeScriptID = copy }
        return moved
    }

    private func scriptConfigurationModel() throws -> ScriptConfigurationModel {
        let currentVersion = LegacyGlobalScriptMigrationPlan.currentVersion
        if let version = scriptConfigurationModelVersion {
            guard version > 0, version <= currentVersion else {
                throw BackupError.unsupportedScriptConfigurationModel(version)
            }
            return .profileScoped(version: version)
        }
        if profiles.contains(where: { $0.postMergeScriptID != nil }) {
            guard schemaVersion <= 3 else {
                throw BackupError.conflictingScriptConfigurationModel
            }
             
             
             
            return .profileScoped(version: currentVersion)
        }
        return .legacyGlobal
    }

    private static func validateScriptReferences(
        in profiles: [Profile],
        scripts: [ConfigScript]
    ) throws {
        guard profiles.allSatisfy({ profile in
            [profile.selectedScriptID, profile.postMergeScriptID]
                .compactMap { $0 }
                .allSatisfy { id in scripts.filter { $0.id == id }.count == 1 }
        }) else {
            throw BackupError.missingReferencedScript
        }
    }

    private func verifyRestoredProfilesCanBeGenerated(
        _ preparation: RestorePreparation,
        workingDir: URL,
        profileScript: (String?, String, String) throws -> String,
        configScript: (String, String) throws -> String,
    ) throws {
        let targetScriptIDs = Set(preparation.targetScripts.map(\.id))
        let applyProfileScript: (String?, String, String) throws -> String = { id, yaml, name in
            guard let id else { return try profileScript(nil, yaml, name) }
            guard targetScriptIDs.contains(id) else {
                return try profileScript(id, yaml, name)
            }
            return try ScriptLibrary.apply(
                id: id,
                to: yaml,
                scripts: preparation.targetScripts,
                profileName: name, caller: .silent
            )
        }
        for (index, profile) in preparation.restoredProfiles.enumerated()
        where preparation.profileIDsRequiringPreflight.contains(profile.id) {
            guard let source = targetSourceYAML(
                for: profile.id,
                preparation: preparation,
                workingDir: workingDir
            ) else {
                throw BackupError.configurationMigrationBlocked(
                    .sourceUnavailable(profileIndex: index)
                )
            }
             
             
             
             
             
             
             
            if ConfigTransforms.isTooLargeToReadWhole(source) {
                do { try ConfigTransforms.validateSource(source) } catch {
                    throw BackupError.configurationMigrationBlocked(.runtimeGenerationFailed(profileIndex: index))
                }
                continue
            }
            let runtime: String
             
             
             
             
             
             
             
             
            var asRestored = profile
            asRestored.proxyCredentials = nil
            asRestored.sourceCredentials = nil
            asRestored.sourceCredentialsRedacted = false
            do {
                runtime = try ProfileRuntimeConfigBuilder.build(
                    raw: source,
                    profile: asRestored,
                    globalOverride: OverrideSpec(),
                    runtimeOverride:
                        preparation.targetRuntimeConfig,
                    profileScript: applyProfileScript,
                    configScript: { yaml, name in
                        guard !preparation.shouldDisableLegacyScript else {
                            return yaml
                        }
                        return try configScript(yaml, name)
                    },
                    postMergeScript: applyProfileScript
                )
            } catch {
                throw BackupError.configurationMigrationBlocked(
                    .runtimeGenerationFailed(profileIndex: index)
                )
            }
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            _ = runtime
        }
    }

    private func targetSourceYAML(
        for profileID: String,
        preparation: RestorePreparation,
        workingDir: URL
    ) -> String? {
        if preparation.importedIDs.contains(profileID) {
             
             
             
            return preparation.payload.sidecars[profileID]
        }
        return Self.sourceYAML(workingDir: workingDir, profileID: profileID)
    }

    private func affectedIDs(
        importedIDs: Set<String>,
        existing: [Profile]
    ) -> Set<String> {
        importedIDs.union(existing.map(\.id))
    }

    private func preparedForRestore() throws -> BackupArchive {
         
         
        var payload = try sanitizedForPortableStorage().readWhole()
         
         
        var unique: [Profile] = []
        for profile in payload.profiles {
            guard Self.isSafeProfileID(profile.id) else {
                throw BackupError.unsafeProfileID(profile.id)
            }
            if let index = unique.firstIndex(where: { $0.id == profile.id }) {
                unique[index] = profile
            } else {
                unique.append(profile)
            }
        }
        payload.profiles = unique
        payload.sidecars = payload.sidecars.filter { profileID, _ in
            Self.isSafeProfileID(profileID) && unique.contains(where: { $0.id == profileID })
        }
        payload.publicResources = payload.publicResources.filter { profileID, _ in
            Self.isSafeProfileID(profileID) && unique.contains(where: { $0.id == profileID })
        }
        return payload
    }

    private static func collectPublicResources(
        profile: Profile,
        workingDir: URL
    ) -> (references: [ProfileExternalResourceReference], data: [String: Data]) {
        var references: [ProfileExternalResourceReference] = []
        var data: [String: Data] = [:]
        for reference in profile.externalResources ?? []
        where isPublicReference(reference) && isSafeStorageKey(reference.storageKey) {
            let url = workingDir.appendingPathComponent(
                "store/\(profile.id)/resources/\(reference.storageKey)"
            )
            guard let bytes = try? Data(contentsOf: url),
                  isSafePublicResource(bytes) else { continue }
            references.append(reference)
            data[reference.storageKey] = bytes
        }
        return (references, data)
    }

    private static func sanitizePublicResources(
        _ resources: [String: [String: Data]],
        profiles: inout [Profile]
    ) -> [String: [String: Data]] {
        var sanitized: [String: [String: Data]] = [:]
        for index in profiles.indices where isSafeProfileID(profiles[index].id) {
            let profileID = profiles[index].id
            let candidates = resources[profileID] ?? [:]
            var keptReferences: [ProfileExternalResourceReference] = []
            var keptData: [String: Data] = [:]
            for reference in profiles[index].externalResources ?? []
            where isPublicReference(reference) && isSafeStorageKey(reference.storageKey) {
                guard let bytes = candidates[reference.storageKey],
                      isSafePublicResource(bytes) else { continue }
                keptReferences.append(reference)
                keptData[reference.storageKey] = bytes
            }
            profiles[index].externalResources = keptReferences.isEmpty
                ? nil : keptReferences
            if !keptData.isEmpty { sanitized[profileID] = keptData }
        }
        return sanitized
    }

    private static func isPublicReference(_ reference: ProfileExternalResourceReference) -> Bool {
        IOSExternalResourceCatalog.entries.contains {
            $0.id == reference.capabilityID
                && $0.disposition == .publicFileOrInline
                && $0.confidentiality == .publicData
        }
    }

    private static func isSafeStorageKey(_ key: String) -> Bool {
        key.hasPrefix("resource-") && !key.contains("/") && !key.contains("\\")
    }

    private static func isSafePublicResource(_ data: Data) -> Bool {
        guard !data.isEmpty,
              data.count <= ProfileExternalResourceImporter.maximumResourceBytes,
              let text = String(data: data, encoding: .utf8) else { return false }
        let upper = text.uppercased()
        return upper.contains("-----BEGIN CERTIFICATE-----")
            && !upper.contains("PRIVATE KEY-----")
            && !upper.contains("OPENVPN STATIC KEY")
    }

    private static func sourceYAML(workingDir: URL, profileID: String) -> String? {
        guard isSafeProfileID(profileID) else { return nil }
        return try? String(
            contentsOf: workingDir.appendingPathComponent("store/\(profileID)/source.yaml"),
            encoding: .utf8
        )
    }

     
     
     
     
    private final class RestoreSnapshot {
        private let fileManager = FileManager.default
        private let workingDir: URL
        private let profileURL: URL
        private let root: URL
        private let affectedProfileIDs: [String]
        private let originalProfileData: Data?
        private let originalProfileFileExisted: Bool
        private let originalGlobalConfig: OverrideSpec
        private let originalRuntimeConfig: OverrideSpec
        private let originalRuntimeConfigInitialized: Bool
        private let originalConfigurationVersion: Int?
        private let originalScripts: [ConfigScript]
        private let originalLegacyScript: LegacyGlobalScriptState
        private let originalScriptConfigurationVersion: Int?
        private let originalScriptMigrationPhase: LegacyGlobalScriptMigrationPhase?

        init(
            workingDir: URL,
            profileURL: URL,
            affectedProfileIDs: Set<String>,
            defaults: UserDefaults
        ) throws {
            self.workingDir = workingDir
            self.profileURL = profileURL
            self.affectedProfileIDs = affectedProfileIDs.sorted()
            originalProfileFileExisted = FileManager.default.fileExists(atPath: profileURL.path)
            originalProfileData = originalProfileFileExisted
                ? try Data(contentsOf: profileURL)
                : nil
            originalGlobalConfig = GlobalConfig.load(from: defaults)
            originalRuntimeConfig = FlClashRuntimeConfig.load(
                from: defaults
            )
            originalRuntimeConfigInitialized =
                FlClashRuntimeConfig.isInitialized(in: defaults)
            originalConfigurationVersion =
                LegacyGlobalConfigMigrationMetadata.completedVersion(in: defaults)
            originalScripts = ScriptLibrary.load(from: defaults)
            originalLegacyScript = LegacyGlobalScriptState(
                enabled: ScriptSettings.enabled(from: defaults),
                body: ScriptSettings.body(from: defaults)
            )
            originalScriptConfigurationVersion =
                LegacyGlobalScriptMigrationMetadata.completedVersion(in: defaults)
            originalScriptMigrationPhase =
                LegacyGlobalScriptMigrationMetadata.phase(in: defaults)
            root = workingDir.appendingPathComponent(
                ".restore-transaction-\(UUID().uuidString.lowercased())",
                isDirectory: true
            )
            do {
                try FileManager.default.createDirectory(
                    at: root,
                    withIntermediateDirectories: true,
                    attributes: [
                        .protectionKey:
                            FileProtectionType.completeUntilFirstUserAuthentication
                    ]
                )
                let storeDir = workingDir.appendingPathComponent("store", isDirectory: true)
                for id in self.affectedProfileIDs {
                    let source = storeDir.appendingPathComponent(id, isDirectory: true)
                    guard FileManager.default.fileExists(atPath: source.path) else { continue }
                    try FileManager.default.copyItem(
                        at: source,
                        to: root.appendingPathComponent(id, isDirectory: true)
                    )
                }
            } catch {
                try? FileManager.default.removeItem(at: root)
                throw error
            }
        }

        func rollback(defaults: UserDefaults) throws {
            let storeDir = workingDir.appendingPathComponent("store", isDirectory: true)
            try fileManager.createDirectory(at: storeDir, withIntermediateDirectories: true)
            for id in affectedProfileIDs {
                let target = storeDir.appendingPathComponent(id, isDirectory: true)
                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.removeItem(at: target)
                }
                let saved = root.appendingPathComponent(id, isDirectory: true)
                if fileManager.fileExists(atPath: saved.path) {
                    try fileManager.copyItem(at: saved, to: target)
                }
            }
            if let originalProfileData {
                try originalProfileData.write(
                    to: profileURL,
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                )
            } else if originalProfileFileExisted == false,
                      fileManager.fileExists(atPath: profileURL.path) {
                try fileManager.removeItem(at: profileURL)
            }
            GlobalConfig.save(originalGlobalConfig, in: defaults)
             
             
             
             
             
            ModeIntentClock.stamped {
                if originalRuntimeConfigInitialized {
                    FlClashRuntimeConfig.save(
                        originalRuntimeConfig,
                        in: defaults
                    )
                } else {
                    FlClashRuntimeConfig.clear(in: defaults)
                }
            }
            LegacyGlobalConfigMigrationMetadata.saveCompletedVersion(
                originalConfigurationVersion,
                in: defaults
            )
            ScriptLibrary.save(originalScripts, in: defaults)
            ScriptSettings.save(
                enabled: originalLegacyScript.enabled,
                body: originalLegacyScript.body,
                in: defaults
            )
            LegacyGlobalScriptMigrationMetadata.saveCompletedVersion(
                originalScriptConfigurationVersion,
                in: defaults
            )
            LegacyGlobalScriptMigrationMetadata.savePhase(
                originalScriptMigrationPhase,
                in: defaults
            )
        }

        func discard() {
            try? fileManager.removeItem(at: root)
        }
    }

    private static func isSafeProfileID(_ id: String) -> Bool {
        guard !id.isEmpty, id != ".", id != ".." else { return false }
        guard id.lowercased() != "profiles.json" else { return false }
        return id.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\:\0")) == nil
    }

    private static func isIdentity(_ spec: OverrideSpec) -> Bool {
        spec.patchJSON.isEmpty && spec.appendRules.isEmpty
    }
}

extension BackupArchive.BackupError: LocalizedError {
    var errorDescription: String? {
        switch self {
                case .incompleteProfiles(let labels):
            return "%@ could not be backed up completely: a saved credential is missing. Re-enter it, then back up again."
                .replacingOccurrences(of: "%@", with: labels.joined(separator: ", "))
case .unsupportedSchema:
            return "This backup was made by a newer version of Clash. Update Clash before restoring it."
        case .unsupportedConfigurationModel:
            return "This backup uses a newer configuration ownership model. Update Clash before restoring it."
        case .incompatibleConfigurationModel:
            return "This backup was created after settings moved into each profile. Open the new Clash interface before restoring it."
        case .conflictingConfigurationModel:
            return "The backup contains both app-wide and profile-owned settings, so it was not restored."
        case .configurationMigrationBlocked(let blocker):
            return blocker.userMessage
        case .unsupportedScriptConfigurationModel:
            return "This backup uses a newer script ownership model. Update Clash before restoring it."
        case .incompatibleScriptConfigurationModel:
            return "This backup uses profile-owned scripts. Open the new Clash interface before restoring it."
        case .conflictingScriptConfigurationModel:
            return "The backup and this device disagree about script ownership, so nothing was changed."
        case .missingReferencedScript:
            return "A profile references a script that is not available in this portable backup."
        case .invalidScript:
            return "The backup contains invalid or duplicate script metadata."
        case .unsafeProfileID:
            return "The backup contains an unsafe profile identifier."
        case .rollbackFailed:
            return "Restore failed and the previous local state could not be fully recovered."
        }
    }
}
