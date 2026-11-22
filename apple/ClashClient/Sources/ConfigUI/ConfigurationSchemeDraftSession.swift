import ClashClientKit
import ClashClientUI
import Combine
import SwiftUI

 
 
 
 
 
 
 

 

 
 
 
 
 
 
 
 
 
enum ConfigurationSchemeChangeNote {
     
    static let becomesOwnKey = "Changes are saved as “%@”, for “%@” only."
    static let alsoChangesKey = "Changes also apply to %@."
    static let stopsFollowingKey = "Once changed, “%@” no longer follows its link."

     
     
     
     
     
     
     
    static func make(profileID: String, library: ConfigurationLibrarySnapshot,
                     profiles: [LibraryUsage.Configuration], locale: Locale) -> String? {
        let name = profiles.first { $0.id == profileID }?.name
            ?? library.recipes.first { $0.id == profileID }?.label ?? profileID
        switch ConfigurationRulesEditOutcome.of(profileID: profileID, in: library) {
        case .becomesOwn(let scheme)?:
            return ClashCopy.format(becomesOwnKey, locale: locale,
                                    ConfigurationRulesEditSnapshot.name(of: scheme, locale: locale), name)
        case .changesInPlace(let ids)?:
            let others = profiles.filter { $0.id != profileID && ids.contains($0.id) }.map(\.name)
            guard ids.contains(profileID), !others.isEmpty else { return nil }
            return ClashCopy.format(alsoChangesKey, locale: locale,
                                    ConfigurationSchemeDetailSnapshot.names([name] + others, locale: locale))
        case nil:
            return nil
        }
    }

     
     
    static func original(name: String, followsLink: Bool, locale: Locale) -> String? {
        followsLink ? ClashCopy.format(stopsFollowingKey, locale: locale, name) : nil
    }
}

 

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class ConfigurationSchemeDraftSession: ObservableObject {
    typealias Edit = (inout ConfigurationRuleDraft) throws -> Void

    let model: ProfilesViewModel
    let profileID: String
     
    var locale: Locale
    @Published private(set) var draft: ConfigurationRuleDraft?
    @Published private(set) var library: ConfigurationLibrarySnapshot?
     
    @Published private(set) var failure: String?
     
    @Published private(set) var isSaving = false
     
     
    var hasUnsavedChanges: Bool { !unsaved.isEmpty }
     
    @Published private(set) var resetDocument: String?
     
    var libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?
     
    var beforeWriteForTesting: (@MainActor () async throws -> Void)?
     
     
    var beforeRuleSetWriteForTesting: (@MainActor () async throws -> Void)?
     
     
    var busyWaitLimit = 40
     
     
    var report: (String) -> Void = { _ in }
     
     
     
    var feedback: ClashFeedbackCenter?
     
     
    static let withdrawnKey = "The last change to “%@” wasn't saved because the library stayed busy, so it's back as it was. Open it and make the change again."

     
     
    func pageOnScreen(_ onScreen: Bool) {
        pagesOnScreen = max(0, pagesOnScreen + (onScreen ? 1 : -1))
    }

     
    private var pagesOnScreen = 0
     
    private var saved: ConfigurationRuleDraft?
    private var changeCount = 0
    private var saveAgain = false
    private var running: Task<Void, Never>?
     
     
    private var unsaved: [(number: Int, edit: Edit)] = []
     
     
    private var reading = false
    private var waitingForRead: [CheckedContinuation<Void, Never>] = []

     
     
     
    init(model: ProfilesViewModel, profileID: String, locale: Locale = .current,
         library: ConfigurationLibrarySnapshot? = nil,
         editor: ConfigurationTowerRuleCustomizationAdapter.LoadedEditor? = nil) {
        self.model = model
        self.profileID = profileID
        self.locale = locale
        self.library = library
        if let editor {
            draft = editor.draft
            saved = editor.draft
            resetDocument = editor.resetDocument
        }
    }

     
    func note(locale: Locale) -> String? {
        guard let library else { return nil }
        return ConfigurationSchemeChangeNote.make(profileID: profileID, library: library,
                                                  profiles: model.profiles.map { .init(id: $0.id, name: $0.label) },
                                                  locale: locale)
    }

     
     
    func load() async {
        guard draft == nil else { return }
        do {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let now = try await Self.snapshot(store)
            library = now
            guard let scheme = ConfigurationRulesEditSnapshot.running(profileID, in: now) else {
                throw ConfigurationLibraryError.unreadable
            }
            let editor = try await ConfigurationTowerRuleCustomizationAdapter.loadEditor(scheme, store: store)
            guard draft == nil else { return }
            draft = editor.draft
            saved = editor.draft
            resetDocument = editor.resetDocument
        } catch {
            failure = ClashErrorCopy.message(error, locale: locale)
        }
    }

     
     
     
    @discardableResult
    func change(_ edit: @escaping @Sendable (inout ConfigurationRuleDraft) throws -> Void) async -> Bool {
        await readDone()
        return apply(edit) { error in
            failure = ClashConfigurationSubRuleCopy.message(error, locale: locale)
        }
    }

     
     
     
     
    @discardableResult
    func apply(_ edit: @escaping Edit, refused: (Error) -> Void) -> Bool {
        guard var value = draft else { return false }
        do {
            try edit(&value)
        } catch {
            refused(error)
            return false
        }
        failure = nil
        guard value != draft else { return true }
        show(value)
        changeCount += 1
        unsaved.append((changeCount, edit))
        if !reading { saveLatest() }
        return true
    }

     
     
     
     
     
    @discardableResult
    func saveLocalRuleSet(_ value: ConfigurationLocalRuleSet?, deleting id: String?) async -> Bool {
        await waitForSaves()
        reading = true
        var written = false
        var read = false
        do {
            try await beforeRuleSetWriteForTesting?()
            guard let known = library, let store = model.configurationLibraryStore else {
                throw ConfigurationLibraryError.unreadable
            }
            let after: ConfigurationLibrarySnapshot
            do {
                after = try await model.saveConfigurationLocalRuleSet(value, deleting: id, generation: known.generation)
            } catch ConfigurationLibraryError.staleGeneration {
                let now = try await Self.snapshot(store)
                guard now.generation != known.generation, now.localRuleSets == known.localRuleSets else {
                    throw ConfigurationLibraryError.staleGeneration
                }
                library = now
                after = try await model.saveConfigurationLocalRuleSet(value, deleting: id, generation: now.generation)
            }
            take(after)
            written = true
            try await readAgain(in: after)
            read = true
        } catch {
            sayFailed(error)
        }
        if endReading(replaying: read) { saveLatest() }
        return written
    }

     
     
     
    func adopt(_ library: ConfigurationLibrarySnapshot) async {
        await waitForSaves()
        guard library.generation > self.library?.generation ?? 0 else { return }
        reading = true
        var read = false
        do {
            try await readAgain(in: library)
            read = true
        } catch {
            sayFailed(error)
        }
        if endReading(replaying: read) { saveLatest() }
    }

     
    func waitForSaves() async {
        while true {
            if reading {
                await readDone()
            } else if isSaving, let running {
                await running.value
            } else {
                return
            }
        }
    }

     
    func take(_ written: ConfigurationLibrarySnapshot) {
        library = written
        libraryChanged?(written)
    }

    func dismissFailure() {
        failure = nil
    }

     
    static func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

     

    private func saveLatest() {
        guard !isSaving else { saveAgain = true; return }
        isSaving = true
        running = Task { @MainActor in
             
            var busyWaits = 0
            repeat {
                saveAgain = false
                guard !reading, let value = draft, let generation = library?.generation else { break }
                let started = changeCount
                do {
                    let (written, stored) = try await save(value, generation: generation)
                    busyWaits = 0
                    take(written)
                    saved = stored.draft
                    resetDocument = stored.resetDocument
                    unsaved.removeAll { $0.number <= started }
                    failure = nil
                    if changeCount == started {
                        show(stored.draft)
                    } else {
                         
                         
                        show(draft?.continuing(after: stored.draft))
                        saveAgain = true
                    }
                } catch let busy as ConfigurationLibraryError where busy == .busy && busyWaits < busyWaitLimit {
                     
                     
                     
                     
                     
                     
                     
                     
                    busyWaits += 1
                    do { try await Task.sleep(nanoseconds: 500_000_000) } catch {}
                    saveAgain = true
                } catch {
                     
                     
                     
                     
                     
                    busyWaits = 0
                    unsaved.removeAll { $0.number <= started }
                    reading = true
                    sayRefused(error)
                    do {
                        try await readAgain(in: nil)
                    } catch {
                        show(saved)
                    }
                     
                     
                    saveAgain = endReading(replaying: true)
                }
            } while saveAgain
            isSaving = false
        }
    }

     
     
     
     
    private func save(_ value: ConfigurationRuleDraft, generation: UInt64) async throws
        -> (ConfigurationLibrarySnapshot, ConfigurationTowerRuleCustomizationAdapter.LoadedEditor) {
        do {
            return try await write(value, generation: generation)
        } catch ConfigurationLibraryError.staleGeneration {
            guard let newer = await newerLibrary(schemeID: value.schemeID) else {
                throw ConfigurationLibraryError.staleGeneration
            }
            library = newer
            return try await write(value, generation: newer.generation)
        }
    }

    private func write(_ value: ConfigurationRuleDraft, generation: UInt64) async throws
        -> (ConfigurationLibrarySnapshot, ConfigurationTowerRuleCustomizationAdapter.LoadedEditor) {
        try await beforeWriteForTesting?()
        let library = try await model.saveConfigurationRuleCustomization(value, profileID: profileID, generation: generation)
        guard let store = model.configurationLibraryStore,
              let own = ConfigurationRulesEditSnapshot.running(profileID, in: library) else {
            throw ConfigurationLibraryError.unreadable
        }
        let read = try await ConfigurationTowerRuleCustomizationAdapter.loadEditor(own, store: store)
        return (library, .init(draft: read.draft.preservingIdentity(from: value), resetDocument: read.resetDocument,
                               ruleSetKeys: read.ruleSetKeys))
    }

     
     
     
    private func newerLibrary(schemeID: String) async -> ConfigurationLibrarySnapshot? {
        guard let store = model.configurationLibraryStore, let known = library else { return nil }
        let now: ConfigurationLibrarySnapshot
        do {
            now = try await Self.snapshot(store)
        } catch {
            return nil
        }
        return ConfigurationRulesEditSnapshot.savesAgain(on: now, known: known, profileID: profileID, schemeID: schemeID)
            ? now : nil
    }

     

     
     
    private func readAgain(in given: ConfigurationLibrarySnapshot?) async throws {
        guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        let now: ConfigurationLibrarySnapshot
        if let given {
            now = given
        } else {
            now = try await Self.snapshot(store)
        }
        guard let scheme = ConfigurationRulesEditSnapshot.running(profileID, in: now) else {
            throw ConfigurationLibraryError.unreadable
        }
        let read = try await ConfigurationTowerRuleCustomizationAdapter.loadEditor(scheme, store: store)
        let shown = saved.map { read.draft.preservingIdentity(from: $0) } ?? read.draft
        library = now
        saved = shown
        resetDocument = read.resetDocument
        show(shown)
    }

     
     
     
     
     
     
     
     
     
     
     
    private func endReading(replaying: Bool) -> Bool {
        reading = false
        let waiting = waitingForRead
        waitingForRead = []
        defer { waiting.forEach { $0.resume() } }
        guard !unsaved.isEmpty, var value = draft else { return false }
        guard replaying else { return true }
        var kept: [(number: Int, edit: Edit)] = []
        for change in unsaved {
            do {
                try change.edit(&value)
                kept.append(change)
            } catch {
                failure = ClashConfigurationSubRuleCopy.message(error, locale: locale)
                report(Self.message(error))
            }
        }
        unsaved = kept
        guard value != draft else { return false }
        show(value)
        changeCount += 1
        return true
    }

     
    private func readDone() async {
        while reading {
            await withCheckedContinuation { waitingForRead.append($0) }
        }
    }

     

     
     
     
     
     
    private func sayRefused(_ error: Error) {
        guard pagesOnScreen == 0, let feedback, (error as? ConfigurationLibraryError) == .busy else {
            sayFailed(error)
            return
        }
        let name = library.flatMap { ConfigurationRulesEditSnapshot.running(profileID, in: $0) }
            .map { ConfigurationRulesEditSnapshot.name(of: $0, locale: locale) } ?? ""
        feedback.show(.error(title: ClashFeedbackCopy.couldNotSave, message: .format(Self.withdrawnKey, [name]),
                             accessibilityIdentifier: "feedback.rules.withdrawn"),
                      operation: "rules.withdrawn")
    }

     
     
    private func sayFailed(_ error: Error) {
        failure = ClashErrorCopy.message(error, locale: locale)
        report(Self.message(error))
    }

     
     
    private func show(_ value: ConfigurationRuleDraft?) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { draft = value }
    }

    private static func snapshot(_ store: ConfigurationLibraryStore) async throws -> ConfigurationLibrarySnapshot {
        try await Task.detached(priority: .userInitiated) { try store.snapshot() }.value
    }
}
