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
final class AdBlockEntrySource: ObservableObject {
    @Published private(set) var entry: ClashAdBlockEntrySnapshot?

    func set(_ entry: ClashAdBlockEntrySnapshot?) {
        if self.entry != entry { self.entry = entry }
    }
}

 
 
 
 
@MainActor
final class AdBlockPageModel: ObservableObject {
    struct Dependencies {
        var container: URL
        var modules: AdBlockModuleStore
        var readiness: AdBlockEngineReadinessSource
        var platform: AdBlockPlatform = .current
        var isConnected: @MainActor () -> Bool = AdBlockPageModel.isConnectedHere
         
         
         
         
         
         
         
         
         
         
        var reconnect: (URL) async -> Void = { container in
            _ = await AdBlockModuleChangeTakers.shared.reconnect(in: container)
        }
        var open: (URL) -> Void = AdBlockPageModel.openInSystem
#if os(iOS)
         
         
         
        var profileServer: (_ handOut: AdBlockCertificateHandOut, _ fetched: @escaping @Sendable () -> Void,
                            _ stopped: @escaping @Sendable (AdBlockCertificateProfileServer.Stop) -> Void)
            -> AdBlockCertificateProfileServer = { handOut, fetched, stopped in
                AdBlockCertificateProfileServer(profile: handOut.profile, page: handOut.page, fetched: fetched, stopped: stopped)
            }
         
         
         
         
        var presentProfilePage: @MainActor (_ page: URL, _ closed: @escaping @MainActor () -> Void) -> Void =
            AdBlockPageModel.presentInApp
#endif
         
         
        var openCertificateFile: (URL) -> Void = { _ in }
         
         
         
        var installAndTrust: @Sendable (Data) -> AdBlockCertificateInstallOutcome = { _ in
            .failed(.install, status: errSecUnimplemented)
        }
         
         
        var openKeychainAccess: () -> Void = {}
         
         
         
        var removeCertificate: @Sendable (Data) -> AdBlockCertificateRemoval = { _ in .failed(status: errSecUnimplemented) }
         
         
        var isCertificateLeft: @Sendable (Data) -> Bool = { _ in false }
         
         
         
        var copy: @MainActor (String) -> Void = { ClashClipboard.copy($0, feedback: nil, operation: "adblock.detail.copy") }

        var certificates: AdBlockCertificateStore { readiness.certificates }

        static func production() -> Dependencies? {
            guard let container = ClashAppIdentifiers.appGroupContainer else { return nil }
            var dependencies = Dependencies(container: container, modules: AdBlockModuleStore.shared(container),
                                            readiness: AdBlockEngineReadinessSource.shared(container))
#if os(macOS)
             
            dependencies.openCertificateFile = { AdBlockKeychainAccess.open($0) }
            dependencies.installAndTrust = { AdBlockKeychainAccess.installAndTrust($0) }
            dependencies.openKeychainAccess = { AdBlockKeychainAccess.openApplication() }
            dependencies.removeCertificate = { AdBlockKeychainAccess.remove($0) }
            dependencies.isCertificateLeft = { AdBlockKeychainAccess.isInKeychain($0) }
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

    static let shared = AdBlockPageModel(dependencies: .production())

    @Published private(set) var snapshot = ClashAdBlockSnapshot.off
    @Published private(set) var details: [String: ClashAdBlockModuleDetailSnapshot] = [:]
    @Published private(set) var isAdding = false
    @Published var addRefusal: ClashDisplayText?
    let entrySource = AdBlockEntrySource()
    var locale: Locale = AppPreferences.language().localeOverride ?? .current

    private let deps: Dependencies?
    private var busy = false
    private var updating: Set<String> = []
    private var editor: ClashAdBlockModuleEditorSnapshot?
    private var actionFailure: AuthoredText?
    private var actionModuleID: String?
    private var certificateFailure: AuthoredText?
     
     
    private var keychainFallback: (certificate: String?, at: AdBlockKeychainFallback)?
    private var pending: [UUID: Task<Void, Never>] = [:]
    private var observers: [NSObjectProtocol] = []
    private var reloads = 0
     
     
    private var generation = 0
     
     
     
    private var certificateLookedAt: CertificateLook?
    private var readinessWoke = false

    private struct CertificateLook: Equatable {
        var state: AdBlockCertificateState
        var unreadable: Bool
    }
     
     
     
     
    private var decryptionCouldWork: Bool?
     
    private var restarting: Task<Void, Never>?
     
    private var turnedOnFor: String?
#if os(iOS)
     
    private var profileServer: AdBlockCertificateProfileServer?
#endif
     
     
    var sceneIsActive = true

    init(dependencies: Dependencies?) {
        deps = dependencies
        guard let deps = dependencies else { return }
        let container = deps.container.standardizedFileURL
        for name in [AdBlockModuleStore.didChange, AdBlockModuleStore.recordsDidChange, AdBlockEngineReadinessSource.didChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                 
                 
                guard (note.object as? URL)?.standardizedFileURL == container else { return }
                let fromReadiness = name == AdBlockEngineReadinessSource.didChange
                Task { @MainActor [weak self] in
                     
                     
                    if fromReadiness { self?.readinessWoke = true }
                    await self?.reload()
                }
            })
        }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

     

     
     
    private struct Read: Sendable {
        var certificate: AdBlockCertificateState
        var certificateUnreadable: Bool
        var certificateName: String?
        var oldCertificateLeft: String?
        var report: AdBlockEngineReport?
        var summary: AdBlockPublicationSummary?
        var sources: [String: Data]
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
            details = [:]
            entrySource.set(nil)
            return
        }
        reloads += 1
        let woke = readinessWoke
        readinessWoke = false
        let state: AdBlockModuleState
        do {
            state = try await deps.modules.state()
        } catch {
            actionFailure = AdBlockModuleStore.authoredText(for: error)
            state = AdBlockModuleState()
        }
        var irs: [String: AdBlockModuleIR] = [:]
        for record in state.modules {
            if let ir = await deps.modules.publishedModule(record.id) { irs[record.id] = ir }
        }
        let container = deps.container
        let certificates = deps.certificates
        let enabled = state.enabled
         
         
         
        var wanting = AdBlockPageFacts(platform: deps.platform, state: state)
        wanting.modules = irs
        let asks = enabled || (deps.platform == .ios && AdBlockPageSnapshotBuilder.wantsDecryption(wanting))
        let ids = state.modules.map(\.id)
        let isLeft = deps.isCertificateLeft


        let read = await Task.detached(priority: .userInitiated) { () -> Read in
            let modules = AdBlockModuleLocations(container: container)
            let engine = AdBlockEngineLocations(container: container)
            let report = AdBlockEngineReport.load(engine)
            var unreadable = false
            var certificate = AdBlockCertificateState.notGenerated
            var name: String?
            var oldLeft: String?
             
             
             
            if asks {
                if case .unavailable = AdBlockCAFiles.status(engine) {
                    unreadable = true
                } else {
                    certificate = certificates.state(report: report)
                    name = certificates.metadata()?.commonName
                }
                oldLeft = certificates.retiredCertificates().first(where: isLeft).flatMap(AdBlockCertificateStore.commonName)
            }
            var sources: [String: Data] = [:]
            for id in ids { sources[id] = try? Data(contentsOf: modules.source(id)) }
            return Read(certificate: certificate, certificateUnreadable: unreadable, certificateName: name, oldCertificateLeft: oldLeft,
                        report: report, summary: AdBlockPublicationSummary.load(locations: modules), sources: sources)
        }.value
        var facts = AdBlockPageFacts(platform: deps.platform, state: state)
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
        facts.actionFailure = actionFailure
        facts.actionModuleID = actionModuleID
        facts.certificateFailure = certificateFailure
        facts.isConnected = deps.isConnected()
        facts.isBusy = busy
        facts.sources = read.sources
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

     
     
     
     
     
     
     
     
     
     
    private func followTheTrust(_ facts: AdBlockPageFacts, _ deps: Dependencies) {
         
         
        guard !busy else { return }
        let canWork = facts.state.enabled && facts.certificate == .ready && !facts.certificateUnreadable
        let before = decryptionCouldWork
        decryptionCouldWork = canWork
        if !facts.state.enabled, facts.certificate == .ready, !facts.certificateUnreadable,
           let name = facts.certificateName, turnedOnFor != name,
           AdBlockPageSnapshotBuilder.wantsDecryption(facts),
           AdBlockDecryptionChoice.read(deps.certificates.locations) == .followsTrust {
             
             
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
        } catch is AdBlockCertificateUnavailable {
             
             
        }
        let modules = deps.modules
        track(Task.detached { _ = await modules.refreshDue(announcedAs: nil) })
    }

     
    private func publish(_ facts: AdBlockPageFacts) {
        generation += 1
        var facts = facts
        // Every publish carries what the scripts have answered so far, so a
        // refresh does not make a result the user is reading disappear.
        facts.scriptResults = scriptResults
        lastFacts = facts
        var page = AdBlockPageSnapshotBuilder.page(facts, locale: locale)
        page.editor = editor
        snapshot = page
        details = Dictionary(uniqueKeysWithValues: facts.state.modules.map { record in
            (record.id, AdBlockModuleDetailBuilder.detail(record: record, facts: facts, source: facts.sources[record.id],
                                                          isUpdating: updating.contains(record.id), locale: locale))
        })
        entrySource.set(AdBlockPageSnapshotBuilder.entry(facts))
    }

     
     
     
    static func mayAskReadiness(about container: URL) -> Bool {
        guard let group = ClashAppIdentifiers.appGroupContainer,
              group.standardizedFileURL == container.standardizedFileURL else { return true }
        return AdBlockEngineReadinessSource.observesInThisProcess
    }

     
    private var lastFacts: AdBlockPageFacts?

    /// The last answer of each `generic` script, keyed by body hash. Kept here
    /// rather than in the facts so a republish (a refresh, a toggle) does not
    /// wipe what the user just asked for and read.
    private var scriptResults: [String: ScriptResult] = [:]

     
     
     
     
    func refreshRuntime() async {
         
         
        guard let deps, lastFacts != nil else { return }
        let mine = generation
        let container = deps.container
        let (report, summary) = await Task.detached(priority: .utility) { () -> (AdBlockEngineReport?, AdBlockPublicationSummary?) in
            (AdBlockEngineReport.load(AdBlockEngineLocations(container: container)),
             AdBlockPublicationSummary.load(locations: AdBlockModuleLocations(container: container)))
        }.value


         
        guard mine == generation, var facts = lastFacts else { return }
        let connected = deps.isConnected()
        guard report != facts.report || summary != facts.summary || connected != facts.isConnected else { return }
        facts.report = report
        facts.summary = summary
        facts.isConnected = connected
        facts.isBusy = busy
        publish(facts)
    }

     

    func perform(_ action: ClashAdBlockAction) {
        guard let deps else { return }
        switch action {
        case .setEnabled(let on):
             
             
            AdBlockDecryptionChoice.record(on ? .followsTrust : .offByReader, in: deps.certificates.locations)
            run {
                guard on else { return try await deps.modules.setEnabled(false) }
                 
                 
                 
                 
                try await self.turnDecryptionOn(deps)
            }
        case .setModule(let id, let enabled):
            run(module: id) { try await deps.modules.setModule(id, enabled: enabled) }
        case .removeModule(let id):
            run(module: id) { try await deps.modules.remove(id) }
        case .refreshModule(let id):
             
            guard !updating.contains(id) else { return }
            updating.insert(id)
            details[id]?.isUpdating = true
            run(module: id) {
                _ = await deps.modules.refresh(id)
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
        case .notice(.runScriptAgain(let sha)):
            // A `generic` script's row carries the hash of the body it would
            // run; the task is found by it and run now. What the script
            // answered goes to the page, because these are node checks and
            // unlock tests whose whole purpose is telling the user something —
            // dropping the answer would leave the button looking inert.
            guard let task = AdBlockCronRunner.genericScript(bodySHA256: sha,
                                                            locations: AdBlockModuleLocations(container: deps.container)) else {
                return
            }
            let container = deps.container
            run {
                let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<ScriptOutcome, Never>) in
                    AdBlockCronRunner.runGeneric(task, locations: AdBlockModuleLocations(container: container)) { outcome in
                        continuation.resume(returning: outcome)
                    }
                }
                ClashLogStore.shared.append("ran \(task.script.name): \(outcome)", stream: .app)
                // The result belongs on the screen, not only in the log: the
                // hub's node checks answer with an HTML panel naming the node
                // and its unlock status, and a user who pressed "run" is
                // waiting for exactly that.
                if case .result(let result) = outcome {
                    scriptResults[sha] = result
                    if let facts = lastFacts { publish(facts) }
                }
            }
        case .newModule:
            editor = ClashAdBlockModuleEditorSnapshot()
            publishEditor()
        case .editModule(let id):
            let text = (try? Data(contentsOf: AdBlockModuleLocations(container: deps.container).source(id)))
                .map { String(decoding: $0, as: UTF8.self) }
            editor = ClashAdBlockModuleEditorSnapshot(moduleID: id, text: text)
            publishEditor()
        case .saveModule(let id, let text):
            save(id: id, text: text, deps)
        case .closeEditor:
            editor = nil
            publishEditor()
        case .copy(let words):
            deps.copy(words)
        }
    }

    private func certificate(_ kind: ClashAdBlockSnapshot.CertificateActionKind, _ deps: Dependencies) {
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
                    () throws -> (String?, AdBlockCertificateInstallOutcome, Bool) in
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
        AdBlockDecryptionChoice.record(.followsTrust, in: deps.certificates.locations)
        profileServer?.stop(.closed)
        profileServer = nil
        run(certificate: true) { [weak self] in
            let certificates = deps.certificates
            let modules = deps.modules
            let enabled = (try? await modules.state())?.enabled ?? false
            if enabled {
                _ = try await certificates.ensureCertificate(republishing: modules)
            }
            let handOut = try await Task.detached(priority: .userInitiated) { () throws -> AdBlockCertificateHandOut in
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

     
     
    private func letGo(of server: AdBlockCertificateProfileServer?) {
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
                editor?.refusal = AdBlockModuleStore.authoredText(for: error).displayText
            }
            await reload()
        }
        track(task)
    }

     
    private func publishEditor() {
        snapshot.editor = editor
    }

     
     
    func add(_ input: AdBlockAddModuleSheet.Input) async -> Bool {
        guard let deps else { return false }
        isAdding = true
        addRefusal = nil
        defer { isAdding = false }
        do {
            switch input {
            case .link(let link): _ = try await deps.modules.add(url: link)
            case .text(let text): _ = try await deps.modules.add(text: text)
            }
        } catch {
            addRefusal = AdBlockModuleStore.authoredText(for: error).displayText
            return false
        }
        await reload()
        return true
    }

     
    func waitForActions() async {
        while let (id, task) = pending.first {
            await task.value
            pending[id] = nil
        }
    }

     
    var reloadCount: Int { reloads }



     
     
     
     
    private static func removeRetired(_ deps: Dependencies) async {
        let certificates = deps.certificates, remove = deps.removeCertificate
        await Task.detached(priority: .userInitiated) {
            for certificate in certificates.retiredCertificates() {
                let outcome = remove(certificate)
                let name = AdBlockCertificateStore.commonName(certificate) ?? "-"
                ClashLogStore.shared.append(#"modules: the replaced certificate \#(name) removal: \#(outcome)"#, stream: .app)
                guard outcome == .removed else { return }
                certificates.forgetRetired(certificate)
            }
        }.value
    }

     
     
     
    private func run(module: String? = nil, certificate: Bool = false, _ work: @escaping () async throws -> Void) {
        busy = true
         
        snapshot.isBusy = true
        actionFailure = nil
        actionModuleID = nil
        certificateFailure = nil
        let task = Task { @MainActor in
            do {
                try await work()
            } catch {
                let said = AdBlockModuleStore.authoredText(for: error)
                if certificate { certificateFailure = said } else { actionFailure = said }
                actionModuleID = module
                ClashLogStore.shared.append("modules page action failed: \(error.localizedDescription)", stream: .app)
            }
            busy = false
            await reload()
        }
        track(task)
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
        let closer = AdBlockProfilePageCloser(closed)
        safari.delegate = closer
        objc_setAssociatedObject(safari, &AdBlockProfilePageCloser.key, closer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        front.present(safari, animated: true)
    }
#endif
}
#if os(iOS)
 
final class AdBlockProfilePageCloser: NSObject, SFSafariViewControllerDelegate {
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
