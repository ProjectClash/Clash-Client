import Foundation
import Darwin
import ClashClientKit
import ClashClientUI

 
 
enum ConfigurationCenterPublicationBridge {
    static func stage(_ publication: ConfigurationPublicationPayload,
                            library: ConfigurationLibraryStore, workingDir: URL,
                            writeSource: ((String, Profile, URL) throws -> Void)? = nil) throws -> Profile {
        let store = ProfileStore(fileURL:workingDir.appendingPathComponent("store/profiles.json"))
        if case .unreadable = store.state() { throw ProfileStore.StoreError.unreadableStore }
        var profile = try JSONDecoder().decode(Profile.self,from:publication.profileMetadata)
        guard profile.id == publication.reference.profileID else { throw ConfigurationLibraryError.invalidIdentifier }
        if let existing = store.load().first(where: { $0.id == profile.id }) {
             
             
            return existing
        }
        let snapshot = try library.snapshot()
        guard let recipe = snapshot.recipes.first(where: { $0.id == profile.id }) else {
            throw ConfigurationLibraryError.missingDependency(profile.id)
        }
        var files: [ExternalResourceImportFile] = []
        for reference in Set(recipe.dependencies) {
            files += ConfigurationCenterSourceBridge.boundFiles(try library.payload(reference))
        }
         
         
         
         
        let prepared = files.isEmpty
            ? PreparedExternalResourceImport(yaml: publication.yaml, references: [], publicResources: [:])
            : try ProfileExternalResourceImporter.prepare(yaml:publication.yaml,profileID:profile.id,
                source:.localFile,files:files,requiringAllFiles:false)
        profile.externalResources = prepared.references.isEmpty ? nil : prepared.references
        try ProfileExternalResourceStore.replace(prepared.publicResources,profileID:profile.id,coreHomeDir:workingDir)
        if let writeSource { try writeSource(prepared.yaml,profile,workingDir) }
        else {
            let source = workingDir.appendingPathComponent("store/\(profile.id)/source.yaml")
            try FileManager.default.createDirectory(at:source.deletingLastPathComponent(),withIntermediateDirectories:true)
            try ConfigurationTextFile.write(prepared.yaml, to: source)
        }
        return profile
    }

    static func materialize(_ publication: ConfigurationPublicationPayload,
                            library: ConfigurationLibraryStore, workingDir: URL,
                            writeSource: ((String, Profile, URL) throws -> Void)? = nil) throws -> Profile {
        let profile = try stage(publication,library:library,workingDir:workingDir,writeSource:writeSource)
        let store = ProfileStore(fileURL:workingDir.appendingPathComponent("store/profiles.json"))
         
        if try store.insertIfAbsent(profile) { return profile }
        return store.load().first(where: { $0.id == profile.id }) ?? profile
    }
     
     
    static func reconcileDeletedProfiles(library: ConfigurationLibraryStore, profileStore: ProfileStore) throws {
        guard case .unreadable = profileStore.state() else {
            var snapshot = try library.snapshot()
            let ids = Set(profileStore.load().map(\.id))
            let pending = Set((snapshot.pendingPublications ?? []).map(\.profileID))
            let count = snapshot.recipes.count
            snapshot.recipes.removeAll { !ids.contains($0.id) && !pending.contains($0.id) }
             
             
            let orphaned = snapshot.sources.compactMap { registrationOwner(of: $0.id) }
                .filter { !ids.contains($0) && !pending.contains($0) }
            var dropped = false
            for owner in Set(orphaned) { dropped = dropOwnedRegistrations(of: owner, from: &snapshot) || dropped }
            if snapshot.recipes.count != count || dropped {
                _ = try library.commit(snapshot, payloads: [], expectedGeneration: snapshot.generation)
            }
             
             
             
             
            return
        }
        throw ProfileStore.StoreError.unreadableStore
    }

     
     
     
     
     
     
     
     
     
    static func collectLibraryGarbage(_ library: ConfigurationLibraryStore) {
        let collected: ConfigurationLibraryGarbageCollection
        do { collected = try library.collectGarbage() } catch { return }
        if collected != ConfigurationLibraryGarbageCollection() {
            ClashLogStore.shared.append(
                #"library gc records=\#(collected.removedRecords) versions=\#(collected.removedVersions) publications=\#(collected.removedPublications)"#,
                stream: .app
            )
        }
    }

     
     
     
    static func ownedRegistrations(of profileID: String) -> (sources: [String], rule: String) {
        let sourceID = "legacy-" + profileID
        return ([sourceID, ConfigurationLegacyRegistration.customNodeSourceID(for: profileID)], "rules-" + sourceID)
    }

     
    static func registrationOwner(of sourceID: String) -> String? {
        for prefix in ["legacy-nodes-", "legacy-"] where sourceID.hasPrefix(prefix) {
            let owner = String(sourceID.dropFirst(prefix.count))
            return owner.isEmpty ? nil : owner
        }
        return nil
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    static func dropOwnedRegistrations(of profileID: String, from snapshot: inout ConfigurationLibrarySnapshot) -> Bool {
        let owned = ownedRegistrations(of: profileID)
        let usedSources = Set(snapshot.recipes.flatMap { $0.sources.map(\.id) + [$0.ruleSource.id] })
        let usedRules = Set(snapshot.recipes.map(\.ruleSchemeID))
        let before = snapshot.sources.count + snapshot.rules.count + (snapshot.registeredLegacyProfileIDs?.count ?? 0)
        snapshot.sources.removeAll { owned.sources.contains($0.id) && !usedSources.contains($0.id) }
        if !usedRules.contains(owned.rule) { snapshot.rules.removeAll { $0.id == owned.rule } }
        snapshot.registeredLegacyProfileIDs?.removeAll { $0 == profileID }
        return snapshot.sources.count + snapshot.rules.count + (snapshot.registeredLegacyProfileIDs?.count ?? 0) != before
    }

     
     
     
     
     
     
    static func removesWithoutLibraryWrite(hadRecipe: Bool, droppedRegistrations: Bool, onlyItsMarker: Bool,
                                           publicationUnderWay: Bool) -> Bool {
        !(hadRecipe || droppedRegistrations) || (onlyItsMarker && !hadRecipe && publicationUnderWay)
    }

    static func removeProfile(_ profile: Profile, library: ConfigurationLibraryStore, profileStore: ProfileStore) throws {
        var snapshot = try library.snapshot()
        let hadRecipe = snapshot.recipes.contains { $0.id == profile.id }
        snapshot.recipes.removeAll { $0.id == profile.id }
        let entries = snapshot.sources.count + snapshot.rules.count
        let droppedRegistrations = dropOwnedRegistrations(of: profile.id, from: &snapshot)
        let onlyItsMarker = droppedRegistrations && snapshot.sources.count + snapshot.rules.count == entries
        guard !removesWithoutLibraryWrite(hadRecipe: hadRecipe, droppedRegistrations: droppedRegistrations,
                                          onlyItsMarker: onlyItsMarker,
                                          publicationUnderWay: !(snapshot.pendingPublications?.isEmpty ?? true)) else {
            try profileStore.remove(id: profile.id); return
        }
         
         
         
         
         
        guard !(snapshot.pendingPublications ?? []).contains(where: { $0.profileID == profile.id }) else {
            throw ConfigurationLibraryError.busy
        }
         
         
         
        try ProfileStore.withWriteLock {
            let stored = profileStore.load().first(where: { $0.id == profile.id }) ?? profile
            try profileStore.remove(id: profile.id)
            do { _ = try library.commit(snapshot, payloads: [], expectedGeneration: snapshot.generation) }
            catch {
                 
                 
                try profileStore.upsert(stored)
                throw error
            }
        }
    }

    struct Replacement {
        let previous: Profile
        let profile: Profile
        let previousYAML: String
        let yaml: String
        let resources: [String: Data]
         
         
         
         
        var planned: (source: FileFingerprint, resources: FileFingerprint)? = nil
    }

     
     
     
     
     
     
    struct PublicationFields: Equatable {
        let source: Profile.Source
        let autoUpdate: Bool
        let subscriptionInfo: SubscriptionInfo?
        let label: String
        let labelIsUserAssigned: Bool?
        let externalResources: [ProfileExternalResourceReference]?

        init(_ profile: Profile) {
            source = profile.source
            autoUpdate = profile.autoUpdate
            subscriptionInfo = profile.subscriptionInfo
            label = profile.label
            labelIsUserAssigned = profile.labelIsUserAssigned
            externalResources = profile.externalResources
        }

        func apply(to profile: inout Profile) {
            profile.source = source
            profile.autoUpdate = autoUpdate
            profile.subscriptionInfo = subscriptionInfo
            profile.label = label
            profile.labelIsUserAssigned = labelIsUserAssigned
            profile.externalResources = externalResources
        }

         
         
         
         
        static func undo(_ next: Profile, to previous: Profile, on profile: inout Profile, resources: Bool) {
            if profile.source == next.source { profile.source = previous.source }
            if profile.autoUpdate == next.autoUpdate { profile.autoUpdate = previous.autoUpdate }
            if profile.subscriptionInfo == next.subscriptionInfo { profile.subscriptionInfo = previous.subscriptionInfo }
            if profile.label == next.label, profile.labelIsUserAssigned == next.labelIsUserAssigned {
                profile.label = previous.label
                profile.labelIsUserAssigned = previous.labelIsUserAssigned
            }
            if resources, profile.externalResources == next.externalResources {
                profile.externalResources = previous.externalResources
            }
        }
    }

     
     
     
    private struct RecoveryEntry: Codable {
        let previous: Profile
        let next: Profile
        let previousYAML: String
        let nextYAML: String
        let resourceNames: [String]
         
         
         
         
        var previousResourcesDigest: String? = nil
        var nextResourcesDigest: String? = nil
    }

     
    static func resourcesDigest(_ resources: [String: Data]) -> String {
        let lines = resources.keys.sorted().map { $0 + "\u{0}" + ProfileExternalResourceImporter.sha256(resources[$0] ?? Data()) }
        return ProfileExternalResourceImporter.sha256(Data(lines.joined(separator: "\n").utf8))
    }

     
    static func resourcesOnDisk(_ directory: URL) throws -> [String: Data] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [:] }
        var resources: [String: Data] = [:]
        for file in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            resources[file.lastPathComponent] = try Data(contentsOf: file)
        }
        return resources
    }

     
     
     
     
    struct FileFingerprint: Equatable {
        let entries: [String]

        init(_ url: URL) {
            let fm = FileManager.default
            func line(_ name: String, _ path: String) -> String {
                guard let attributes = try? fm.attributesOfItem(atPath: path) else { return name + "\u{0}-" }
                let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
                let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
                let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
                return "\(name)\u{0}\(inode)\u{0}\(size)\u{0}\(modified)"
            }
            var entries = [line(".", url.path)]
            if let names = try? fm.contentsOfDirectory(atPath: url.path) {
                entries += names.sorted().map { line($0, url.appendingPathComponent($0).path) }
            }
            self.entries = entries
        }
    }
    private struct RecoveryRecord: Codable {
        let schemaVersion: Int
        let id: String
        let entries: [RecoveryEntry]
    }
    private static func recoveryDirectory(_ working: URL) -> URL {
        working.appendingPathComponent("configuration-library/materialization-transaction")
    }
    static func hasReplacementRecovery(workingDir: URL) -> Bool {
        FileManager.default.fileExists(atPath: recoveryDirectory(workingDir).path)
    }
     
     
    private static func withReplacementLock<T>(workingDir: URL, waits: Bool = false, _ operation: () throws -> T) throws -> T {
#if canImport(UIKit)
        let finishAccess = ConfigStoreSuspensionShield.beginLibraryAccess()
        defer { finishAccess() }
#endif
        let directory = workingDir.appendingPathComponent("configuration-library")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.appendingPathComponent("materialization.lock").path,
                      O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ConfigurationLibraryError.unreadable }
        defer { close(fd) }
        guard flock(fd, waits ? LOCK_EX : LOCK_EX | LOCK_NB) == 0 else { throw ConfigurationLibraryError.busy }
        defer { flock(fd, LOCK_UN) }
        return try operation()
    }
     
     
     
     
     
    @discardableResult
    static func recoverReplacements(library: ConfigurationLibraryStore, workingDir: URL,
                                    waitingForPublication: Bool = false) throws -> Set<String> {
        guard hasReplacementRecovery(workingDir: workingDir) else { return [] }
        return try withReplacementLock(workingDir: workingDir, waits: waitingForPublication) {
            try recoverReplacementsLocked(library: library, workingDir: workingDir)
        }
    }
    private static func safeComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\0")
    }
    @discardableResult
    private static func recoverReplacementsLocked(library: ConfigurationLibraryStore, workingDir: URL) throws -> Set<String> {
        let fm = FileManager.default
        let folder = recoveryDirectory(workingDir)
        guard fm.fileExists(atPath: folder.path) else { return [] }
        let ready = folder.appendingPathComponent("ready.json")
        guard fm.fileExists(atPath: ready.path) else {
             
            try fm.removeItem(at: folder); return []
        }
        var putBack: Set<String> = []
        let record = try JSONDecoder().decode(RecoveryRecord.self, from: Data(contentsOf: ready))
        guard record.schemaVersion == 1, UUID(uuidString: record.id) != nil,
              Set(record.entries.map { $0.previous.id }).count == record.entries.count,
              record.entries.allSatisfy({ safeComponent($0.previous.id) && $0.previous.id == $0.next.id
                  && Set($0.resourceNames).count == $0.resourceNames.count
                  && $0.resourceNames.allSatisfy(safeComponent) }) else { throw ConfigurationLibraryError.unreadable }
        if try library.snapshot().lastMaterializationID != record.id {
            let store = ProfileStore(fileURL: workingDir.appendingPathComponent("store/profiles.json"))
            if case .unreadable = store.state() { throw ProfileStore.StoreError.unreadableStore }
             
             
             
             
             
             
             
             
             
             
            struct Undo {
                let entry: RecoveryEntry
                let seen: (source: FileFingerprint, resources: FileFingerprint)
                let filesAreTheTransactions: Bool
                var resources: ProfileExternalResourceStore.Staged?
                var source: URL?
            }
            let present = Set(store.load().map(\.id))
            var undos: [Undo] = []
            defer {
                for undo in undos {
                    if let resources = undo.resources { ProfileExternalResourceStore.discard(resources) }
                    if let source = undo.source { try? fm.removeItem(at: source) }
                }
            }
            for entry in record.entries {
                let id = entry.previous.id
                let url = ProfileSourceStore.runnableURL(workingDirectory: workingDir, profileID: id)
                let resourcesURL = workingDir.appendingPathComponent("store/\(id)/resources", isDirectory: true)
                let seen = (source: FileFingerprint(url), resources: FileFingerprint(resourcesURL))
                let raw = try? Data(contentsOf: url)
                let sourceIsTheTransactions = raw == Data(entry.previousYAML.utf8) || raw == Data(entry.nextYAML.utf8)
                let resourcesAreTheTransactions: Bool
                if let previousDigest = entry.previousResourcesDigest, let nextDigest = entry.nextResourcesDigest {
                    let onDisk = (try? resourcesOnDisk(resourcesURL)).map(resourcesDigest)
                    resourcesAreTheTransactions = onDisk == previousDigest || onDisk == nextDigest
                } else {
                    resourcesAreTheTransactions = sourceIsTheTransactions
                }
                var undo = Undo(entry: entry, seen: seen,
                                filesAreTheTransactions: sourceIsTheTransactions && resourcesAreTheTransactions)
                if undo.filesAreTheTransactions, present.contains(id),
                   fm.fileExists(atPath: url.deletingLastPathComponent().path) {
                    let backup = try Dictionary(uniqueKeysWithValues: entry.resourceNames.map { name in
                        (name, try Data(contentsOf: folder.appendingPathComponent(id).appendingPathComponent(name)))
                    })
                    undo.resources = try ProfileExternalResourceStore.stage(backup, profileID: id, coreHomeDir: workingDir,
                        prefix: ProfileExternalResourceStore.publicationPrefix)
                    let staged = url.deletingLastPathComponent().appendingPathComponent(ProfileSourceStore.stagingName(stagedSourcePrefix))
                    try Data(entry.previousYAML.utf8).write(to: staged,
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    undo.source = staged
                }
                undos.append(undo)
            }


            var retired: [URL] = []
            defer { retired.forEach { try? fm.removeItem(at: $0) } }
            try ProfileStore.withWriteLock {
                var current = store.load()
                for index in undos.indices {
                    let entry = undos[index].entry
                    guard let position = current.firstIndex(where: { $0.id == entry.previous.id }) else { continue }
                    let url = ProfileSourceStore.runnableURL(workingDirectory: workingDir, profileID: entry.previous.id)
                    let resourcesURL = workingDir.appendingPathComponent("store/\(entry.previous.id)/resources", isDirectory: true)
                     
                     
                     
                     
                    let referencesAreTheTransactions = current[position].externalResources == entry.previous.externalResources
                        || current[position].externalResources == entry.next.externalResources
                    let unchanged = FileFingerprint(url) == undos[index].seen.source
                        && FileFingerprint(resourcesURL) == undos[index].seen.resources
                    var restored = false
                    if undos[index].filesAreTheTransactions, referencesAreTheTransactions, unchanged,
                       let resources = undos[index].resources, let source = undos[index].source {
                        if let old = try ProfileExternalResourceStore.swapIn(resources) { retired.append(old) }
                        undos[index].resources = nil
                        guard rename(source.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
                        undos[index].source = nil
                        restored = true
                        putBack.insert(entry.previous.id)
                    }
                    PublicationFields.undo(entry.next, to: entry.previous, on: &current[position], resources: restored)
                }
                try store.save(current)
            }
        }
         
        for entry in record.entries {
            removeStagedPublication(workingDir: workingDir, profileID: entry.previous.id)
        }
         
         
        try RecoveryRebuilds.add(putBack, workingDir: workingDir)
         
        try fm.removeItem(at: folder)
        return putBack
    }



     
    private static let stagedSourcePrefix = ".source-publishing-"

     
     
     
    private static func removeStagedPublication(workingDir: URL, profileID: String, olderThan age: TimeInterval = 0) {
        let directory = workingDir.appendingPathComponent("store/\(profileID)", isDirectory: true)
        let prefixes = [ProfileExternalResourceStore.publicationPrefix, stagedSourcePrefix]
        guard age > 0 else {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            where prefixes.contains(where: name.hasPrefix) {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
            return
        }
        ProfileSourceStore.sweepStaging(in: directory, prefixes: prefixes, olderThan: age)
    }

     
     
     
     
    private static func sweepStagedPublications(workingDir: URL) {
        let store = workingDir.appendingPathComponent("store", isDirectory: true)
        for name in (try? FileManager.default.contentsOfDirectory(atPath: store.path)) ?? [] where safeComponent(name) {
            removeStagedPublication(workingDir: workingDir, profileID: name, olderThan: 600)
        }
    }

    @MainActor
    static func replaceOffMain(_ replacements: [Replacement], candidate: ConfigurationLibrarySnapshot,
                               payloads: [ConfigurationSourcePayload], library: ConfigurationLibraryStore,
                               workingDir: URL, expectedGeneration: UInt64,
                               beforeSourceWrite: (@Sendable (Int) throws -> Void)? = nil) async throws {
         
         
        try await Task.detached(priority: .userInitiated) {
            try ClashPerf.measure("configuration.save.commit") {
                try replace(replacements, candidate: candidate, payloads: payloads, library: library,
                    workingDir: workingDir, expectedGeneration: expectedGeneration, beforeSourceWrite: beforeSourceWrite)
            }
        }.value
    }

    static func replace(_ replacements: [Replacement], candidate: ConfigurationLibrarySnapshot,
                        payloads: [ConfigurationSourcePayload], library: ConfigurationLibraryStore,
                        workingDir: URL, expectedGeneration: UInt64,
                        beforeSourceWrite: ((Int) throws -> Void)? = nil,
                        beforeRegistryHold: (() throws -> Void)? = nil) throws {
        try withReplacementLock(workingDir: workingDir) {
            try recoverReplacementsLocked(library: library, workingDir: workingDir)
            sweepStagedPublications(workingDir: workingDir)
            if replacements.isEmpty {
                _ = try library.commit(candidate, payloads: payloads, expectedGeneration: expectedGeneration)
                return
            }
            let store = ProfileStore(fileURL: workingDir.appendingPathComponent("store/profiles.json"))
            if case .unreadable = store.state() { throw ProfileStore.StoreError.unreadableStore }
             
             
             
             
             
             
             
            let originals = store.load()
            guard try library.snapshot().generation == expectedGeneration,
                  Set(replacements.map { $0.profile.id }).count == replacements.count else {
                throw ConfigurationLibraryError.staleGeneration
            }
            let fm = FileManager.default
            func sourceURL(_ replacement: Replacement) -> URL {
                ProfileSourceStore.runnableURL(workingDirectory: workingDir, profileID: replacement.profile.id)
            }
            func resourcesURL(_ replacement: Replacement) -> URL {
                workingDir.appendingPathComponent("store/\(replacement.profile.id)/resources", isDirectory: true)
            }
             
            func fieldsUnchanged(_ replacement: Replacement, in registry: [Profile]) -> Bool {
                guard let profile = registry.first(where: { $0.id == replacement.previous.id }) else { return false }
                return PublicationFields(profile) == PublicationFields(replacement.previous)
            }
             
             
            var seen: [String: (source: FileFingerprint, resources: FileFingerprint)] = [:]
            var previousResources: [String: [String: Data]] = [:]
            for replacement in replacements {
                guard safeComponent(replacement.profile.id), replacement.previous.id == replacement.profile.id,
                      candidate.recipes.contains(where: { $0.id == replacement.profile.id }),
                      fieldsUnchanged(replacement, in: originals) else {
                    throw ConfigurationLibraryError.staleGeneration
                }
                let now = (source: FileFingerprint(sourceURL(replacement)), resources: FileFingerprint(resourcesURL(replacement)))
                if let planned = replacement.planned, planned.source != now.source || planned.resources != now.resources {
                    throw ConfigurationLibraryError.staleGeneration
                }
                let fingerprints = replacement.planned ?? now
                guard try Data(contentsOf: sourceURL(replacement)) == Data(replacement.previousYAML.utf8) else {
                    throw ConfigurationLibraryError.staleGeneration
                }
                let resources = try resourcesOnDisk(resourcesURL(replacement))
                guard resources.keys.allSatisfy(safeComponent) else { throw ConfigurationLibraryError.unreadable }
                seen[replacement.profile.id] = fingerprints
                previousResources[replacement.profile.id] = resources
            }
             
            var stagedResources: [String: ProfileExternalResourceStore.Staged] = [:]
            var stagedSources: [String: URL] = [:]
            defer {
                stagedResources.values.forEach { ProfileExternalResourceStore.discard($0) }
                stagedSources.values.forEach { try? fm.removeItem(at: $0) }
            }
            for replacement in replacements {
                stagedResources[replacement.profile.id] = try ProfileExternalResourceStore.stage(replacement.resources,
                    profileID: replacement.profile.id, coreHomeDir: workingDir,
                    prefix: ProfileExternalResourceStore.publicationPrefix)
                let staged = sourceURL(replacement).deletingLastPathComponent()
                    .appendingPathComponent(ProfileSourceStore.stagingName(stagedSourcePrefix))
                try Data(replacement.yaml.utf8).write(to: staged,
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                stagedSources[replacement.profile.id] = staged
            }
            let folder = recoveryDirectory(workingDir)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var entries: [RecoveryEntry] = []
            for replacement in replacements {
                let backup = folder.appendingPathComponent(replacement.profile.id)
                try fm.createDirectory(at: backup, withIntermediateDirectories: true)
                let resources = previousResources[replacement.profile.id] ?? [:]
                for (name, data) in resources {
                    try data.write(to: backup.appendingPathComponent(name),
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }
                var entry = RecoveryEntry(previous: replacement.previous, next: replacement.profile,
                    previousYAML: replacement.previousYAML, nextYAML: replacement.yaml,
                    resourceNames: resources.keys.sorted())
                entry.previousResourcesDigest = resourcesDigest(resources)
                entry.nextResourcesDigest = resourcesDigest(replacement.resources)
                entries.append(entry)
            }
            let record = RecoveryRecord(schemaVersion: 1, id: UUID().uuidString, entries: entries)
            try JSONEncoder().encode(record).write(to: folder.appendingPathComponent("ready.json"),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
             
            func orUndo<T>(_ body: () throws -> T) throws -> T {
                do { return try body() } catch {
                    let originalError = error
                    do { try recoverReplacementsLocked(library: library, workingDir: workingDir) }
                    catch { throw BackupArchive.BackupError.rollbackFailed }
                    throw originalError
                }
            }
             
             
             
             
             
             
            var retired: [URL] = []
            defer { retired.forEach { try? fm.removeItem(at: $0) } }
            let wrote: Bool = try orUndo {
                try beforeRegistryHold?()
                return try ProfileStore.withWriteLock {
                    var current = store.load()
                    for replacement in replacements {
                        guard fieldsUnchanged(replacement, in: current),
                              seen[replacement.profile.id]?.source == FileFingerprint(sourceURL(replacement)),
                              seen[replacement.profile.id]?.resources == FileFingerprint(resourcesURL(replacement)) else {
                            return false
                        }
                    }
                    for (index, replacement) in replacements.enumerated() {
                        try beforeSourceWrite?(index)
                        guard let resources = stagedResources.removeValue(forKey: replacement.profile.id),
                              let source = stagedSources[replacement.profile.id] else {
                            throw ConfigurationLibraryError.unreadable
                        }
                        do {
                            if let old = try ProfileExternalResourceStore.swapIn(resources) { retired.append(old) }
                        } catch {
                            ProfileExternalResourceStore.discard(resources)
                            throw error
                        }
                        guard rename(source.path, sourceURL(replacement).path) == 0 else {
                            throw CocoaError(.fileWriteUnknown)
                        }
                        stagedSources[replacement.profile.id] = nil
                        if let position = current.firstIndex(where: { $0.id == replacement.profile.id }) {
                            PublicationFields(replacement.profile).apply(to: &current[position])
                        }
                    }
                    try store.save(current)
                    return true
                }
            }
            guard wrote else {
                 
                try? fm.removeItem(at: folder)
                throw ConfigurationLibraryError.staleGeneration
            }
            try orUndo {
                var committed = candidate
                committed.lastMaterializationID = record.id
                _ = try library.commit(committed, payloads: payloads, expectedGeneration: expectedGeneration)
            }
             
             
            try? FileManager.default.removeItem(at: recoveryDirectory(workingDir))
        }
    }
}

 
 
 
 
 
 
 
 
 
enum RecoveryRebuilds {
    private struct Record: Codable {
        var owed: [String: String]
    }

    private static func url(_ workingDir: URL) -> URL {
        workingDir.appendingPathComponent("configuration-library/rebuild-after-recovery.json")
    }

     
     
     
     
     
     
    private static func withLock<T>(_ workingDir: URL, waits: Bool, _ body: () throws -> T) throws -> T {
        let directory = workingDir.appendingPathComponent("configuration-library", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let shield = ConfigResourceStore.suspensionShield
        let shieldToken = shield.begin()
        defer { shield.end(shieldToken) }
        let fd = open(directory.appendingPathComponent("rebuild-after-recovery.lock").path,
                      O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ConfigurationLibraryError.unreadable }
        defer { close(fd) }
        if waits {
            flock(fd, LOCK_EX)
        } else {
            var tries = 0
            while flock(fd, LOCK_EX | LOCK_NB) != 0 {
                tries += 1
                guard tries < 3 else { throw ConfigurationLibraryError.busy }
                usleep(500)
            }
        }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    private static func read(_ workingDir: URL) -> Record {
        (try? JSONDecoder().decode(Record.self, from: Data(contentsOf: url(workingDir)))) ?? Record(owed: [:])
    }

    private static func write(_ record: Record, _ workingDir: URL) throws {
        guard !record.owed.isEmpty else {
            if FileManager.default.fileExists(atPath: url(workingDir).path) { try FileManager.default.removeItem(at: url(workingDir)) }
            return
        }
        try JSONEncoder().encode(record).write(to: url(workingDir), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

     
     
    static func add(_ ids: Set<String>, workingDir: URL) throws {
        guard !ids.isEmpty else { return }
        try withLock(workingDir, waits: true) {
            var record = read(workingDir)
            for id in ids { record.owed[id] = UUID().uuidString.lowercased() }
            try write(record, workingDir)
        }
    }

     
     
    static func owed(workingDir: URL) -> [String: String] { read(workingDir).owed }

     
     
    static func token(for id: String, workingDir: URL) -> String? { owed(workingDir: workingDir)[id] }

     
     
    static func settle(_ id: String, token: String, workingDir: URL) {
        guard owed(workingDir: workingDir)[id] == token else { return }
        _ = try? withLock(workingDir, waits: false) {
            var record = read(workingDir)
            guard record.owed[id] == token else { return }
            record.owed[id] = nil
            try write(record, workingDir)
        }
    }

     
     
    static func forget(allBut present: Set<String>, workingDir: URL) {
        guard !present.isEmpty, !owed(workingDir: workingDir).keys.allSatisfy(present.contains) else { return }
        _ = try? withLock(workingDir, waits: false) {
            var record = read(workingDir)
            record.owed = record.owed.filter { present.contains($0.key) }
            try write(record, workingDir)
        }
    }
}
