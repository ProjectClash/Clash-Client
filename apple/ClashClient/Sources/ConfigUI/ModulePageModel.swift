#if os(iOS) || os(macOS)
import ClashClientKit
import ClashClientUI
import Foundation
#if canImport(UIKit)
import SafariServices
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

 
 
 
@MainActor
final class ModuleEntrySource: ObservableObject {
    @Published private(set) var entry: ClashModulesEntrySnapshot?

    func set(_ entry: ClashModulesEntrySnapshot?) {
        if self.entry != entry { self.entry = entry }
    }
}

 
 
 
 
@MainActor
final class ModuleAddRequest: ObservableObject {
    @Published private(set) var link: String?
    @Published private(set) var isPageOnScreen = false
    private var pagesOnScreen = 0

     
    func request(link: String) {
        self.link = link
    }

     
    func settle() {
        if link != nil { link = nil }
    }

    func pageAppeared() {
        pagesOnScreen += 1
        if !isPageOnScreen { isPageOnScreen = true }
    }

    func pageDisappeared() {
        pagesOnScreen = max(0, pagesOnScreen - 1)
        if isPageOnScreen, pagesOnScreen == 0 { isPageOnScreen = false }
    }
}

 
 
 
 
@MainActor
final class ModulePageModel: ObservableObject {
    struct Dependencies {
        var container: URL
        var modules: ModuleStore
        var readiness: ModuleEngineReadinessSource
        var platform: ModulePlatform = .current
        var isConnected: @MainActor () -> Bool = ModulePageModel.isConnectedHere
         
         
         
         
         
         
         
         
         
         
        var reconnect: (URL) async -> Void = { container in
            _ = await ModuleChangeTakers.shared.reconnect(in: container)
        }
        var open: (URL) -> Void = ModulePageModel.openInSystem
#if os(iOS)
         
         
         
        var profileServer: (_ handOut: ModuleCertificateHandOut, _ fetched: @escaping @Sendable () -> Void,
                            _ stopped: @escaping @Sendable (ModuleCertificateProfileServer.Stop) -> Void)
            -> ModuleCertificateProfileServer = { handOut, fetched, stopped in
                ModuleCertificateProfileServer(profile: handOut.profile, page: handOut.page, fetched: fetched, stopped: stopped)
            }
         
         
         
         
        var presentProfilePage: @MainActor (_ page: URL, _ closed: @escaping @MainActor () -> Void) -> Void =
            ModulePageModel.presentInApp
#endif
         
         
        var openCertificateFile: (URL) -> Void = { _ in }
         
         
         
        var installAndTrust: @Sendable (Data) -> ModuleCertificateInstallOutcome = { _ in
            .failed(.install, status: errSecUnimplemented)
        }
         
         
        var openKeychainAccess: () -> Void = {}
         
         
         
        var removeCertificate: @Sendable (Data) -> ModuleCertificateRemoval = { _ in .failed(status: errSecUnimplemented) }
         
         
        var isCertificateLeft: @Sendable (Data) -> Bool = { _ in false }
         
         
         
        var copy: @MainActor (String) -> Void = { ClashClipboard.copy($0, feedback: nil, operation: "modules.detail.copy") }
         
         
        var copyLink: @MainActor (String, ClashFeedbackCenter?) -> Void = {
            ClashClipboard.copy($0, feedback: $1, noun: "Module Link", operation: "modules.module.copy-link")
        }
         
         
         
         
        var runPanelScript: @MainActor (_ module: String, _ script: String, _ byReader: Bool) async -> ModuleAppScriptResult? = { _, _, _ in nil }
         
         
         
        var runAppScript: @MainActor (_ id: String) async -> ModuleAppScriptResult? = { _ in nil }
        var now: () -> Date = Date.init
         
         
        var activation: Notification.Name?

        var certificates: ModuleCertificateStore { readiness.certificates }

        static func production() -> Dependencies? {
            guard let container = productionContainer() else { return nil }
            var dependencies = Dependencies(container: container, modules: ModuleStore.shared(container),
                                            readiness: ModuleEngineReadinessSource.shared(container))
             
             
             
            if !isReviewLaunch {
#if os(macOS)
                 
                dependencies.openCertificateFile = { ModuleKeychainAccess.open($0) }
                dependencies.installAndTrust = { ModuleKeychainAccess.installAndTrust($0) }
                dependencies.openKeychainAccess = { ModuleKeychainAccess.openApplication() }
                dependencies.removeCertificate = { ModuleKeychainAccess.remove($0) }
                dependencies.isCertificateLeft = { ModuleKeychainAccess.isInKeychain($0) }
#endif
                dependencies.runPanelScript = { module, script, byReader in
                    let runner = ModuleAppScriptRunner.shared
                    guard let entry = runner.entries(.generic).first(where: { $0.moduleID == module && $0.name == script }) else { return nil }
                    return await runner.run(entry, trigger: .panel(byReader: byReader))
                }
                dependencies.runAppScript = { id in
                    let runner = ModuleAppScriptRunner.shared
                    guard let entry = runner.entry(id: id) else { return nil }
                    return await runner.run(entry, trigger: .byReader)
                }
            }
#if os(iOS)
            dependencies.activation = UIApplication.didBecomeActiveNotification
#else
            dependencies.activation = NSApplication.didBecomeActiveNotification
#endif
            return dependencies
        }
    }

     
     
    @MainActor
    static func isConnectedHere() -> Bool {
#if os(macOS)
        isConnectedOnTheMac?() ?? false
#else
        ClashSystemActionDispatch.handoff.isVPNSnapshotActive
#endif
    }

#if os(macOS)
     
    static var isConnectedOnTheMac: (@MainActor () -> Bool)?
#endif

    static let shared = ModulePageModel(dependencies: .production())

     
     
    static func updateOperation(of id: String) -> String { "modules.update.\(id)" }



     
    nonisolated static var isReviewLaunch: Bool {

        false

    }

     
     
    nonisolated static func productionContainer(reviewing: Bool = isReviewLaunch) -> URL? {


        return ClashAppIdentifiers.appGroupContainer
    }

    @Published private(set) var snapshot = ClashModulesSnapshot.off
    @Published private(set) var details = Details()
    @Published private(set) var isAdding = false
    @Published var addRefusal: ClashDisplayText?
    let entrySource = ModuleEntrySource()
    let addRequest = ModuleAddRequest()
    var locale: Locale = AppPreferences.language().localeOverride ?? .current

    private let deps: Dependencies?
    private var busy = false
     
     
     
     
     
     
     
     
     
     
    let writes = ClashModulesWrites()
    private var updating: Set<String> = []
     
    private var batch: ClashModulesSnapshot.Batch?
    private var editor: ClashModuleEditorSnapshot?
    private var actionFailure: AuthoredText?
    private var actionModuleID: String?
     
    private var settingsFailure: AuthoredText?
    private var settingsModuleID: String?
     
     
    private var panelResults: [String: ModulePanelResult]?
    private var panelsRefreshing: Set<String> = []
     
    private var appScriptsRunning: Set<String> = []
    private var panelsFailed: Set<String> = []
    private var certificateFailure: AuthoredText?
     
    private var readFailure: AuthoredText?
     
     
    private var keychainFallback: (certificate: String?, at: ModuleKeychainFallback)?
    private var pending: [UUID: Task<Void, Never>] = [:]
    private var observers: [NSObjectProtocol] = []
    private var reloads = 0
     
     
    private var generation = 0
     
     
     
    private var certificateLookedAt: CertificateLook?
    private var readinessWoke = false

    private struct CertificateLook: Equatable {
        var state: ModuleCertificateState
        var unreadable: Bool
    }
     
     
     
     
    private var decryptionCouldWork: Bool?
     
    private var restarting: Task<Void, Never>?
     
    private var turnedOnFor: String?
#if os(iOS)
     
    private var profileServer: ModuleCertificateProfileServer?
#endif
     
     
    var sceneIsActive = true

    init(dependencies: Dependencies?) {
        deps = dependencies
        guard let deps = dependencies else { return }
        let container = deps.container.standardizedFileURL
        for name in [ModuleStore.didChange, ModuleStore.recordsDidChange, ModuleEngineReadinessSource.didChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                 
                 
                guard (note.object as? URL)?.standardizedFileURL == container else { return }
                let fromReadiness = name == ModuleEngineReadinessSource.didChange
                Task { @MainActor [weak self] in
                     
                     
                    if fromReadiness { self?.readinessWoke = true }
                    await self?.reload()
                }
            })
        }
        if let activation = deps.activation {
            observers.append(NotificationCenter.default.addObserver(forName: activation, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.cameToTheFront() }
            })
        }
    }

     
     
     
     
     
     
     
     
     
    func cameToTheFront() async {
        guard let facts = lastFacts, Self.waitsOnTheReaderOutsideTheApp(facts) else { return }
        await reload()
    }

     
     
    static func waitsOnTheReaderOutsideTheApp(_ facts: ModulePageFacts) -> Bool {
        !facts.certificateUnreadable && (facts.certificate == .notInstalled || facts.certificate == .installedNotTrusted)
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

     

     
     
    private struct Read: Sendable {
        var certificate: ModuleCertificateState
        var certificateUnreadable: Bool
        var certificateName: String?
        var oldCertificateLeft: String?
        var report: ModuleEngineReport?
        var summary: ModulePublicationSummary?
        var sources: [String: Data]
        var storedValues: [String: String]
        var panelResults: [String: ModulePanelResult]?
         
        var counted: [String: ModulePageSnapshotBuilder.Counted]
    }

     
    private var reading: Task<Void, Never>?
    private var readAgain = false

     
     
     
    func reload() async {
        if let reading {
            readAgain = true
            await reading.value
            return
        }
        let task = Task { @MainActor in
            repeat {
                readAgain = false
                await readOnce()
            } while readAgain
             
             
            reading = nil
        }
        reading = task
        await task.value
    }

    private func readOnce() async {
        guard let deps else {
            snapshot = .off
            details = Details()
            entrySource.set(nil)
            return
        }
        reloads += 1
        let woke = readinessWoke
        readinessWoke = false
        let state: ModuleState
        do {
            state = try await deps.modules.state()
            readFailure = nil
        } catch {
             
             
             
             
             
             
            readFailure = ModuleStore.authoredText(for: error)
             
             
            let readBefore = lastFacts != nil
            var facts = lastFacts ?? ModulePageFacts(platform: deps.platform, state: ModuleState())
            facts.actionFailure = actionFailure ?? readFailure
            facts.isConnected = deps.isConnected()
            facts.isBusy = busy
            publish(facts, entry: readBefore)
            return
        }
        let irs = await deps.modules.publishedModules(state.modules.map(\.id))
        let container = deps.container
        let certificates = deps.certificates
        let enabled = state.enabled
         
         
         
        var wanting = ModulePageFacts(platform: deps.platform, state: state)
        wanting.modules = irs
        let asks = enabled || (deps.platform == .ios && ModulePageSnapshotBuilder.wantsDecryption(wanting))
        let ids = state.modules.map(\.id)
         
        let storedKeys = Set(irs.values.flatMap { ir in
            ir.manifest.arguments.compactMap { argument -> String? in
                switch argument.kind {
                case .storedChoice, .storedInput: return argument.name
                case .text, .toggle, .choice, .input: return nil
                }
            }
        })
        let isLeft = deps.isCertificateLeft
        let readsPanels = panelResults == nil
        let records = state.modules


        let read = await Task.detached(priority: .userInitiated) { () -> Read in
            let modules = ModuleLocations(container: container)
            let engine = ModuleEngineLocations(container: container)
            let report = ModuleEngineReport.load(engine)
            var unreadable = false
            var certificate = ModuleCertificateState.notGenerated
            var name: String?
            var oldLeft: String?
             
             
             
            if asks {
                if case .unavailable = ModuleCAFiles.status(engine) {
                    unreadable = true
                } else {
                    certificate = certificates.state(report: report)
                    name = certificates.metadata()?.commonName
                }
                oldLeft = certificates.retiredCertificates().first(where: isLeft).flatMap(ModuleCertificateStore.commonName)
            }
            var sources: [String: Data] = [:]
            for id in ids { sources[id] = try? Data(contentsOf: modules.source(id)) }
            let summary = ModulePublicationSummary.load(locations: modules)
            var stored: [String: String] = [:]
            if !storedKeys.isEmpty {
                let store = ModuleScriptStore(directory: container.appendingPathComponent(ModuleScriptStore.directoryName, isDirectory: true),
                                              log: { _ in })
                for key in storedKeys { stored[key] = store.readShared(key: key) }
            }
            return Read(certificate: certificate, certificateUnreadable: unreadable, certificateName: name, oldCertificateLeft: oldLeft,
                        report: report, summary: summary, sources: sources,
                        storedValues: stored, panelResults: readsPanels ? ModulePanelResults.load(container: container) : nil,
                        counted: ModulePageSnapshotBuilder.counted(records, modules: irs, sources: sources, summary: summary))
        }.value
        var facts = ModulePageFacts(platform: deps.platform, state: state)
        facts.locations = ModuleLocations(container: deps.container)
        facts.modules = irs
        facts.certificate = read.certificate
        facts.certificateUnreadable = read.certificateUnreadable
        facts.certificateName = read.certificateName
        facts.oldCertificateLeft = read.oldCertificateLeft
        if let fallback = keychainFallback, fallback.certificate == read.certificateName,
           read.certificate == .notInstalled || read.certificate == .installedNotTrusted {
            facts.keychainFallback = fallback.at
        }
        facts.report = read.report
        facts.summary = read.summary
        facts.actionFailure = actionFailure ?? readFailure
        facts.actionModuleID = actionModuleID
        facts.certificateFailure = certificateFailure
        facts.isConnected = deps.isConnected()
        facts.isBusy = busy
        facts.sources = read.sources
        facts.counted = read.counted
        facts.storedValues = read.storedValues
        facts.settingsFailure = settingsFailure
        facts.settingsModuleID = settingsModuleID
        if panelResults == nil { panelResults = read.panelResults ?? [:] }
        withPanels(&facts)
        publish(facts)


        followTheTrust(facts, deps)
         
         
         
         
         
        guard asks else {
            certificateLookedAt = nil
            return
        }
        let look = CertificateLook(state: read.certificate, unreadable: read.certificateUnreadable)
        guard look != certificateLookedAt else { return }
        certificateLookedAt = look
        if !woke, Self.mayAskReadiness(about: deps.container) { deps.readiness.scheduleRecheck() }
    }

     
     
     
     
     
     
     
     
     
     
    private func followTheTrust(_ facts: ModulePageFacts, _ deps: Dependencies) {
         
         
        guard !busy else { return }
        let canWork = facts.state.enabled && facts.certificate == .ready && !facts.certificateUnreadable
        let before = decryptionCouldWork
        decryptionCouldWork = canWork
         
         
        if !writes.switches.isPending(ClashModulesWrites.decryption),
           !facts.state.enabled, facts.certificate == .ready, !facts.certificateUnreadable,
           let name = facts.certificateName, turnedOnFor != name,
           ModulePageSnapshotBuilder.wantsDecryption(facts),
           ModuleDecryptionChoice.read(deps.certificates.locations) == .followsTrust {
             
             
            turnedOnFor = name
            ClashLogStore.shared.append("modules: the certificate \(name) is trusted; HTTPS Decryption turns itself on", stream: .app)
            run { try await self.turnDecryptionOn(deps) }
            return
        }
        if canWork, before == false, facts.isConnected { restartOnce(deps) }
    }

     
    private func restartOnce(_ deps: Dependencies) {
        guard restarting == nil else { return }


        ClashLogStore.shared.append(#"modules: HTTPS Decryption can work now; the connection restarts on it once"#, stream: .app)
        let container = deps.container
        let task = Task { @MainActor [weak self] in
            await deps.reconnect(container)
            self?.restarting = nil
        }
        restarting = task
        track(task)
    }

     
     
     
    private func turnDecryptionOn(_ deps: Dependencies) async throws {
        try await deps.modules.setEnabled(true)
        do {
            _ = try await deps.certificates.ensureCertificate(republishing: deps.modules)
        } catch is ModuleCertificateUnavailable {
             
             
        }
        let modules = deps.modules
        track(Task.detached { _ = await modules.refreshDue(announcedAs: nil) })
    }

     
     
     
     
     
    private func publish(_ facts: ModulePageFacts, entry: Bool = true) {
        generation += 1
        lastFacts = facts
        var page = ModulePageSnapshotBuilder.page(facts, locale: locale)
        page.editor = editor
        page.batch = batch
        if page != snapshot { snapshot = page }
        let details = Details(facts: facts, updating: updating, locale: locale)
        if details != self.details { self.details = details }
        if entry { entrySource.set(ModulePageSnapshotBuilder.entry(facts)) }
    }

     
     
     
    struct Details: Equatable {
        fileprivate var facts: ModulePageFacts?
        fileprivate var updating: Set<String> = []
        fileprivate var locale = Locale.current

         
         
        subscript(id: String) -> ClashModuleDetailSnapshot? {
            guard let facts, let record = facts.state.modules.first(where: { $0.id == id }) else { return nil }
            return ModuleDetailBuilder.detail(record: record, facts: facts, source: facts.sources[id],
                                              isUpdating: updating.contains(id), locale: locale)
        }

         
         
         
         
         
        static func == (lhs: Details, rhs: Details) -> Bool {
            guard lhs.updating == rhs.updating, lhs.locale == rhs.locale else { return false }
            guard let a = lhs.facts, let b = rhs.facts else { return lhs.facts == nil && rhs.facts == nil }
            func omitted(_ facts: ModulePageFacts) -> [ModuleEngineReport.OmittedModule]? {
                facts.isConnected ? facts.report?.omittedModules : nil
            }
            return a.isConnected == b.isConnected
                && ModulePageSnapshotBuilder.decryption(a) == ModulePageSnapshotBuilder.decryption(b)
                && omitted(a) == omitted(b)
                && a.summary == b.summary
                && a.storedValues == b.storedValues
                && a.settingsModuleID == b.settingsModuleID && a.settingsFailure == b.settingsFailure
                && a.panelResults == b.panelResults && a.panelsRefreshing == b.panelsRefreshing
                && a.panelsFailed == b.panelsFailed
                && a.state == b.state && a.sources == b.sources && a.modules == b.modules
        }
    }

     
     
     
    static func mayAskReadiness(about container: URL) -> Bool {
        guard let group = ClashAppIdentifiers.appGroupContainer,
              group.standardizedFileURL == container.standardizedFileURL else { return true }
        return ModuleEngineReadinessSource.observesInThisProcess
    }

     
    private var lastFacts: ModulePageFacts?

     
     
     
     
    func refreshRuntime() async {
         
         
        guard let deps, let before = lastFacts else { return }
        let mine = generation
        let container = deps.container
         
         
        let records = before.state.modules, modules = before.modules, sources = before.sources, last = before.summary
        let (report, summary, counted) = await Task.detached(priority: .utility) {
            () -> (ModuleEngineReport?, ModulePublicationSummary?, [String: ModulePageSnapshotBuilder.Counted]?) in
            let summary = ModulePublicationSummary.load(locations: ModuleLocations(container: container))
            return (ModuleEngineReport.load(ModuleEngineLocations(container: container)), summary,
                    summary == last ? nil : ModulePageSnapshotBuilder.counted(records, modules: modules, sources: sources, summary: summary))
        }.value


         
        guard mine == generation, var facts = lastFacts else { return }
        let connected = deps.isConnected()
        guard report != facts.report || summary != facts.summary || connected != facts.isConnected else { return }
        facts.report = report
        facts.summary = summary
        if let counted { facts.counted = counted }
        facts.isConnected = connected
        facts.isBusy = busy
        publish(facts)
    }

     

     
     
    func perform(_ action: ClashModulesAction, feedback: ClashFeedbackCenter? = nil) {
        guard let deps else { return }
        switch action {
        case .setEnabled(let on):
             
             
             
             
             
             
             
            actionFailure = nil
            actionModuleID = nil
            writes.switches.press(ClashModulesWrites.decryption, on) { [weak self] on in
                try await self?.writeDecryption(on, deps)
            }
        case .setModule(let id, let enabled):
            switchModule(id, enabled: enabled, deps)
        case .removeModule(let id):
            run(module: id) { try await deps.modules.remove(id) }
        case .refreshModule(let id):
             
            guard !updating.contains(id) else { return }
            updating.insert(id)
            details.updating.insert(id)
            var result: ModuleStore.RefreshResult?
             
             
             
             
             
            run(module: id, afterReading: { [weak self] in
                guard let self, let result, let said = self.updateResult([(id, result)]) else { return }
                feedback?.show(said, operation: Self.updateOperation(of: id))
            }) {
                 
                result = await deps.modules.refresh(id, readerAsked: true)
                self.updating.remove(id)
            }
        case .certificate(let kind):
            certificate(kind, deps)
        case .renewCertificate:
             
            run(certificate: true) {
                _ = try await deps.certificates.regenerate(republishing: deps.modules)
                 
                 
                 
                await Self.removeRetired(deps)
            }
        case .notice(.retryAfterMemoryStop):
             
            run { deps.readiness.noteRetry() }
        case .notice(.runScriptAgain):
            break  
        case .newModule:
            editor = ClashModuleEditorSnapshot()
            publishEditor()
        case .editModule(let id):
            let text = (try? Data(contentsOf: ModuleLocations(container: deps.container).source(id)))
                .map { String(decoding: $0, as: UTF8.self) }
            editor = ClashModuleEditorSnapshot(moduleID: id, text: text)
            publishEditor()
        case .saveModule(let id, let text):
            save(id: id, text: text, deps)
        case .closeEditor:
            editor = nil
            publishEditor()
        case .copy(let words):
             
             
            if snapshot.modules.contains(where: { $0.link == words }) {
                deps.copyLink(words, feedback)
            } else {
                deps.copy(words)
            }
        case .setArgument(let id, let name, let value):
             
             
             
             
            settingsFailure = nil
            settingsModuleID = nil
            writes.settings.press(ClashModulesWrites.setting(module: id, name: name), value) { [weak self] value in
                try await self?.writeSettings(of: id, deps) { try await deps.modules.setArgumentValue(value, for: name, module: id) }
            }
        case .resetArguments(let id):
            settingsFailure = nil
            settingsModuleID = nil
            writes.settings.press(ClashModulesWrites.reset(module: id), nil) { [weak self] _ in
                try await self?.writeSettings(of: id, deps) { try await deps.modules.resetArguments(module: id) }
            }
        case .refreshPanel(let key):
            refreshPanel(key, byReader: true, deps)
        case .runAppScript(let id):
            runAppScript(id, deps, feedback)
        case .panelsAppeared(let id):
            refreshDuePanels(of: id, deps)
        case .renameModule(let id, let name):
            run(module: id) { try await deps.modules.rename(id, to: name) }
        case .moveModules(let ids):
            run { try await deps.modules.move(ids) }
        case .refreshAll:
            track(Task { @MainActor in await self.refreshAll(feedback: feedback) })
        }
    }

     
     
     
     
     
     
    func refreshAll(feedback: ClashFeedbackCenter? = nil) async {
        guard let deps, batch?.isRunning != true else { return }
        let ids = (lastFacts?.state.modules ?? []).filter { if case .url = $0.origin { return true } else { return false } }.map(\.id)
        guard !ids.isEmpty else { return }
        setBatch(.init(done: 0, total: ids.count, isRunning: true))
        var results: [(id: String, result: ModuleStore.RefreshResult)] = []
        for (index, id) in ids.enumerated() {
            updating.insert(id)
            let result = await deps.modules.refresh(id, readerAsked: true)
            results.append((id, result))
            updating.remove(id)
            setBatch(.init(done: index + 1, total: ids.count, isRunning: true))
        }
        await reload()
        let finished = ClashModulesSnapshot.Batch(done: ids.count, total: ids.count, isRunning: false)
        setBatch(finished)
         
        if let said = updateResult(results) {
            feedback?.show(said, operation: "modules.update-all")
        }
        track(Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.batchLingersNanoseconds)
            if self.batch == finished { self.setBatch(nil) }
        })
    }

     
    static let batchLingersNanoseconds: UInt64 = 3_000_000_000

    private func setBatch(_ value: ClashModulesSnapshot.Batch?) {
        batch = value
        snapshot.batch = value
    }

     

     
     
     
     
     
    private func updateResult(_ results: [(id: String, result: ModuleStore.RefreshResult)]) -> ClashFeedbackPresentation? {
        guard let facts = lastFacts else { return nil }
        var outcome = UpdateOutcome()
        for (id, result) in results {
            guard let record = facts.state.modules.first(where: { $0.id == id }) else { continue }
            let name = ModulePageSnapshotBuilder.shownName(record, locale: locale)
            switch result {
            case .updated: outcome.changed.append(name)
            case .unchanged:
                 
                 
                 
                 
                let missed = Self.downloadsMissed(by: record, ir: facts.modules[id])
                if let reason = missed.said.first {
                    outcome.failed.append((name, reason.displayText))
                } else if missed.unsaid == 0 {
                    outcome.unchanged.append(name)
                }
            case .failed(let why):
                 
                outcome.failed.append((name, ModuleStoredSentence.failure(why, linked: true).displayText))
            case .superseded, .cancelled, .outOfTime, .missing, .listUnreadable:
                continue
            }
        }
        return outcome.presentation(locale: locale)
    }

     
     
     
     
     
     
     
    static func downloadsMissed(by record: ModuleRecord, ir: ModuleIR?) -> (said: [AuthoredText], unsaid: Int) {
        guard let checked = record.lastCheckedAt else { return ([], 0) }
         
         
        var addresses = record.scriptFailureCount.compactMap { address, count -> String? in
            guard count > 0, let tried = record.scriptAttemptedAt[address], tried.timeIntervalSince(checked) >= 0 else { return nil }
            return address
        }.sorted()
         
        addresses += record.fileStates.compactMap { key, state -> String? in
            guard state.failures > 0, let tried = state.attemptedAt, tried.timeIntervalSince(checked) >= 0,
                  let space = key.firstIndex(of: " ") else { return nil }
            return String(key[key.index(after: space)...])
        }.sorted()
        var said: [AuthoredText] = []
        var unsaid = 0
        for address in addresses {
             
            if let entry = ir?.ignored.first(where: { $0.text == address }) {
                said.append(entry.reason.authoredText)
            } else {
                unsaid += 1
            }
        }
        return (said, unsaid)
    }

     
     
     
     
     
     
    struct UpdateOutcome {
        var changed: [String] = []
        var unchanged: [String] = []
        var failed: [(name: String, reason: ClashDisplayText)] = []

        func presentation(locale: Locale) -> ClashFeedbackPresentation? {
            switch changed.count + unchanged.count + failed.count {
            case 0:
                return nil
            case 1:
                if let name = changed.first {
                    return .success(title: ClashFeedbackCopy.updated(name), accessibilityIdentifier: "feedback.modules.update")
                }
                if let name = unchanged.first {
                    return .information(title: ClashFeedbackCopy.upToDate(name), accessibilityIdentifier: "feedback.modules.update")
                }
                guard let failure = failed.first else { return nil }
                return .error(title: ClashFeedbackCopy.couldNotUpdate(failure.name), message: failure.reason,
                              accessibilityIdentifier: "feedback.modules.update")
            default:
                let title = ClashFeedbackCopy.batch(updated: changed.count, failed: failed.count, unchanged: unchanged.count)
                if failed.isEmpty {
                    return changed.isEmpty
                        ? .information(title: title, isBatchSummary: true, accessibilityIdentifier: "feedback.modules.update")
                        : .success(title: title, isBatchSummary: true, accessibilityIdentifier: "feedback.modules.update")
                }
                 
                let reasons = ClashDisplayText.verbatim(failed.map { failure in
                    "\(failure.name): \(ClashCopy.string(for: failure.reason, locale: locale))"
                }.joined(separator: "\n"))
                return changed.isEmpty && unchanged.isEmpty
                    ? .error(title: title, message: reasons, isBatchSummary: true, accessibilityIdentifier: "feedback.modules.update")
                    : .warning(title: title, message: reasons, isBatchSummary: true, accessibilityIdentifier: "feedback.modules.update")
            }
        }
    }

     

     
    private func appScriptName(_ id: String) -> String? {
        guard let facts = lastFacts else { return nil }
        for record in facts.state.modules where record.enabled {
            for script in facts.modules[record.id]?.appScripts ?? []
            where ModuleAppScriptEntry.id(module: record.id, origin: script.origin) == id {
                return script.name
            }
        }
        return nil
    }

     
     
     
     
     
     
    private func runAppScript(_ id: String, _ deps: Dependencies, _ feedback: ClashFeedbackCenter?) {
        let name = appScriptName(id) ?? ""
        let operation = #"modules.app-script.run"#
        guard deps.isConnected() else {
            feedback?.show(Self.runResult(.notRun(.tunnelNotConnected), name: name), operation: operation)
            return
        }
         
         
        guard appScriptsRunning.insert(id).inserted else {
            feedback?.show(Self.runResult(.notRun(.busy), name: name), operation: operation)
            return
        }
        let started = feedback?.show(.loading(title: .format("Running %@", [name]),
                                              accessibilityIdentifier: Self.runResultIdentifier), operation: operation)
        track(Task { @MainActor in
            let result = await deps.runAppScript(id)
            appScriptsRunning.remove(id)
             
             
            let said = name.isEmpty ? result?.entry.name ?? name : name
            feedback?.answer(started, with: Self.runResult(result?.outcome ?? .notRun(.notFound), name: said),
                             operation: operation)
        })
    }

    static let runResultIdentifier = "modules.appScript.run.result"

     
     
     
    static func runResult(_ outcome: ModuleAppScriptResult.Outcome, name: String) -> ClashFeedbackPresentation {
        let id = runResultIdentifier
        switch outcome {
        case .done:
            return .success(title: .format("Ran %@", [name]), accessibilityIdentifier: id)
        case .aborted(let words):
            return .error(title: .format("%@ ended with an error", [name]), message: .verbatim(words), accessibilityIdentifier: id)
        case .timedOut:
            return .error(title: .format("%@ ran too long and was stopped", [name]), accessibilityIdentifier: id)
        case .notRun(.tunnelNotConnected):
            return .warning(title: "Connect Clash first",
                            message: name.isEmpty ? nil : .format("%@ runs while Clash is connected.", [name]),
                            accessibilityIdentifier: id)
        case .notRun(.busy):
            return .information(title: .format("%@ is still running", [name]), accessibilityIdentifier: id)
        case .notRun(.bodyMissing), .notRun(.bodyMismatch):
            return .warning(title: .format("%@ is not downloaded yet", [name]),
                            message: "Update the module, then run it again.", accessibilityIdentifier: id)
        case .notRun(.notFound):
            return .warning(title: .format("%@ is not in a module turned on", [name]), accessibilityIdentifier: id)
        case .skipped(.quarantined):
            return .warning(title: .format("%@ did not run", [name]),
                            message: "It ran too long before, so it is held until the module is updated.",
                            accessibilityIdentifier: id)
        case .skipped(.paused), .skipped(.lowMemory):
            return .warning(title: .format("%@ did not run", [name]),
                            message: "Scripts are paused for now. Try again later.", accessibilityIdentifier: id)
        case .skipped(.other):
            return .warning(title: .format("%@ did not run", [name]), accessibilityIdentifier: id)
        }
    }

     

     
    private static let panelSaves = DispatchQueue(label: "modules.panels.save", qos: .utility)

     
    private func withPanels(_ facts: inout ModulePageFacts) {
        facts.panelResults = panelResults ?? [:]
        facts.panelsRefreshing = panelsRefreshing
        facts.panelsFailed = panelsFailed
    }

     
    private func publishPanels() {
        guard var facts = lastFacts else { return }
        withPanels(&facts)
        publish(facts)
    }

     
    private func panel(_ key: String) -> (module: String, panel: ModulePanel, script: String)? {
        guard let facts = lastFacts else { return nil }
        for record in facts.state.modules where record.enabled {
            for panel in facts.modules[record.id]?.panels ?? [] where ModulePanelResults.key(module: record.id, panel: panel.name) == key {
                guard let script = panel.scriptName else { return nil }
                return (record.id, panel, script)
            }
        }
        return nil
    }

     
     
     
     
    private func refreshPanel(_ key: String, byReader: Bool, _ deps: Dependencies) {
        guard !panelsRefreshing.contains(key), let found = panel(key), deps.isConnected() else { return }
        panelsRefreshing.insert(key)
        panelsFailed.remove(key)
        publishPanels()
        let task = Task { @MainActor in
            let result = await deps.runPanelScript(found.module, found.script, byReader)
            panelsRefreshing.remove(key)
            switch result?.outcome {
            case .done?:
                let given = result?.panel
                var results = panelResults ?? [:]
                results[key] = ModulePanelResult(title: given?.title, content: given?.content, icon: given?.icon,
                                                 iconColor: given?.iconColor, style: given?.style, at: deps.now())
                panelResults = results
                let container = deps.container
                 
                 
                Self.panelSaves.async { ModulePanelResults.save(results, container: container) }
            case .notRun(.tunnelNotConnected)?, .notRun(.busy)?, .notRun(.notFound)?, .notRun(.bodyMissing)?, nil:
                 
                 
                break
            default:
                panelsFailed.insert(key)
            }
            publishPanels()
        }
        track(task)
    }

     
     
     
    private func refreshDuePanels(of id: String, _ deps: Dependencies) {
        guard deps.isConnected(), let facts = lastFacts, let record = facts.state.modules.first(where: { $0.id == id }),
              record.enabled else { return }
        let now = deps.now()
        for panel in facts.modules[id]?.panels ?? [] {
            guard panel.scriptName != nil, let interval = panel.updateInterval else { continue }
            let key = ModulePanelResults.key(module: id, panel: panel.name)
            if let at = panelResults?[key]?.at, now.timeIntervalSince(at) < Double(interval) { continue }
            refreshPanel(key, byReader: false, deps)
        }
    }

    private func certificate(_ kind: ClashModulesSnapshot.CertificateActionKind, _ deps: Dependencies) {
        switch kind {
        case .create:
            run(certificate: true) { _ = try await deps.certificates.ensureCertificate(republishing: deps.modules) }
        case .installProfile:
#if os(iOS)
            installProfile(deps)
#endif
        case .installAndTrust:
            run(certificate: true) { [weak self] in
                 
                 
                 
                let certificates = deps.certificates
                let install = deps.installAndTrust
                let (name, outcome, honoured) = try await Task.detached(priority: .userInitiated) {
                    () throws -> (String?, ModuleCertificateInstallOutcome, Bool) in
                    let file = try certificates.exportFile()
                    let outcome = install(try Data(contentsOf: file))
                    if outcome.added { certificates.noteExported() }
                     
                     
                    let honoured = outcome != .trusted || certificates.isTrusted()
                    return (certificates.metadata()?.commonName, outcome, honoured)
                }.value
                ClashLogStore.shared.append("modules: the certificate \(name ?? "-") install: \(outcome)", stream: .app)
                if case .failed(let at, _) = outcome {
                    self?.keychainFallback = (name, at)
                } else if !honoured {
                     
                     
                    ClashLogStore.shared.append(#"modules: the system took the certificate's trust and this Mac does not trust it yet"#,
                                                stream: .app)
                    self?.keychainFallback = (name, .trust)
                }
                 
                if outcome == .trusted { await Self.removeRetired(deps) }
            }
        case .openInKeychainAccess where keychainFallback?.at == .trust:
            deps.openKeychainAccess()
        case .openInKeychainAccess:
            run(certificate: true) {
                 
                 
                let certificates = deps.certificates
                let file = try await Task.detached(priority: .userInitiated) { () throws -> URL in
                    let file = try certificates.exportFile()
                    certificates.noteExported()
                    return file
                }.value
                deps.openCertificateFile(file)
            }
        case .makeNew:
            break  
        }
    }

#if os(iOS)
     
     
     
     
     
     
     
     
     
    private func installProfile(_ deps: Dependencies) {
        ModuleDecryptionChoice.record(.followsTrust, in: deps.certificates.locations)
        profileServer?.stop(.closed)
        profileServer = nil
        run(certificate: true) { [weak self] in
            let certificates = deps.certificates
            let modules = deps.modules
            let enabled = (try? await modules.state())?.enabled ?? false
            if enabled {
                _ = try await certificates.ensureCertificate(republishing: modules)
            }
            let handOut = try await Task.detached(priority: .userInitiated) { () throws -> ModuleCertificateHandOut in
                if !enabled { try certificates.ensureCertificate() }
                return try certificates.handOut()
            }.value
            guard let self else { return }
            let server = deps.profileServer(handOut, { [weak self] in
                certificates.noteExported()
                Task { @MainActor [weak self] in await self?.reload() }
            }, { [weak self] _ in
                Task { @MainActor [weak self] in self?.letGo(of: nil) }
            })
            let page = try await server.start()
            self.profileServer = server
            ClashLogStore.shared.append("modules: the certificate \(handOut.commonName) is offered at \(page.absoluteString)", stream: .app)
            deps.presentProfilePage(page) { [weak self, weak server] in
                server?.stop(.closed)
                self?.letGo(of: server)
            }
        }
    }

     
     
    private func letGo(of server: ModuleCertificateProfileServer?) {
        guard let current = profileServer else { return }
        if let server, current !== server { return }
        if server == nil, current.isListening { return }
        profileServer = nil
    }


#endif

    private func save(id: String?, text: String, _ deps: Dependencies) {
        editor?.isSaving = true
        editor?.refusal = nil
        publishEditor()
        let id = id
        let task = Task { @MainActor in
            do {
                _ = try await deps.modules.saveLocalModule(id: id, text: text)
                editor = nil
            } catch {
                editor?.isSaving = false
                editor?.text = text
                editor?.refusal = ModuleStore.authoredText(for: error).displayText
            }
            await reload()
        }
        track(task)
    }

     
    private func publishEditor() {
        snapshot.editor = editor
    }

     
     
     
    func add(_ input: ModuleAddModuleSheet.Input, name: String = "") async -> Bool {
        guard let deps else { return false }
        isAdding = true
        addRefusal = nil
        defer { isAdding = false }
        do {
            let record: ModuleRecord
            switch input {
            case .link(let link):
                record = try await deps.modules.add(url: ModuleInstallLink.moduleLink(in: link) ?? link)
            case .text(let text): record = try await deps.modules.add(text: text)
            }
             
             
             
             
            if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                do {
                    try await deps.modules.rename(record.id, to: name)
                } catch {
                    ClashLogStore.shared.append(#"modules: the name typed for \#(record.id) was not kept: \#(error.localizedDescription)"#, stream: .app)
                }
            }
        } catch {
            addRefusal = ModuleStore.authoredText(for: error).displayText
            return false
        }
        await reload()
        return true
    }

     
     
    func waitForActions() async {
        repeat {
            while let (id, task) = pending.first {
                await task.value
                pending[id] = nil
            }
            await writes.switches.waitForWrites()
            await writes.settings.waitForWrites()
        } while !pending.isEmpty || writes.switches.isDraining || writes.settings.isDraining
    }

     
    var reloadCount: Int { reloads }



     
     
     
     
    private static func removeRetired(_ deps: Dependencies) async {
        let certificates = deps.certificates, remove = deps.removeCertificate
        await Task.detached(priority: .userInitiated) {
            for certificate in certificates.retiredCertificates() {
                let outcome = remove(certificate)
                let name = ModuleCertificateStore.commonName(certificate) ?? "-"
                ClashLogStore.shared.append(#"modules: the replaced certificate \#(name) removal: \#(outcome)"#, stream: .app)
                guard outcome == .removed else { return }
                certificates.forgetRetired(certificate)
            }
        }.value
    }

     
     
     
     
    private func run(module: String? = nil, certificate: Bool = false, settings: Bool = false,
                     afterReading: (@MainActor () -> Void)? = nil,
                     _ work: @escaping () async throws -> Void) {
        busy = true
         
        snapshot.isBusy = true
        actionFailure = nil
        actionModuleID = nil
        certificateFailure = nil
        settingsFailure = nil
        settingsModuleID = nil
        let task = Task { @MainActor in
            do {
                 
                 
                try await self.writes.turns.run { try await work() }
            } catch {
                let said = ModuleStore.authoredText(for: error)
                 
                 
                if certificate {
                    certificateFailure = said
                } else if settings, let module {
                    settingsFailure = said
                    settingsModuleID = module
                } else {
                    actionFailure = said
                }
                actionModuleID = module
                ClashLogStore.shared.append("modules page action failed: \(error.localizedDescription)", stream: .app)
            }
            busy = false
            await reload()
            afterReading?()
        }
        track(task)
    }

     
     
     
     
     
    private func switchModule(_ id: String, enabled: Bool, _ deps: Dependencies) {
        actionFailure = nil
        actionModuleID = nil
        writes.switches.press(ClashModulesWrites.module(id), enabled) { [weak self] enabled in
            try await self?.writeSwitch(module: id) { try await deps.modules.setModule(id, enabled: enabled) }
        }
    }

     
     
     
    private func writeSwitch(module id: String?, _ work: () async throws -> Void) async throws {
        var failed = false
        do {
            try await work()
        } catch ModuleStoreError.moduleGone {
             
             
        } catch {
            failed = true
            actionFailure = ModuleStore.authoredText(for: error)
            actionModuleID = id
            ClashLogStore.shared.append(#"modules page action failed: \#(error.localizedDescription)"#, stream: .app)
        }
        await reload()
        if failed { throw ClashStoredWriteSaidElsewhere() }
    }

     
     
     
     
     
     
    private func writeDecryption(_ on: Bool, _ deps: Dependencies) async throws {
        try await writeSwitch(module: nil) {
            let locations = deps.certificates.locations
            await Task.detached(priority: .userInitiated) {
                ModuleDecryptionChoice.record(on ? .followsTrust : .offByReader, in: locations)
            }.value
            guard on else { return try await deps.modules.setEnabled(false) }
            try await self.turnDecryptionOn(deps)
        }
    }

     
     
     
    private func writeSettings(of id: String, _ deps: Dependencies, _ work: () async throws -> Void) async throws {
        var failed = false
        do {
            try await work()
        } catch ModuleStoreError.moduleGone {
             
        } catch {
            failed = true
            settingsFailure = ModuleStore.authoredText(for: error)
            settingsModuleID = id
            ClashLogStore.shared.append(#"modules page action failed: \#(error.localizedDescription)"#, stream: .app)
        }
        await reload()
        if failed { throw ClashStoredWriteSaidElsewhere() }
    }

    private func track(_ task: Task<Void, Never>) {
        let id = UUID()
        pending[id] = task
        Task { @MainActor [weak self] in
            await task.value
            self?.pending[id] = nil
        }
    }

    nonisolated static func openInSystem(_ url: URL) {
#if canImport(UIKit)
        DispatchQueue.main.async { UIApplication.shared.open(url) }
#elseif canImport(AppKit)
        DispatchQueue.main.async { NSWorkspace.shared.open(url) }
#endif
    }

#if os(iOS)
     
     
     
     
     
     
    static func presentInApp(_ page: URL, closed: @escaping @MainActor () -> Void) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.first { $0.activationState == .foregroundActive }?.keyWindow ?? scenes.first?.keyWindow
        guard var front = window?.rootViewController else {
            openInSystem(page)
            return
        }
        while let next = front.presentedViewController, !next.isBeingDismissed { front = next }
        let safari = SFSafariViewController(url: page)
        safari.dismissButtonStyle = .done
        let closer = ModuleProfilePageCloser(closed)
        safari.delegate = closer
        objc_setAssociatedObject(safari, &ModuleProfilePageCloser.key, closer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        front.present(safari, animated: true)
    }
#endif
}
#if os(iOS)
 
final class ModuleProfilePageCloser: NSObject, SFSafariViewControllerDelegate {
    nonisolated(unsafe) static var key: UInt8 = 0
    private let closed: @MainActor () -> Void

    init(_ closed: @escaping @MainActor () -> Void) {
        self.closed = closed
    }

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        MainActor.assumeIsolated { closed() }
    }
}
#endif
#endif
