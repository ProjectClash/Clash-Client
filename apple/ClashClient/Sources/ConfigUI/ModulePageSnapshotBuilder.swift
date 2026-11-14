#if os(iOS) || os(macOS)
import ClashClientKit
import ClashClientUI
import Foundation

 
 
 
 
struct ModulePageFacts {
    var platform: ModulePlatform
    var state: ModuleState
     
     
    var locations: ModuleLocations? = nil
     
    var modules: [String: ModuleIR] = [:]
     
     
    var sources: [String: Data] = [:]
    var certificate: ModuleCertificateState = .notGenerated
     
     
     
     
    var certificateUnreadable = false
     
     
    var certificateName: String? = nil
     
     
    var keychainFallback: ModuleKeychainFallback? = nil
     
     
    var oldCertificateLeft: String? = nil
     
    var report: ModuleEngineReport? = nil
     
     
     
    var summary: ModulePublicationSummary? = nil
     
     
    var actionFailure: AuthoredText? = nil
     
     
    var actionModuleID: String? = nil
     
     
    var certificateFailure: AuthoredText? = nil
     
    var isConnected = false
    var isBusy = false
     
     
    var storedValues: [String: String] = [:]
     
     
    var settingsFailure: AuthoredText? = nil
    var settingsModuleID: String? = nil
     
    var panelResults: [String: ModulePanelResult] = [:]
     
     
    var panelsRefreshing: Set<String> = []
    var panelsFailed: Set<String> = []
     
     
     
    var counted: [String: ModulePageSnapshotBuilder.Counted] = [:]
}

 
 
 
 
 
enum ModulePageSnapshotBuilder {
     
     
    static func page(_ facts: ModulePageFacts, locale: Locale) -> ClashModulesSnapshot {
         
         
         
         
        let decryption = decryption(facts)
        let rows = facts.state.modules.map { record in
             
            let counted = facts.modules[record.id].map { counted(facts, record: record, ir: $0) }
            return row(record, ir: counted?.published, locale: locale, decryption: decryption, written: counted?.written)
        }
        let install = install(facts)
        guard facts.state.enabled else {
             
             
             
             
             
            return ClashModulesSnapshot(isOn: false, isBusy: facts.isBusy,
                                        certificate: install == nil ? nil : certificate(facts, locale: locale), install: install,
                                        notices: notices(facts, decryptionOn: false, locale: locale), modules: rows)
        }
        return ClashModulesSnapshot(isOn: true, isBusy: facts.isBusy, certificate: certificate(facts, locale: locale),
                                    install: install, notices: notices(facts, decryptionOn: true, locale: locale), modules: rows)
    }

     
     
     
     
     
     
     
     
     
    struct Counted: Sendable {
         
        var enabled: Bool
        var ir: ModuleIR
        var summary: ModulePublicationSummary?
         
        var written: [Substring]?
        var published: ModuleIR

         
        func holds(_ record: ModuleRecord, ir: ModuleIR, summary: ModulePublicationSummary?) -> Bool {
            enabled == record.enabled && self.summary == summary && self.ir == ir
        }
    }

    static func counted(_ record: ModuleRecord, ir: ModuleIR, source: Data?, summary: ModulePublicationSummary?) -> Counted {
        if Thread.isMainThread { CountedOnTheMainThread.note() }
        let written = ModuleDetailBuilder.writtenLines(source, of: ir)
        return Counted(enabled: record.enabled, ir: ir, summary: summary, written: written,
                       published: ModuleDetailBuilder.published(ir, record: record, publication: summary, written: written))
    }

     
    static func counted(_ records: [ModuleRecord], modules: [String: ModuleIR], sources: [String: Data],
                        summary: ModulePublicationSummary?) -> [String: Counted] {
        var out: [String: Counted] = [:]
        for record in records {
            guard let ir = modules[record.id] else { continue }
            out[record.id] = counted(record, ir: ir, source: sources[record.id], summary: summary)
        }
        return out
    }

     
    static func counted(_ facts: ModulePageFacts, record: ModuleRecord, ir: ModuleIR) -> Counted {
        if let kept = facts.counted[record.id], kept.holds(record, ir: ir, summary: facts.summary) { return kept }
        return counted(record, ir: ir, source: facts.sources[record.id], summary: facts.summary)
    }

     
     
     
    enum CountedOnTheMainThread {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var count = 0
        static func note() { lock.lock(); count += 1; lock.unlock() }
        static var total: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

     
     
    static func wantsDecryption(_ facts: ModulePageFacts) -> Bool {
        facts.state.modules.contains { record in
            record.enabled && facts.modules[record.id]?.mitmHostLines.contains { $0.entries.contains { !$0.excluded } } == true
        }
    }

     
     
     
     
     
     
    static func install(_ facts: ModulePageFacts) -> ClashModulesSnapshot.Install? {
        guard facts.platform == .ios, !facts.certificateUnreadable, facts.certificate != .ready, wantsDecryption(facts) else {
            return nil
        }
        return ClashModulesSnapshot.Install(action: installAction(facts.certificate),
                                            effect: ModuleCertificateCopy.profileDescription.displayText)
    }

     
     
     
    static func installAction(_ state: ModuleCertificateState) -> ClashModulesSnapshot.CertificateAction {
        let shown: ModuleCertificateState = state == .notGenerated ? .notInstalled : state
        return .init(kind: .installProfile, title: ModuleCertificateCopy.action(shown, platform: .ios).displayText)
    }

     
     
     
     
     
     
     
     
     
     
    static func decryption(_ facts: ModulePageFacts) -> ModuleDetailBuilder.Decryption {
        guard facts.state.enabled else { return .off }
        if facts.certificateUnreadable || facts.certificate != .ready { return .notReady(.certificate) }
        if let summary = facts.summary {
            if summary.notApplied != nil { return .notReady(.unavailable) }
            for reason in summary.reasons where kind(of: reason) == .decryption {
                switch reason {
                case .portsTaken: return .notReady(.preparing)
                 
                case .stoppedForMemory: return .notReady(.onHold)
                default: return .notReady(.unavailable)
                }
            }
             
             
            if !summary.engineInjected { return .notReady(.preparing) }
        }
        if facts.isConnected, let report = facts.report {
             
             
             
             
             
            var unusable = false
            if case .certificateUnreadable? = report.failure { unusable = true }
            if report.rung == .engineStopped, !unusable, [.starting, .running, .passThrough].contains(report.state) {
                return .notReady(.onHold)
            }
            switch report.state {
            case .starting: return .notReady(.preparing)
            case .passThrough, .failed: return .notReady(.unavailable)
            case .running:
                if unusable { return .notReady(.unavailable) }
            case .stopped:
                break  
            }
        }
        return .working
    }

     
     
    static func entry(_ facts: ModulePageFacts) -> ClashModulesEntrySnapshot {
        ClashModulesEntrySnapshot(decryptionOn: facts.state.enabled, certificateReady: facts.certificate == .ready,
                                  enabledModules: facts.state.modules.filter(\.enabled).count)
    }

     
     
    static func state(_ facts: ModulePageFacts) -> ClashModulesSnapshot.CertificateState {
        facts.certificateUnreadable ? .unreadable : state(facts.certificate)
    }

    static func state(_ state: ModuleCertificateState) -> ClashModulesSnapshot.CertificateState {
        switch state {
        case .notGenerated: return .notGenerated
        case .notInstalled: return .notInstalled
        case .installedNotTrusted: return .installedNotTrusted
        case .ready: return .ready
        }
    }

     

     
     
     
     
     
     
     
    static func certificate(_ facts: ModulePageFacts) -> ClashModulesSnapshot.Certificate {
        certificate(facts, locale: nil)
    }

     
     
     
     
    static func certificate(_ facts: ModulePageFacts, locale: Locale?) -> ClashModulesSnapshot.Certificate {
        let state = facts.certificate
        let platform = certificatePlatform(facts.platform)
        var note: AuthoredText?
        var action: ClashModulesSnapshot.CertificateAction?
        func act(_ kind: ClashModulesSnapshot.CertificateActionKind, _ title: AuthoredText) {
            action = ClashModulesSnapshot.CertificateAction(kind: kind, title: title.displayText)
        }
         
         
        var stepsFor = state
        switch (state, platform) {
        case (.ready, _):
            act(.makeNew, ModuleCertificateCopy.action(state, platform: platform))
        case (.notGenerated, .mac):
            act(.create, ModuleCertificateCopy.action(state, platform: platform))
        case (.notGenerated, .ios), (.notInstalled, .ios), (.installedNotTrusted, .ios):
            action = installAction(state)
            if state == .notGenerated { stepsFor = .notInstalled }
        case (.notInstalled, .mac), (.installedNotTrusted, .mac):
             
             
             
            if facts.keychainFallback != nil {
                act(.openInKeychainAccess, ModuleCertificateCopy.openInKeychainAccess)
            } else {
                act(.installAndTrust, ModuleCertificateCopy.action(state, platform: platform))
            }
        }
        if facts.certificateUnreadable {
             
             
             
             
            note = Copy.certificateUnreadable
            act(.makeNew, ModuleCertificateCopy.action(.ready, platform: platform))
        }
        if note == nil, !facts.isBusy, let old = facts.oldCertificateLeft {
             
             
             
             
            note = ModuleCertificateCopy.deleteOldCertificate(old)
        }
        if let failure = facts.certificateFailure { note = failure }
        let stepped = action.map(\.kind).map(namedByStepOne) == true
        let name = facts.certificateName, fallback = facts.keychainFallback
        return ClashModulesSnapshot.Certificate(
            state: Self.state(facts),
            steps: !stepped ? [] : locale.map {
                ModuleCertificateCopy.steps(stepsFor, platform: platform, certificate: name, fallback: fallback, resolvedIn: $0)
            } ?? steps(stepsFor, platform: platform, certificate: name, fallback: fallback),
            note: note?.displayText,
            action: action,
            renewWarning: ModuleCertificateCopy.regenerateWarning(platform: platform).displayText)
    }

     
     
     
     
     
    static func steps(_ state: ModuleCertificateState, platform: ModuleCertificatePlatform, certificate name: String? = nil,
                      fallback: ModuleKeychainFallback? = nil) -> [ClashDisplayText] {
        ModuleCertificateCopy.steps(state, platform: platform, certificate: name, fallback: fallback)
    }

     
     
     
    static func certificatePlatform(_ platform: ModulePlatform) -> ModuleCertificatePlatform {
        switch platform {
        case .mac: return .mac
        case .ios, .tvos: return .ios
        }
    }

     
     
     
    static func namedByStepOne(_ kind: ClashModulesSnapshot.CertificateActionKind) -> Bool {
        switch kind {
        case .installProfile, .openInKeychainAccess: return true
        case .create, .installAndTrust, .makeNew: return false
        }
    }

     

     
     
     
    enum NoticeKind: Equatable {
        case modules
        case decryption
    }

     
     
     
     
    static func kind(of reason: ModuleDegradeReason) -> NoticeKind? {
        switch reason {
        case .certificateNotTrusted, .certificateMissing:
            return nil  
        case .certificateUnusable, .stoppedForMemory:
             
             
            return .decryption
        case .noCertificateAddress:
             
             
             
            return nil
        case .moduleRulesLeftOut, .moduleEntriesLeftOut, .moduleSettingsLeftOut, .notApplied, .snifferWrittenOff, .snifferNotCompleted:
            return .modules
        case .engineUnavailable, .portsTaken, .groupsNotAdjustable, .sectionNotAdjustable, .alreadyPublished, .engineNameTaken:
            return .decryption
        }
    }

     
     
     
     
     
     
     
     
    static func notices(_ facts: ModulePageFacts, decryptionOn: Bool, locale: Locale) -> [ClashModulesSnapshot.Notice] {
        var out: [ClashModulesSnapshot.Notice] = []
        var said: [AuthoredText: Int] = [:]
        func add(_ kind: NoticeKind, _ id: String, _ text: AuthoredText, action: ClashModulesSnapshot.NoticeAction? = nil,
                 shown: ClashDisplayText? = nil, place: ClashModulesSnapshot.NoticePlace? = nil) {
            guard decryptionOn || kind == .modules else { return }
            if let index = said[text] {
                 
                 
                if out[index].action == nil, let action {
                    out[index].action = action
                    out[index].actionTitle = title(for: action)
                }
                return
            }
            said[text] = out.count
             
            out.append(.init(id: id, text: shown ?? text.displayText, action: action, actionTitle: action.map(title(for:)),
                             tone: ModuleEngineInsight.Copy.onHold.contains(text) ? .onHold : .attention, place: place))
        }
         
        if let failure = facts.actionFailure { add(.modules, "action", actionNotice(failure, facts, locale: locale)) }
        if let notApplied = facts.summary?.notApplied {
            add(.modules, "not-applied", ModuleStoredSentence.current(notApplied))
        }
         
         
        var decrypting = false
        for reason in facts.summary?.reasons ?? [] {
            guard let about = kind(of: reason) else { continue }
            if about == .decryption {
                guard !decrypting else { continue }
                decrypting = true
            }
            add(about, "reason-" + reason.spelling, reason.authoredText, action: tryAgain(reason) ? .retryAfterMemoryStop : nil,
                shown: shown(reason, on: facts.platform, locale: locale), place: place(of: reason, profileID: facts.summary?.profileID))
        }
         
         
        let insight = ModuleEngineInsight.read(facts.isConnected ? facts.report : nil)
        for (index, notice) in insight.notices.enumerated() {
            if tryAgain(notice, rung: insight.rung) {
                add(.decryption, "memory", notice, action: .retryAfterMemoryStop)
            } else {
                add(.decryption, "report-\(index)", notice)
            }
        }
         
        return out
    }

     
     
     
     
    static func shown(_ reason: ModuleDegradeReason) -> ClashDisplayText {
        switch reason {
        case .snifferWrittenOff, .snifferNotCompleted:
            guard case .app(let key, let names) = reason.authoredText else { return reason.authoredText.displayText }
            return .formatCopy(key, names)
        case .engineUnavailable, .certificateNotTrusted, .certificateMissing, .certificateUnusable, .stoppedForMemory,
             .portsTaken, .noCertificateAddress, .groupsNotAdjustable, .sectionNotAdjustable, .alreadyPublished,
             .moduleRulesLeftOut, .moduleEntriesLeftOut, .moduleSettingsLeftOut, .engineNameTaken, .notApplied:
            return reason.authoredText.displayText
        }
    }

     
     
     
    static func shown(_ reason: ModuleDegradeReason, on platform: ModulePlatform, locale: Locale,
                      copy: ConfigurationFieldCopy = .shared) -> ClashDisplayText {
        guard platform == .mac, let words = macSnifferNotice(reason, locale: locale, copy: copy) else { return shown(reason) }
        return words
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    static func macSnifferNotice(_ reason: ModuleDegradeReason, locale: Locale,
                                 copy: ConfigurationFieldCopy) -> ClashDisplayText? {
         
         
         
        let language = ConfigurationFieldCopy.Language.shown(in: locale)
        let chapter = "sniffer"
        func title(_ path: String) -> String? { copy.entry(forPath: path, language: language)?.title }
        switch reason {
        case .snifferWrittenOff(let keys):
            let needed = ModuleDegradeReason.snifferKeys(keys)
            let order = copy.layout(forPath: chapter, language: language)?.flatMap(\.keys) ?? []
            var seen = Set<String>()
            let names = (order.filter { needed.contains($0) && seen.insert($0).inserted } + needed.filter { !seen.contains($0) })
                .compactMap { title(chapter + "." + $0) }
            guard !names.isEmpty else {
                guard let section = title(chapter) else { return nil }
                return .format(ModuleDegradeReason.macSnifferWrittenOffInSectionSentence, [section])
            }
            return .format(ModuleDegradeReason.macSnifferWrittenOffSentence(count: names.count), names)
        case .snifferNotCompleted:
            guard let enable = title(chapter + ".enable") else { return nil }
            return .format(ModuleDegradeReason.macSnifferNotCompletedSentence, [enable])
        case .engineUnavailable, .certificateNotTrusted, .certificateMissing, .certificateUnusable, .stoppedForMemory,
             .portsTaken, .noCertificateAddress, .groupsNotAdjustable, .sectionNotAdjustable, .alreadyPublished,
             .moduleRulesLeftOut, .moduleEntriesLeftOut, .moduleSettingsLeftOut, .engineNameTaken, .notApplied:
            return nil
        }
    }

     
     
     
     
     
     
     
     
    static func place(of reason: ModuleDegradeReason, profileID: String?) -> ClashModulesSnapshot.NoticePlace? {
        switch reason {
        case .snifferWrittenOff, .snifferNotCompleted:
            return profileID.map { .snifferSettings(profileID: $0) }
        case .engineUnavailable, .certificateNotTrusted, .certificateMissing, .certificateUnusable, .stoppedForMemory,
             .portsTaken, .noCertificateAddress, .groupsNotAdjustable, .sectionNotAdjustable, .alreadyPublished,
             .moduleRulesLeftOut, .moduleEntriesLeftOut, .moduleSettingsLeftOut, .engineNameTaken, .notApplied:
            return nil
        }
    }

     
     
     
     
     
     
    static func tryAgain(_ reason: ModuleDegradeReason) -> Bool {
        switch reason {
        case .engineUnavailable, .certificateUnusable:
            return true
        case .stoppedForMemory, .certificateNotTrusted, .certificateMissing, .portsTaken, .noCertificateAddress,
             .groupsNotAdjustable, .sectionNotAdjustable, .alreadyPublished, .moduleRulesLeftOut, .moduleEntriesLeftOut,
             .moduleSettingsLeftOut, .engineNameTaken, .notApplied, .snifferWrittenOff, .snifferNotCompleted:
            return false
        }
    }

     
     
     
    static func tryAgain(_ notice: AuthoredText, rung: ModuleEngineReport.Rung) -> Bool {
        notice == ModuleDegradeReason.certificateUnusable.authoredText
            || notice == ModuleDegradeReason.engineUnavailable.authoredText
    }

     
     
     
    static func actionNotice(_ failure: AuthoredText, _ facts: ModulePageFacts, locale: Locale) -> AuthoredText {
        let failure = ModuleStoredSentence.current(failure)
        if failure == ModuleStoreError.editSuperseded.authoredText,
           let record = facts.state.modules.first(where: { $0.id == facts.actionModuleID }) {
            return Copy.changedElsewhere(row(record, ir: nil, locale: locale).name)
        }
        return failure
    }

     
    static func title(for action: ClashModulesSnapshot.NoticeAction) -> ClashDisplayText {
        switch action {
        case .retryAfterMemoryStop: return "Try Again"
        case .runScriptAgain: return "Run Again"
        }
    }

     

     
     
     
     
     
     
     
     
     
     
     
    static func row(_ record: ModuleRecord, ir: ModuleIR?, locale: Locale,
                    decryption: ModuleDetailBuilder.Decryption = .working,
                    written: [Substring]? = nil) -> ClashModulesSnapshot.ModuleRow {
        let source: ClashModuleSource
        var link: String?
        switch record.origin {
        case .url(let added):
            source = .link(URL(string: added)?.host ?? added)
             
            link = added
        case .local: source = .local
         
        case .unknown: source = .unknown
        }
        let name = shownName(record, locale: locale)
         
        let failed = record.lastFailure != nil || record.failureFromALaterBuild
        let failure: ClashDisplayText? = failed && source != .local ? "Update failed" : nil
        let counts = ir.map { ModuleDetailBuilder.counts($0, decryption: decryption, written: written) }
         
         
        let waiting = record.enabled ? counts?.waiting ?? 0 : 0
        return ClashModulesSnapshot.ModuleRow(
            id: record.id, name: name, source: source, updatedAt: record.lastUpdatedAt,
            effectiveCount: counts?.shown(enabled: record.enabled) ?? 0,
            ignoredCount: ir?.ignoredCount ?? 0, enabled: record.enabled,
            failure: failure, link: link,
            waitingCount: waiting, waitsFor: waiting > 0 ? decryption.wait : nil)
    }

     
     
    static func shownName(_ record: ModuleRecord, locale: Locale) -> String {
        record.displayName.isEmpty ? ownName(record, locale: locale) : record.displayName
    }

     
     
    static func ownName(_ record: ModuleRecord, locale: Locale) -> String {
        record.name.isEmpty ? ClashCopy.string(for: Copy.untitledModule.displayText, locale: locale) : record.name
    }

     

     
     
     
     
    enum Copy {
         
        static let untitledModule: AuthoredText = .app("Untitled Module")
         
         
        static let certificatePageUnavailable: AuthoredText = .app("The certificate page can't open right now; try again later.")
         
         
         
        static let certificateUnreadable: AuthoredText =
            .app("The certificate couldn't be read. Make a new one, then install and trust it again.")
         
         
        static func changedElsewhere(_ name: String) -> AuthoredText {
            .app("“%@” was just changed elsewhere; open it again.", arguments: [name])
        }
         
        static let panelNeedsConnection: AuthoredText = .app("Connect to refresh")
         
         
         
        static let panelFailed: AuthoredText = .app("It didn't refresh; try again")
         
         
        static let panelScriptMissing: AuthoredText = .app("Not Available Yet")
        static var every: [AuthoredText] {
            [untitledModule, certificatePageUnavailable, certificateUnreadable, changedElsewhere("Zhihu"), panelNeedsConnection,
             panelFailed, panelScriptMissing]
        }
    }
}
#endif
